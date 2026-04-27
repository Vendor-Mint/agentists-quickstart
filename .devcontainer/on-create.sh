#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────
# DevContainer on-create setup script
# Installs browser deps, MCP servers and AI tools
# ─────────────────────────────────────────────────

ARCH=$(dpkg --print-architecture)  # amd64 | arm64
TOTAL_STEPS=5
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

  # 2. Extract the DEV_NAME (removing 'dev-' prefix) to construct the secret name.
  #    Exported so later steps (e.g. cloudflared) can reuse it.
  export DEV_NAME=${namespace#dev-}
  local secret_name="${DEV_NAME}-api-secrets"

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

  export CLOUDFLARED_TOKEN=$(sudo -E kubectl get secret "$secret_name" -n "$namespace" -o jsonpath="{.data.CLOUDFLARED_TOKEN}" | base64 --decode)
  if [ -n "$CLOUDFLARED_TOKEN" ]; then
    echo "  ✓ CLOUDFLARED_TOKEN successfully loaded"
  else
    echo "  ⚠ CLOUDFLARED_TOKEN is empty — tunnel configuration will be skipped"
  fi

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

# ─── Step 5: Configure Cloudflared Tunnel ────────
configure_cloudflared() {
  log_step 5 "Configuring Cloudflared tunnel"

  if [ -z "${CLOUDFLARED_TOKEN:-}" ]; then
    echo "  ⚠ CLOUDFLARED_TOKEN not set, skipping tunnel configuration"
    return 0
  fi

  if ! command -v cloudflared &>/dev/null; then
    echo "  ✗ cloudflared binary not found"
    return 1
  fi

  # The tunnel token is base64-encoded JSON: {"a":"<account>","t":"<tunnel id>","s":"<secret>"}
  local decoded
  if ! decoded=$(printf '%s' "$CLOUDFLARED_TOKEN" | base64 -d 2>/dev/null); then
    echo "  ✗ Failed to base64-decode CLOUDFLARED_TOKEN"
    return 1
  fi

  local account_tag tunnel_id tunnel_secret
  account_tag=$(printf '%s' "$decoded" | python3 -c 'import json,sys; print(json.load(sys.stdin)["a"])') || {
    echo "  ✗ Failed to parse account tag from token"
    return 1
  }
  tunnel_id=$(printf '%s' "$decoded" | python3 -c 'import json,sys; print(json.load(sys.stdin)["t"])')
  tunnel_secret=$(printf '%s' "$decoded" | python3 -c 'import json,sys; print(json.load(sys.stdin)["s"])')

  local cf_dir="$HOME/.cloudflared"
  mkdir -p "$cf_dir"
  chmod 700 "$cf_dir"

  # Credentials file expected by `cloudflared tunnel run` when using config.yml
  local creds_file="$cf_dir/${tunnel_id}.json"
  printf '{"AccountTag":"%s","TunnelID":"%s","TunnelSecret":"%s"}\n' \
    "$account_tag" "$tunnel_id" "$tunnel_secret" > "$creds_file"
  chmod 600 "$creds_file"
  echo "  ✓ Wrote credentials file: $creds_file"

  # Render config.yml from the template shipped in this repo. If the user already
  # customized their config.yml (e.g. added ingress rules), do not overwrite it.
  local template=".devcontainer/cloudflared/config.yml.template"
  local config_file="$cf_dir/config.yml"

  if [ ! -f "$template" ]; then
    echo "  ⚠ Template not found at $template, skipping config.yml generation"
  elif [ -f "$config_file" ]; then
    echo "  ✓ Existing $config_file preserved (not overwritten)"
  else
    DEV_NAME="${DEV_NAME}" TUNNEL_ID="${tunnel_id}" \
      envsubst '${DEV_NAME} ${TUNNEL_ID}' < "$template" > "$config_file"
    chmod 600 "$config_file"
    echo "  ✓ Rendered $config_file"
  fi

  echo ""
  echo "  ℹ Tunnel is NOT auto-started. To expose your apps:"
  echo "      1. Edit $config_file and add one ingress rule per app."
  echo "      2. Start the tunnel with: cloudflared tunnel run"
  echo "      3. Apps will be reachable at https://<app>.${DEV_NAME}.dev.vendormint.ai"
}

# ─── Run all steps ───────────────────────────────
for step_fn in install_claude load_secrets install_cloud_sql_proxy configure_mcps configure_cloudflared; do
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
