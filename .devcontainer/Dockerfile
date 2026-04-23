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
USER root
# Symlink to /usr/local/bin so 'claude' is available in any shell session
RUN ln -s /home/vscode/.claude/local/bin/claude /usr/local/bin/claude

# ─── Dev Container metadata for VS Code "Attach" mode ─
# When attaching to a K8s pod, VS Code reads this label to auto-install
# extensions, apply settings, and set the remote user (instead of root).
LABEL devcontainer.metadata='[ \
  { \
    "remoteUser": "vscode", \
    "customizations": { \
      "vscode": { \
        "extensions": [ \
          "eamodio.gitlens", \
          "esbenp.prettier-vscode", \
          "ms-python.python", \
          "ms-python.debugpy", \
          "ms-python.black-formatter", \
          "ms-dotnettools.csharp", \
          "ms-dotnettools.csdevkit", \
          "ms-azuretools.vscode-docker", \
          "redhat.vscode-yaml", \
          "rangav.vscode-thunder-client", \
          "googlecloudtools.cloudcode", \
          "ms-toolsai.jupyter" \
        ], \
        "settings": { \
          "terminal.integrated.defaultProfile.linux": "zsh", \
          "editor.formatOnSave": true \
        } \
      } \
    } \
  } \
]'

# ─── Cleanup ─────────────────────────────────────
RUN apt-get clean \
    && rm -rf /var/lib/apt/lists/*
