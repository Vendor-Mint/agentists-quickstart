#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────
# DevContainer on-create setup script
# Installs cloud tools, CLI utilities and AI tools
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

# ─── Step 1: Google Cloud CLI ────────────────────
install_gcloud() {
  log_step 1 "Installing Google Cloud CLI"
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get update -qq
  sudo apt-get install -y -qq apt-transport-https ca-certificates gnupg curl > /dev/null
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list > /dev/null
  sudo apt-get update -qq && sudo apt-get install -y -qq google-cloud-cli > /dev/null
  echo "  ✓ gcloud $(gcloud version --format='value(Google Cloud SDK)' 2>/dev/null || echo 'installed')"
}

# ─── Step 2: Cloudflare tools ────────────────────
install_cloudflare() {
  log_step 2 "Installing Cloudflare tools"

  # Wrangler CLI
  npm install -g wrangler --silent
  echo "  ✓ wrangler $(wrangler --version 2>/dev/null || echo 'installed')"

  # Cloudflared tunnel — architecture-aware
  local deb_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb"
  curl -fsSL --output /tmp/cloudflared.deb "$deb_url"
  sudo dpkg -i /tmp/cloudflared.deb > /dev/null
  rm -f /tmp/cloudflared.deb
  echo "  ✓ cloudflared $(cloudflared --version 2>/dev/null || echo 'installed')"
}

# ─── Step 3: AI tools ────────────────────────────
install_ai_tools() {
  log_step 3 "Installing Claude Code & Jira MCP"
  npm install -g @anthropic-ai/claude-code --silent
  echo "  ✓ claude-code installed"

  npm install -g @modelcontextprotocol/server-jira --silent
  echo "  ✓ jira-mcp-server installed"
}

# ─── Run all steps ───────────────────────────────
for step_fn in install_gcloud install_cloudflare install_ai_tools; do
  if ! $step_fn; then
    FAILED_STEPS+=("$step_fn")
    echo "  ✗ $step_fn failed — continuing with remaining steps"
  fi
done

# ─── Cleanup ─────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════"
sudo apt-get clean > /dev/null 2>&1
sudo rm -rf /var/lib/apt/lists/*

if [ ${#FAILED_STEPS[@]} -eq 0 ]; then
  echo "  ✅ All tools installed successfully"
else
  echo "  ⚠️  Completed with errors in: ${FAILED_STEPS[*]}"
  echo "  Run failed steps manually to troubleshoot."
fi
echo "══════════════════════════════════════════════"
