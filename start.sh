#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_DIR="$SCRIPT_DIR/.tmux"
TMUX_CONF="$TMUX_DIR/tmux.conf"
TPM_DIR="$TMUX_DIR/plugins/tpm"

# Phonetic alphabet for tmux session naming
PHONETIC_ALPHABET=(
    "alpha" "bravo" "charlie" "delta" "echo" "foxtrot" "golf" "hotel"
    "india" "juliet" "kilo" "lima" "mike" "november" "oscar" "papa"
    "quebec" "romeo" "sierra" "tango" "uniform" "victor" "whiskey"
    "xray" "yankee" "zulu"
)

# Find the first available phonetic name for a tmux session
find_available_session_name() {
    for name in "${PHONETIC_ALPHABET[@]}"; do
        if ! tmux has-session -t "$name" 2>/dev/null; then
            echo "$name"
            return 0
        fi
    done
    return 1
}

# Install tmux if not present
install_tmux() {
    echo "Installing tmux..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y tmux
    elif command -v yum &>/dev/null; then
        sudo yum install -y tmux
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y tmux
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm tmux
    elif command -v brew &>/dev/null; then
        brew install tmux
    else
        echo "Error: Could not determine package manager to install tmux."
        exit 1
    fi
}

# Install TPM (Tmux Plugin Manager) and plugins
install_tpm() {
    if [[ ! -d "$TPM_DIR" ]]; then
        echo "Installing Tmux Plugin Manager..."
        git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
    fi
}

# Install tmux plugins
install_plugins() {
    if [[ -x "$TPM_DIR/bin/install_plugins" ]]; then
        echo "Installing tmux plugins..."
        "$TPM_DIR/bin/install_plugins"
    fi
}

# Check and install tmux if needed
if ! command -v tmux &>/dev/null; then
    install_tmux
    if ! command -v tmux &>/dev/null; then
        echo "Error: Failed to install tmux."
        exit 1
    fi
fi

# Check if git is installed (needed for TPM)
if ! command -v git &>/dev/null; then
    echo "Error: git is not installed. Please install git first."
    exit 1
fi

# Check if claude is installed
if ! command -v claude &>/dev/null; then
    echo "Error: claude is not installed. Please install Claude Code first."
    exit 1
fi

# Ensure tmux config directory exists
mkdir -p "$TMUX_DIR/plugins"
mkdir -p "$TMUX_DIR/resurrect"

# Install TPM and plugins if needed
install_tpm
install_plugins

# Source updated config for any existing tmux server
if tmux list-sessions &>/dev/null; then
    echo "Updating tmux configuration..."
    tmux source-file "$TMUX_CONF" 2>/dev/null || true
fi

# Find an available session name
SESSION_NAME=$(find_available_session_name)

if [[ -z "$SESSION_NAME" ]]; then
    echo "Error: All phonetic alphabet session names are in use (alpha through zulu)."
    echo "Please close an existing tmux session and try again."
    exit 1
fi

# Create the tmux session with our config and start claude code
echo "Creating tmux session: $SESSION_NAME"
tmux -f "$TMUX_CONF" new-session -d -s "$SESSION_NAME" -c "$SCRIPT_DIR"
tmux send-keys -t "$SESSION_NAME" "claude --dangerously-skip-permissions" Enter

# Attach to the session
echo "Attaching to session: $SESSION_NAME"
tmux -f "$TMUX_CONF" attach-session -t "$SESSION_NAME"
