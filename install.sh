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

sync_claude_settings() {
    local enabled="${CLAUDE_SYNC_ENABLED:-1}"
    if [ "$enabled" != "1" ]; then
        log "Skipping Claude settings sync (CLAUDE_SYNC_ENABLED=$enabled)."
        return 0
    fi

    local repo="${CLAUDE_SYNC_REPO:-https://github.com/JavierMNieto/.claude.git}"
    local ref="${CLAUDE_SYNC_REF:-}"
    local dest="${CLAUDE_SYNC_DEST:-$HOME/.claude}"
    local cache_dir="${CLAUDE_SYNC_CACHE_DIR:-$HOME/.cache/dotfiles/claude-settings}"
    local delete_mode="${CLAUDE_SYNC_DELETE:-0}"
    local extra_excludes="${CLAUDE_SYNC_EXCLUDES:-}"

    mkdir -p "$(dirname "$cache_dir")" "$dest"

    if [ -d "$cache_dir/.git" ]; then
        git -C "$cache_dir" remote set-url origin "$repo" >/dev/null 2>&1 || true
        git -C "$cache_dir" fetch --prune origin >/dev/null
    else
        log "Cloning Claude settings from $repo..."
        git clone --depth 1 "$repo" "$cache_dir" >/dev/null
    fi

    if [ -n "$ref" ]; then
        git -C "$cache_dir" fetch --depth 1 origin "$ref" >/dev/null
        git -C "$cache_dir" checkout -f --detach FETCH_HEAD >/dev/null
    else
        git -C "$cache_dir" checkout -f --detach refs/remotes/origin/HEAD >/dev/null 2>&1 || \
            git -C "$cache_dir" checkout -f --detach "$(git -C "$cache_dir" rev-parse HEAD)" >/dev/null
    fi

    if has_cmd rsync; then
        local -a sync_args=("-a" "--exclude=.git/")
        if [ "$delete_mode" = "1" ]; then
            sync_args+=("--delete")
        fi

        local old_ifs="$IFS"
        IFS=','
        read -r -a excludes <<< "$extra_excludes"
        IFS="$old_ifs"
        for pattern in "${excludes[@]}"; do
            if [ -n "$pattern" ]; then
                sync_args+=("--exclude=$pattern")
            fi
        done

        rsync "${sync_args[@]}" "$cache_dir"/ "$dest"/
    else
        log "rsync not available; using cp fallback."
        if [ "$delete_mode" = "1" ] || [ -n "$extra_excludes" ]; then
            log "Fallback mode ignores CLAUDE_SYNC_DELETE and CLAUDE_SYNC_EXCLUDES."
        fi
        find "$cache_dir" -mindepth 1 -maxdepth 1 ! -name ".git" -exec cp -R {} "$dest"/ \;
    fi

    log "Claude settings synced to $dest."
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
apt_install rsync

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

# ── Claude settings sync ───────────────────────────────────────────────────────
sync_claude_settings

log "tmux and shell setup complete."
