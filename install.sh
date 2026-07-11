#!/usr/bin/env bash
# Personal dev container setup — runs automatically on container create/attach.
# Installs jcodemunch-mcp and jdocmunch-mcp (Python CLI tools used by Claude Code hooks).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
    echo "[dotfiles] $*"
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

ensure_local_bin() {
    mkdir -p "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"
}

apt_install() {
    local package="$1"
    if has_cmd "$package"; then
        return 0
    fi

    if ! has_cmd apt-get; then
        log "Skipping $package install (apt-get not available)."
        return 0
    fi

    log "Installing $package..."
    if has_cmd sudo; then
        sudo apt-get update -qq && sudo apt-get install -y "$package"
    else
        apt-get update -qq && apt-get install -y "$package"
    fi
}

if ! has_cmd curl; then
    log "curl is required but was not found."
    exit 1
fi

# ── Install bun.sh ─────────────────────────────────────────────────
if ! has_cmd bun; then
    log "Installing bun..."
    curl -fsSL https://bun.sh/install | bash
fi

# ── Install uv if not present ─────────────────────────────────────────────────
if ! has_cmd uv; then
    log "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi
ensure_local_bin

# ── Install jcodemunch-mcp and jdocmunch-mcp ─────────────────────────────────
if has_cmd uv; then
    log "Installing jcodemunch-mcp..."
    uv tool install jcodemunch-mcp --upgrade
    log "Installing jdocmunch-mcp..."
    uv tool install jdocmunch-mcp --upgrade
    log "Done. jcodemunch-mcp and jdocmunch-mcp are installed."
else
    log "Skipping MCP tool installation (uv not available)."
fi

# ── Install tmux if not present ───────────────────────────────────────────────
apt_install tmux

# ── Optional clipboard helpers for tmux select-to-copy on Linux ──────────────
# No-op on non-apt systems (e.g., macOS).
apt_install wl-clipboard
apt_install xclip
apt_install xsel

# ── Install gitmux if not present ───────────────────────────────────────────────
if ! has_cmd gitmux; then
    log "Installing gitmux..."
    ensure_local_bin
    VER="$(curl -fsSL https://api.github.com/repos/arl/gitmux/releases/latest | awk -F '"' '/"tag_name"/ {print $4; exit}')"

    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64|amd64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        *)
            log "Skipping gitmux install (unsupported architecture: $ARCH)."
            ARCH=""
            ;;
    esac

    if [ -n "$ARCH" ] && [ -n "$VER" ]; then
        TMP_DIR="$(mktemp -d)"
        trap 'rm -rf "$TMP_DIR"' EXIT
        curl -fsSL "https://github.com/arl/gitmux/releases/download/${VER}/gitmux_${VER}_linux_${ARCH}.tar.gz" | tar -xz -C "$TMP_DIR"
        install -m 755 "$TMP_DIR/gitmux" "$HOME/.local/bin/gitmux"
    fi
fi

# ── tmux config ───────────────────────────────────────────────────────────────
mkdir -p "$HOME/.tmux/plugins"
if [ ! -d "$HOME/.tmux/plugins/tpm/.git" ]; then
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
fi
cp "$SCRIPT_DIR/.tmux.conf" "$HOME/.tmux.conf" 2>/dev/null || true
cp "$SCRIPT_DIR/.gitmux.conf" "$HOME/.gitmux.conf" 2>/dev/null || true

# ── Git config (shared tracked defaults + local untracked identity) ───────────
if ! git config --global --get-all include.path | grep -Fxq "$SCRIPT_DIR/.gitconfig"; then
    git config --global --add include.path "$SCRIPT_DIR/.gitconfig"
fi

if [ ! -f "$HOME/.gitconfig.local" ]; then
    cat > "$HOME/.gitconfig.local" <<'EOF'
[user]
    name = Your Name
    email = your.email@example.com
EOF
    chmod 600 "$HOME/.gitconfig.local"
    log "Created ~/.gitconfig.local template. Update it with your identity."
fi

log "tmux and shell setup complete."
