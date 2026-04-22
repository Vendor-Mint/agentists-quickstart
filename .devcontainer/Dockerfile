FROM mcr.microsoft.com/devcontainers/base:ubuntu

ARG DEBIAN_FRONTEND=noninteractive

# ─── Google Cloud CLI ────────────────────────────
RUN apt-get update -qq \
    && apt-get install -y -qq apt-transport-https ca-certificates gnupg curl > /dev/null \
    && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
       | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
       | tee /etc/apt/sources.list.d/google-cloud-sdk.list > /dev/null \
    && apt-get update -qq \
    && apt-get install -y -qq google-cloud-cli > /dev/null

# ─── Cloudflare tunnel (architecture-aware) ──────
ARG TARGETARCH
RUN curl -fsSL --output /tmp/cloudflared.deb \
       "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${TARGETARCH}.deb" \
    && dpkg -i /tmp/cloudflared.deb > /dev/null \
    && rm -f /tmp/cloudflared.deb

# ─── Node.js (required for npm-based tools below) ─
# The devcontainer 'node' feature will detect this installation
# and manage version switching via nvm on top of it.
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y -qq nodejs > /dev/null

# ─── Cloudflare Wrangler CLI ─────────────────────
RUN npm install -g wrangler --silent

# ─── MCP Servers ─────────────────────────────────
RUN npm install -g @modelcontextprotocol/server-jira --silent
RUN npm install -g @modelcontextprotocol/server-github --silent
RUN npm install -g @upstash/context7-mcp --silent
RUN npm install -g @modelcontextprotocol/server-filesystem --silent

# ─── Playwright MCP + Chromium ───────────────────
RUN npm install -g @playwright/mcp@latest --silent
RUN npx playwright install --with-deps chromium

# ─── Claude Code (official installer as vscode user) ─
USER vscode
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/home/vscode/.claude/local/bin:${PATH}"
USER root

# ─── Cleanup ─────────────────────────────────────
RUN apt-get clean \
    && rm -rf /var/lib/apt/lists/*
