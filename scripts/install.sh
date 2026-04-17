#!/bin/bash
# Argus Agent Wrapper Installer

set -e

WRAPPER_SRC="$(cd "$(dirname "$0")" && pwd)/openvibe-wrapper.py"
WRAPPER_DST="/usr/local/bin/openvibe-wrapper"
SHELL_CONFIG=""

# Detect shell
if [[ "$SHELL" == */zsh ]]; then
    SHELL_CONFIG="$HOME/.zshrc"
elif [[ "$SHELL" == */bash ]]; then
    SHELL_CONFIG="$HOME/.bashrc"
fi

echo "=== Argus Wrapper Installer ==="

# Copy wrapper
if [[ ! -f "$WRAPPER_SRC" ]]; then
    echo "Error: openvibe-wrapper.py not found at $WRAPPER_SRC"
    exit 1
fi

cp "$WRAPPER_SRC" "$WRAPPER_DST"
chmod +x "$WRAPPER_DST"
echo "Installed wrapper to $WRAPPER_DST"

# Add aliases
if [[ -n "$SHELL_CONFIG" ]]; then
    echo ""
    echo "Adding aliases to $SHELL_CONFIG..."

    add_alias() {
        local name="$1"
        if ! grep -q "alias $name='openvibe-wrapper $name'" "$SHELL_CONFIG" 2>/dev/null; then
            echo "alias $name='openvibe-wrapper $name'" >> "$SHELL_CONFIG"
            echo "  + alias $name"
        else
            echo "  ~ alias $name (already exists)"
        fi
    }

    add_alias claude
    add_alias codex
    add_alias opencode
    add_alias gemini

    echo ""
    echo "Done. Run 'source $SHELL_CONFIG' to activate aliases."
else
    echo ""
    echo "Could not detect shell config. Add these aliases manually:"
    echo "  alias claude='openvibe-wrapper claude'"
    echo "  alias codex='openvibe-wrapper codex'"
    echo "  alias opencode='openvibe-wrapper opencode'"
fi

echo ""
echo "Install complete. Start the Argus macOS app, then run 'claude' in your terminal."
