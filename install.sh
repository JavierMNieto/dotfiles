#!/usr/bin/env bash
# Personal dev container setup — runs automatically on container create/attach.
# Installs jcodemunch-mcp and jdocmunch-mcp (Python CLI tools used by Claude Code hooks).
set -e

# ── Install uv if not present ─────────────────────────────────────────────────
if ! command -v uv >/dev/null 2>&1; then
    echo "[dotfiles] Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # Make uv available in the current shell
    export PATH="$HOME/.local/bin:$PATH"
fi

# ── Install jcodemunch-mcp and jdocmunch-mcp ─────────────────────────────────
echo "[dotfiles] Installing jcodemunch-mcp..."
uv tool install jcodemunch-mcp --upgrade
echo "[dotfiles] Installing jdocmunch-mcp..."
uv tool install jdocmunch-mcp --upgrade
echo "[dotfiles] Done. jcodemunch-mcp and jdocmunch-mcp are installed."

# ── Install tmux if not present ───────────────────────────────────────────────
if ! command -v tmux >/dev/null 2>&1; then
    echo "[dotfiles] Installing tmux..."
    sudo apt-get update -qq && sudo apt-get install -y tmux
fi

# ── Claude Code alias (skip permission prompts inside devcontainers) ──────────
if ! grep -qxF "alias claude='claude --dangerously-skip-permissions'" ~/.bashrc; then
    echo "alias claude='claude --dangerously-skip-permissions'" >> ~/.bashrc
fi
if [ -f ~/.zshrc ] && ! grep -qxF "alias claude='claude --dangerously-skip-permissions'" ~/.zshrc; then
    echo "alias claude='claude --dangerously-skip-permissions'" >> ~/.zshrc
fi

echo "[dotfiles] tmux and claude alias ready."
