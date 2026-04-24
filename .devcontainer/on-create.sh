#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────
# DevContainer on-create setup script
# Installs browser deps, MCP servers and AI tools
# ─────────────────────────────────────────────────

ARCH=$(dpkg --print-architecture)  # amd64 | arm64
TOTAL_STEPS=4
FAILED_STEPS=()

log_step() {
  local step=$1
  local name=$2
  echo ""
  echo "══════════════════════════════════════════════"
  echo "  [$step/$TOTAL_STEPS] $name"
  echo "══════════════════════════════════════════════"
}

# ─── Pre-step: Initialize Claude Config ──────────
init_claude() {
  echo "  ⚙ Initializing Claude configuration..."
  # Force onboarding as completed and set permissions to bypass completely
  echo '{"hasCompletedOnboarding": true}' > ~/.claude.json
  echo '{"permissions": {"defaultMode": "bypassPermissions"}}' > ~/.claude/settings.json
}

# ─── Step 1: Install Claude Code ─────────────────
install_claude() {
  log_step 1 "Installing Claude Code CLI"
  curl -fsSL https://claude.ai/install.sh | bash
  echo "  ✓ Claude Code CLI installed"

  # Run initialization
  init_claude
}

# ─── Step 2: Load Kubernetes Secrets ─────────────
load_secrets() {
  log_step 2 "Loading secrets from Kubernetes"

  # 1. Get the namespace injected by Kubernetes into the Pod
  local namespace
  namespace=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
  
  # 2. Extract the DEV_NAME (removing 'dev-' prefix) to construct the secret name
  local dev_name=${namespace#dev-}
  local secret_name="${dev_name}-api-secrets"

  echo "  🔒 Fetching credentials from secret: $secret_name in $namespace"

  # 3. Validate that the secret exists before attempting to read it
  local k8s_response
  if ! k8s_response=$(sudo -E kubectl get secret "$secret_name" -n "$namespace" 2>&1); then
    echo "  ❌ ERROR from Kubernetes API:"
    echo "     $k8s_response"
    return 1
  fi

  # 4. Extract, decode, and export the variables to the environment
  export CONTEXT7_API_KEY=$(sudo -E kubectl get secret "$secret_name" -n "$namespace" -o jsonpath="{.data.CONTEXT7_API_KEY}" | base64 --decode)
  echo "  ✓ CONTEXT7_API_KEY successfully loaded"

  export CLAUDE_CODE_OAUTH_TOKEN=$(sudo -E kubectl get secret "$secret_name" -n "$namespace" -o jsonpath="{.data.CLAUDE_CODE_OAUTH_TOKEN}" | base64 --decode)
  echo "  ✓ CLAUDE_CODE_OAUTH_TOKEN successfully loaded"

  sudo tee /etc/profile.d/api-secrets.sh > /dev/null <<-EOF
		export CONTEXT7_API_KEY='${CONTEXT7_API_KEY}'
		export CLAUDE_CODE_OAUTH_TOKEN='${CLAUDE_CODE_OAUTH_TOKEN}'
	EOF

  sudo chmod 644 /etc/profile.d/api-secrets.sh

  if ! grep -q "source /etc/profile.d/api-secrets.sh" ~/.zshrc 2>/dev/null; then
    echo "source /etc/profile.d/api-secrets.sh" >> ~/.zshrc
  fi
}

# ─── Step 3: Install Cloud SQL Auth Proxy ────────
install_cloud_sql_proxy() {
  log_step 3 "Installing Cloud SQL Auth Proxy"

  # Install the official Cloud SQL Auth Proxy
  curl -o cloud-sql-proxy https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.21.1/cloud-sql-proxy.linux.amd64

  # Grant execute permissions and move it to the PATH
  chmod +x cloud-sql-proxy
  sudo mv cloud-sql-proxy /usr/local/bin/
  
  echo "  ✓ Cloud SQL Auth Proxy installed"
}

# ─── Step 4: Configure Claude Code MCPs ──────────
configure_mcps() {
  log_step 4 "Configuring Claude Code MCP servers"

  # Wait for claude to be available
  if ! command -v claude &> /dev/null; then
    # Try to add ~/.local/bin to PATH if not already there
    export PATH="$HOME/.local/bin:$PATH"
  fi

  if ! command -v claude &> /dev/null; then
    echo "  ⚠ claude not found, skipping MCP configuration"
    return 1
  fi

  # Playwright MCP
  claude mcp add playwright -s user -- npx -y @playwright/mcp@latest --browser chromium
  echo "  ✓ MCP: playwright"

  # GitHub MCP (authenticates via GitHub CLI extension 'gh-mcp')
  # Requires 'gh auth login' in the terminal
  gh extension install shuymn/gh-mcp --force
  claude mcp add github -s user -- gh mcp
  echo "  ✓ MCP: github (via gh CLI)"

  # Context7 MCP (using API key from env)
  claude mcp add --scope user context7 -- npx -y @upstash/context7-mcp --api-key "$CONTEXT7_API_KEY"
  echo "  ✓ MCP: context7"

  # Filesystem MCP
  claude mcp add server-filesystem -s user -- npx -y @modelcontextprotocol/server-filesystem /workspaces
  echo "  ✓ MCP: server-filesystem"

  # Atlassian (Jira + Confluence) MCP via OAuth — browser auth on first use
  claude mcp add atlassian --transport sse https://mcp.atlassian.com/v1/sse -s user
  echo "  ✓ MCP: atlassian (Jira/Confluence via OAuth)"

  echo "  ✓ All MCP servers configured"
}

# ─── Run all steps ───────────────────────────────
for step_fn in install_claude load_secrets install_cloud_sql_proxy configure_mcps; do
  if ! $step_fn; then
    FAILED_STEPS+=("$step_fn")
    echo "  ✗ $step_fn failed — continuing with remaining steps"
  fi
done

# ─── Cleanup ─────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════"
sudo apt-get clean > /dev/null 2>&1 || true
sudo rm -rf /var/lib/apt/lists/* 2>/dev/null || true

if [ ${#FAILED_STEPS[@]} -eq 0 ]; then
  echo "  ✅ All tools installed successfully"
else
  echo "  ⚠️  Completed with errors in: ${FAILED_STEPS[*]}"
  echo "  Run failed steps manually to troubleshoot."
fi
echo "══════════════════════════════════════════════"
