#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════════
# 🚀 Agentists QuickStart - Batteries Included Launcher
# ═══════════════════════════════════════════════════════════════════════════════
# This script launches Claude Code in a tmux session
# with proper configuration and error handling.
# ═══════════════════════════════════════════════════════════════════════════════

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Phonetic alphabet for tmux sessions
PHONETIC_NAMES=("alpha" "bravo" "charlie" "delta" "echo" "foxtrot" "golf" "hotel" "india" "juliet" "kilo" "lima" "mike" "november" "oscar" "papa" "quebec" "romeo" "sierra" "tango" "uniform" "victor" "whiskey" "xray" "yankee" "zulu")

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to print section headers
print_header() {
    local header=$1
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${BOLD}${header}${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Function to print error messages and exit
error_exit() {
    local message=$1
    print_message "$RED" "❌ ERROR: $message"
    echo ""
    print_message "$YELLOW" "💡 Troubleshooting tips:"
    echo "   1. Ensure all required tools are installed by running: .devcontainer/install-tools.sh"
    echo "   2. Check the installation report: cat .devcontainer/installation-report.md"
    echo "   3. Verify Node.js and npm are available: node --version && npm --version"
    echo "   4. For tmux issues, try: sudo apt-get install tmux"
    echo ""
    exit 1
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to find next available tmux session name
find_tmux_session() {
    for name in "${PHONETIC_NAMES[@]}"; do
        if ! tmux has-session -t "$name" 2>/dev/null; then
            echo "$name"
            return 0
        fi
    done
    # If all phonetic names are taken, use a timestamp
    echo "session-$(date +%s)"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN SCRIPT START
# ═══════════════════════════════════════════════════════════════════════════════

print_header "🚀 Agentists QuickStart - Batteries Included"

# Step 1: Check prerequisites
print_message "$BLUE" "📋 Checking prerequisites..."

# Check for Node.js
if ! command_exists node; then
    error_exit "Node.js is not installed. Please install Node.js first."
fi

# Check for npm
if ! command_exists npm; then
    error_exit "npm is not installed. Please install npm first."
fi

# Check for tmux
if ! command_exists tmux; then
    print_message "$YELLOW" "⚠️  tmux is not installed. Attempting to install..."
    
    if command_exists apt-get; then
        if sudo apt-get install -y tmux >/dev/null 2>&1; then
            print_message "$GREEN" "✅ tmux installed successfully"
        else
            error_exit "Failed to install tmux. Please install it manually: sudo apt-get install tmux"
        fi
    else
        error_exit "tmux is not installed and automatic installation is not available on this system."
    fi
fi

# Check for claude command (Claude Code)
if ! command_exists claude; then
    print_message "$YELLOW" "⚠️  Claude Code is not installed. Attempting to install..."
    
    if npm install -g @anthropic-ai/claude-code 2>/dev/null || sudo npm install -g @anthropic-ai/claude-code 2>/dev/null; then
        print_message "$GREEN" "✅ Claude Code installed successfully"
    else
        error_exit "Failed to install Claude Code. Please install it manually: npm install -g @anthropic-ai/claude-code"
    fi
fi

print_message "$GREEN" "✅ All prerequisites are installed"

# Step 2: Check for .mcp.json configuration
print_header "📦 MCP Configuration Check"

MCP_CONFIG_PATH="${WORKSPACE_FOLDER:-$(pwd)}/.mcp.json"
MCP_CONFIG_EXISTS=false

if [ -f "$MCP_CONFIG_PATH" ]; then
    print_message "$GREEN" "✅ Found .mcp.json configuration at: $MCP_CONFIG_PATH"
    MCP_CONFIG_EXISTS=true
else
    print_message "$YELLOW" "⚠️  No .mcp.json configuration found at: $MCP_CONFIG_PATH"
    print_message "$BLUE" "💡 Claude Code will run without MCP configuration"
fi

# Step 3: Create tmux session
print_header "🖥️  Tmux Session Management"

# Find available session name
SESSION_NAME=$(find_tmux_session)
print_message "$BLUE" "🔍 Selected tmux session name: ${BOLD}$SESSION_NAME${NC}"

# Check if session already exists (shouldn't happen due to find_tmux_session, but double-check)
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    print_message "$YELLOW" "⚠️  Session '$SESSION_NAME' already exists. Attaching to it..."
    tmux attach-session -t "$SESSION_NAME"
    exit 0
fi

# Step 4: Launch Claude Code in tmux
print_header "🚀 Launching Claude Code"

print_message "$BLUE" "📝 Creating tmux session: $SESSION_NAME"

# Prepare the Claude Code command
if [ "$MCP_CONFIG_EXISTS" = true ]; then
    CLAUDE_CMD="claude --dangerously-skip-permissions --mcp-config $MCP_CONFIG_PATH"
    print_message "$GREEN" "✅ Launching Claude Code with MCP configuration"
else
    CLAUDE_CMD="claude --dangerously-skip-permissions"
    print_message "$YELLOW" "⚠️  Launching Claude Code without MCP configuration"
fi

# Create tmux session and run Claude Code
if tmux new-session -d -s "$SESSION_NAME" "$CLAUDE_CMD" 2>/dev/null; then
    print_message "$GREEN" "✅ Claude Code launched successfully in tmux session: $SESSION_NAME"
    echo ""
    print_header "📌 Session Information"
    
    echo -e "${GREEN}Session created successfully!${NC}"
    echo ""
    echo "📋 Tmux Commands Reference:"
    echo "  • Attach to session:  ${CYAN}tmux attach -t $SESSION_NAME${NC}"
    echo "  • Detach from session: ${CYAN}Ctrl+b, then d${NC}"
    echo "  • List sessions:       ${CYAN}tmux ls${NC}"
    echo "  • Kill session:        ${CYAN}tmux kill-session -t $SESSION_NAME${NC}"
    echo "  • Switch windows:      ${CYAN}Ctrl+b, then n (next) or p (previous)${NC}"
    echo "  • Create new window:   ${CYAN}Ctrl+b, then c${NC}"
    echo ""
    
    # Automatically attach to the session
    print_message "$BLUE" "🔗 Attaching to session..."
    tmux attach-session -t "$SESSION_NAME"
else
    error_exit "Failed to create tmux session. Please check tmux installation and permissions."
fi

# Step 5: Success message
echo ""
print_header "✅ Setup Complete!"

print_message "$GREEN" "🎉 Your Batteries-Included development environment is ready!"
echo ""
echo "Resources:"
echo "  • Claude Code Docs: https://docs.anthropic.com/en/docs/claude-code"
echo "  • Report Issues:    https://github.com/jedarden/agentists-quickstart/issues"
echo ""
print_message "$CYAN" "Happy coding! 🚀"