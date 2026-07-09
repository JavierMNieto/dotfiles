#!/usr/bin/env bash
# Personal dev container setup — runs automatically on container create/attach.
# Installs jcodemunch-mcp and jdocmunch-mcp (Python CLI tools used by Claude Code hooks).
set -e

# ── Install bun.sh ─────────────────────────────────────────────────
curl -fsSL https://bun.sh/install | bash

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
    sudo apt-get update -qq && sudo apt-get install -y tmux gitmux
fi

# ── tmux config ───────────────────────────────────────────────────────────────
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
cp ~/dotfiles/.tmux.conf ~/.tmux.conf 2>/dev/null || true

# ── Claude Code alias (skip permission prompts inside devcontainers) ──────────
if ! grep -qxF "alias claude='claude --dangerously-skip-permissions'" ~/.bashrc; then
    echo "alias claude='claude --dangerously-skip-permissions'" >> ~/.bashrc
fi
if [ -f ~/.zshrc ] && ! grep -qxF "alias claude='claude --dangerously-skip-permissions'" ~/.zshrc; then
    echo "alias claude='claude --dangerously-skip-permissions'" >> ~/.zshrc
fi

echo "[dotfiles] tmux and claude alias ready."

git config core.fsmonitor true
git config core.untrackedCache true
git config --global user.name "Javier Nieto"
git config --global user.email "javiermnieto89@gmail.com"

echo "git config set."
