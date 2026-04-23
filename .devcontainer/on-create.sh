#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────
# DevContainer on-create setup script
# Installs browser deps, MCP servers and AI tools
# ─────────────────────────────────────────────────

ARCH=$(dpkg --print-architecture)  # amd64 | arm64
TOTAL_STEPS=3
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
  # Force onboarding as completed to avoid interactive prompts
  echo '{"hasCompletedOnboarding": true}' > ~/.claude.json
}

# ─── Step 1: Playwright (Chromium only) ──────────
install_playwright() {
  log_step 1 "Installing Playwright with Chromium"
  npx -y playwright install --with-deps chromium
  echo "  ✓ Playwright + Chromium installed"
}

# ─── Step 2: Install Claude Code ─────────────────
install_claude() {
  log_step 2 "Installing Claude Code CLI"
  curl -fsSL https://claude.ai/install.sh | bash
  echo "  ✓ Claude Code CLI installed"

  # Run initialization
  init_claude
}

# ─── Step 3: Configure Claude Code MCPs ──────────
configure_mcps() {
  log_step 3 "Configuring Claude Code MCP servers"

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
  claude mcp add playwright -s user -- npx -y @playwright/mcp@latest
  echo "  ✓ MCP: playwright"

  # GitHub MCP (authenticates via GitHub CLI extension 'gh-mcp')
  # Requires 'gh auth login' in the terminal
  gh extension install shuymn/gh-mcp --force
  claude mcp add github -s user -- gh mcp
  echo "  ✓ MCP: github (via gh CLI)"

  # Context7 MCP (using API key from env)
  claude mcp add context7 -s user -e CONTEXT7_API_KEY="$CONTEXT7_API_KEY" -- npx -y @upstash/context7-mcp@latest
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
for step_fn in install_playwright install_claude configure_mcps; do
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
