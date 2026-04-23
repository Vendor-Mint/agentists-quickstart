#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────
# DevContainer on-create setup script
# Installs browser deps, MCP servers and AI tools
# ─────────────────────────────────────────────────

ARCH=$(dpkg --print-architecture)  # amd64 | arm64
TOTAL_STEPS=2
FAILED_STEPS=()

log_step() {
  local step=$1
  local name=$2
  echo ""
  echo "══════════════════════════════════════════════"
  echo "  [$step/$TOTAL_STEPS] $name"
  echo "══════════════════════════════════════════════"
}

# ─── Step 1: Playwright (Chromium only) ──────────
install_playwright() {
  log_step 1 "Installing Playwright with Chromium"
  npx -y playwright install --with-deps chromium
  echo "  ✓ Playwright + Chromium installed"
}

# ─── Step 2: Configure Claude Code MCPs ──────────
configure_mcps() {
  log_step 2 "Configuring Claude Code MCP servers"

  # Wait for claude to be available (installed via feature)
  if ! command -v claude &> /dev/null; then
    echo "  ⚠ claude not found, skipping MCP configuration"
    return 1
  fi

  # Playwright MCP
  claude mcp add playwright -s user -- npx -y @playwright/mcp@latest
  echo "  ✓ MCP: playwright"

  # GitHub MCP (uses GITHUB_PERSONAL_ACCESS_TOKEN from env)
  claude mcp add github -s user -e GITHUB_PERSONAL_ACCESS_TOKEN -- npx -y @modelcontextprotocol/server-github
  echo "  ✓ MCP: github"

  # Context7 MCP (no API key needed — free public service)
  claude mcp add context7 -s user -- npx -y @upstash/context7-mcp@latest
  echo "  ✓ MCP: context7"

  # Filesystem MCP
  claude mcp add server-filesystem -s user -- npx -y @modelcontextprotocol/server-filesystem /workspaces
  echo "  ✓ MCP: server-filesystem"

  # Atlassian (Jira + Confluence) MCP via OAuth — browser auth on first use
  claude mcp add atlassian --url https://mcp.atlassian.com/v1/sse -s user
  echo "  ✓ MCP: atlassian (Jira/Confluence via OAuth)"

  echo "  ✓ All MCP servers configured"
}

# ─── Run all steps ───────────────────────────────
for step_fn in install_playwright configure_mcps; do
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
