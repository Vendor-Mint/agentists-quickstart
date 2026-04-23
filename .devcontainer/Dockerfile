FROM mcr.microsoft.com/devcontainers/base:ubuntu

ARG DEBIAN_FRONTEND=noninteractive

# ─── Node.js (required for npm-based tools below) ─
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y -qq nodejs > /dev/null

# ─── MCP Servers ─────────────────────────────────
RUN npm install -g @aashari/mcp-server-atlassian-jira --silent
RUN npm install -g github-mcp-server --silent
RUN npm install -g @upstash/context7-mcp --silent
RUN npm install -g @modelcontextprotocol/server-filesystem --silent
RUN npm install -g @playwright/mcp@latest --silent

# ─── Claude Code (official installer as vscode user) ─
USER vscode
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/home/vscode/.claude/local/bin:${PATH}"
USER root

# ─── Cleanup ─────────────────────────────────────
RUN apt-get clean \
    && rm -rf /var/lib/apt/lists/*
