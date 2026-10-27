#!/usr/bin/env bash
# Personal dev container setup — runs automatically on container create/attach.
# Installs tools (Claude Code and Codex among them), the tmux and git configs, and merges claude/settings.json into ~/.claude/settings.json.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
    echo "[dotfiles] $*"
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

is_container_runtime() {
    [ -f "/.dockerenv" ] && return 0
    [ -f "/run/.containerenv" ] && return 0
    [ -n "${REMOTE_CONTAINERS:-}" ] && return 0
    [ -n "${DEVCONTAINER:-}" ] && return 0
    [ -n "${CODESPACES:-}" ] && return 0

    if [ -r "/proc/1/cgroup" ] && grep -Eiq '(docker|containerd|kubepods|podman|lxc)' /proc/1/cgroup; then
        return 0
    fi

    if [ -r "/proc/1/environ" ] && tr '\0' '\n' < /proc/1/environ 2>/dev/null | grep -Eiq '^(container|CONTAINER|DEVCONTAINER|REMOTE_CONTAINERS)='; then
        return 0
    fi

    return 1
}

# Whether a container override should run, from a detection mode
# (auto/on/off); logs why not.
container_override_wanted() {
    local detection_mode="$1"
    local variable="$2"
    local what="$3"

    case "${detection_mode,,}" in
        1|true|yes|on|always)
            return 0
            ;;
        0|false|no|off|never)
            log "Skipping $what ($variable=$detection_mode)."
            return 1
            ;;
        auto|'')
            if is_container_runtime; then
                return 0
            fi
            log "Skipping $what (container not detected)."
            return 1
            ;;
        *)
            log "Unknown $variable value '$detection_mode'; expected auto/on/off."
            return 1
            ;;
    esac
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

clean_old_claude_settings() {
    local settings_file="$1"
    local aside="$2"

    if ! has_cmd python3; then
        log "Skipping the old settings cleanup (python3 not available; not touching $settings_file)."
        return 0
    fi

    local backup="$aside/settings.json"
    if [ -e "$backup" ]; then
        backup="$aside/settings.$(date +%H%M%S).json"
    fi
    cp "$settings_file" "$backup"

    local removed
    if ! removed="$(python3 -I - "$settings_file" <<'PY'
import json
import os
import pathlib
import sys

settings_file = pathlib.Path(sys.argv[1])
try:
    payload = json.loads(settings_file.read_text(encoding="utf-8"))
except Exception as exc:
    sys.exit(f"cannot parse {settings_file}: {exc}")
if not isinstance(payload, dict):
    sys.exit(f"{settings_file} is not a JSON object")

OLD_HOOKS = ("hooks/launcher.js", "jcodemunch-mcp hook-", "jdocmunch-mcp hook-")
removed = []

hooks = payload.get("hooks")
if isinstance(hooks, dict):
    for event in list(hooks):
        groups = hooks[event]
        if not isinstance(groups, list):
            continue
        kept_groups = []
        for group in groups:
            entries = group.get("hooks") if isinstance(group, dict) else None
            if not isinstance(entries, list):
                kept_groups.append(group)
                continue
            kept = []
            for entry in entries:
                command = entry.get("command", "") if isinstance(entry, dict) else ""
                if isinstance(command, str) and any(old in command for old in OLD_HOOKS):
                    removed.append(f"hooks.{event}: {command}")
                else:
                    kept.append(entry)
            if kept:
                group["hooks"] = kept
                kept_groups.append(group)
        if kept_groups:
            hooks[event] = kept_groups
        else:
            del hooks[event]
    if not hooks:
        del payload["hooks"]

env = payload.get("env")
if isinstance(env, dict):
    for key in ("CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS", "CLAUDE_CODE_SPAWN_BACKEND"):
        if key in env:
            del env[key]
            removed.append(f"env.{key}")

for key in ("teammateMode", "enabledMcpjsonServers"):
    if key in payload:
        del payload[key]
        removed.append(key)

tmp = settings_file.with_name(settings_file.name + ".tmp")
tmp.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
os.replace(tmp, settings_file)
print("\n".join(removed))
PY
    )"; then
        log "Skipping the old settings cleanup (could not read $settings_file)."
        return 0
    fi

    if [ -n "$removed" ]; then
        log "Copied $settings_file to $backup and removed what the old .claude repository set:"
        local line
        while IFS= read -r line; do
            log "  $line"
        done <<< "$removed"
    else
        log "Copied $settings_file to $backup; nothing from the old .claude repository was left in it."
    fi
}

tidy_claude_sync() {
    local dest="$HOME/.claude"
    local readme="$dest/README.md"
    local settings_file="$dest/settings.json"
    local stamp
    stamp="$(date +%Y-%m-%d)"
    local aside="$dest/synced-removed-$stamp"
    local moved=1

    if [ -f "$readme" ] && grep -Fxq '# Claude Code Agent Configuration' "$readme"; then
        mkdir -p "$aside"
        local item
        for item in agents hooks scripts skills/create-hook skills/install-hook style \
            .claude .devcontainer README.md .gitignore CLAUDE.md output-styles; do
            if [ -e "$dest/$item" ] || [ -L "$dest/$item" ]; then
                mkdir -p "$aside/$(dirname "$item")"
                mv "$dest/$item" "$aside/$item"
            fi
        done
        moved=0
        log "Moved the old synced files to ~/.claude/synced-removed-$stamp; delete it when you are sure."
    fi

    # The settings the old repository merged in stay after its files move;
    # a machine already past the move is caught by its launcher.js hook.
    if [ -f "$settings_file" ] && { [ "$moved" -eq 0 ] || grep -Fq 'hooks/launcher.js' "$settings_file"; }; then
        mkdir -p "$aside"
        clean_old_claude_settings "$settings_file" "$aside"
    fi
}

merge_claude_settings() {
    local source_file="$SCRIPT_DIR/claude/settings.json"
    local settings_file="$HOME/.claude/settings.json"

    if [ ! -f "$source_file" ]; then
        log "Skipping Claude settings merge ($source_file not found)."
        return 0
    fi

    mkdir -p "$(dirname "$settings_file")"

    if has_cmd python3; then
        if ! python3 -I - "$settings_file" "$source_file" <<'PY'
import json
import os
import pathlib
import sys

settings_file = pathlib.Path(sys.argv[1])
source_file = pathlib.Path(sys.argv[2])

try:
    tracked = json.loads(source_file.read_text(encoding="utf-8"))
except Exception as exc:
    sys.exit(f"cannot parse {source_file}: {exc}")
if not isinstance(tracked, dict):
    sys.exit(f"{source_file} is not a JSON object")

payload = {}
if settings_file.exists():
    try:
        payload = json.loads(settings_file.read_text(encoding="utf-8"))
    except Exception as exc:
        sys.exit(f"cannot parse {settings_file}: {exc}")
    if not isinstance(payload, dict):
        sys.exit(f"{settings_file} is not a JSON object")

# An object is merged one level down; a scalar or a list is set; every
# other key in the user settings is kept.
for key, value in tracked.items():
    current = payload.get(key)
    if isinstance(value, dict) and isinstance(current, dict):
        current.update(value)
    else:
        payload[key] = value

tmp = settings_file.with_name(settings_file.name + ".tmp")
tmp.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
os.replace(tmp, settings_file)
PY
        then
            log "Skipping Claude settings merge (could not merge into $settings_file)."
            return 0
        fi
    elif has_cmd jq; then
        local tmp_file="${settings_file}.tmp"
        local existing='{}'
        if [ -f "$settings_file" ]; then
            existing="$(cat "$settings_file")"
        fi
        if ! printf '%s' "$existing" | jq --slurpfile tracked "$source_file" '
            if type != "object" then error("not a JSON object") else . end
            | $tracked[0] as $new
            | if ($new | type) != "object" then error("tracked settings are not a JSON object") else . end
            | reduce ($new | keys_unsorted[]) as $k (.;
                if (.[$k] | type) == "object" and ($new[$k] | type) == "object"
                then .[$k] += $new[$k]
                else .[$k] = $new[$k]
                end)
        ' > "$tmp_file"; then
            rm -f "$tmp_file"
            log "Skipping Claude settings merge (could not merge into $settings_file)."
            return 0
        fi
        mv "$tmp_file" "$settings_file"
    else
        log "Skipping Claude settings merge (python3 and jq not available; not touching $settings_file)."
        return 0
    fi

    log "Claude settings from claude/settings.json merged into $settings_file."
}

apply_claude_permission_mode() {
    local detection_mode="${CLAUDE_CONTAINER_DETECTION:-auto}"
    local default_mode="${CLAUDE_CONTAINER_PERMISSION_MODE:-bypassPermissions}"
    local settings_file="$HOME/.claude/settings.json"

    if ! container_override_wanted "$detection_mode" CLAUDE_CONTAINER_DETECTION "Claude permissions override"; then
        return 0
    fi

    if [ -z "$default_mode" ]; then
        log "Skipping Claude permissions override (CLAUDE_CONTAINER_PERMISSION_MODE is empty)."
        return 0
    fi

    mkdir -p "$(dirname "$settings_file")"

    local skip_prompt=0
    if [ "$default_mode" = "bypassPermissions" ]; then
        skip_prompt=1
    fi

    if has_cmd python3; then
        if ! python3 - "$settings_file" "$default_mode" "$skip_prompt" <<'PY'
import json
import os
import pathlib
import sys

settings_file = pathlib.Path(sys.argv[1])
default_mode = sys.argv[2]
skip_prompt = sys.argv[3] == "1"
payload = {}

if settings_file.exists():
    try:
        payload = json.loads(settings_file.read_text(encoding="utf-8"))
    except Exception as exc:
        sys.exit(f"cannot parse {settings_file}: {exc}")
    if not isinstance(payload, dict):
        sys.exit(f"{settings_file} is not a JSON object")

permissions = payload.get("permissions")
if not isinstance(permissions, dict):
    permissions = {}

permissions.pop("bypassAllToolUsePermissions", None)
permissions["defaultMode"] = default_mode
payload["permissions"] = permissions
if skip_prompt:
    payload["skipDangerousModePermissionPrompt"] = True

tmp = settings_file.with_name(settings_file.name + ".tmp")
tmp.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
os.replace(tmp, settings_file)
PY
        then
            log "Skipping Claude permissions override (could not merge into $settings_file)."
            return 0
        fi
    elif has_cmd jq; then
        local tmp_file="${settings_file}.tmp"
        local existing='{}'
        if [ -f "$settings_file" ]; then
            existing="$(cat "$settings_file")"
        fi
        if ! printf '%s' "$existing" | jq \
            --arg mode "$default_mode" \
            --argjson skip "$([ "$skip_prompt" -eq 1 ] && echo true || echo false)" '
            if type != "object" then error("not a JSON object") else . end
            | .permissions = ((if (.permissions | type) == "object" then .permissions else {} end)
                | del(.bypassAllToolUsePermissions)
                | .defaultMode = $mode)
            | if $skip then .skipDangerousModePermissionPrompt = true else . end
        ' > "$tmp_file"; then
            rm -f "$tmp_file"
            log "Skipping Claude permissions override (could not merge into $settings_file)."
            return 0
        fi
        mv "$tmp_file" "$settings_file"
    else
        log "Skipping Claude permissions override (python3 and jq not available; not touching $settings_file)."
        return 0
    fi

    if [ "$skip_prompt" -eq 1 ]; then
        log "Claude permissions set in $settings_file (defaultMode='${default_mode}', skipDangerousModePermissionPrompt=true)."
    else
        log "Claude permissions set in $settings_file (defaultMode='${default_mode}')."
    fi
}

apply_codex_permission_mode() {
    local detection_mode="${CODEX_CONTAINER_DETECTION:-${CLAUDE_CONTAINER_DETECTION:-auto}}"
    local approval_policy="${CODEX_CONTAINER_APPROVAL_POLICY-never}"
    local sandbox_mode="${CODEX_CONTAINER_SANDBOX_MODE-danger-full-access}"
    local config_file="${CODEX_HOME:-$HOME/.codex}/config.toml"

    if ! container_override_wanted "$detection_mode" CODEX_CONTAINER_DETECTION "Codex permissions override"; then
        return 0
    fi

    if [ -z "$approval_policy" ] && [ -z "$sandbox_mode" ]; then
        log "Skipping Codex permissions override (CODEX_CONTAINER_APPROVAL_POLICY and CODEX_CONTAINER_SANDBOX_MODE are empty)."
        return 0
    fi

    if ! has_cmd python3; then
        log "Skipping Codex permissions override (python3 not available; not touching $config_file)."
        return 0
    fi

    mkdir -p "$(dirname "$config_file")"

    if ! python3 -I - "$config_file" "$approval_policy" "$sandbox_mode" <<'PY'
import json
import os
import pathlib
import re
import sys

config_file = pathlib.Path(sys.argv[1])
wanted = {"approval_policy": sys.argv[2], "sandbox_mode": sys.argv[3]}
wanted = {key: value for key, value in wanted.items() if value}

text = config_file.read_text(encoding="utf-8") if config_file.exists() else ""
lines = text.splitlines()

try:
    import tomllib
except ImportError:
    tomllib = None
if tomllib is not None and text:
    try:
        tomllib.loads(text)
    except Exception as exc:
        sys.exit(f"cannot parse {config_file}: {exc}")

# Top-level keys sit before the first table header; set them there and
# leave every other line as it is.
first_table = next(
    (i for i, line in enumerate(lines) if re.match(r"\s*\[", line)), len(lines)
)
done = set()
for i in range(first_table):
    match = re.match(r"\s*([A-Za-z0-9_-]+)\s*=", lines[i])
    if match and match.group(1) in wanted:
        key = match.group(1)
        lines[i] = f"{key} = {json.dumps(wanted[key])}"
        done.add(key)
missing = [f"{key} = {json.dumps(value)}" for key, value in wanted.items() if key not in done]
lines[0:0] = missing

result = "\n".join(lines) + "\n"
if tomllib is not None:
    parsed = tomllib.loads(result)
    assert all(parsed.get(key) == value for key, value in wanted.items())

tmp = config_file.with_name(config_file.name + ".tmp")
tmp.write_text(result, encoding="utf-8")
os.replace(tmp, config_file)
PY
    then
        log "Skipping Codex permissions override (could not merge into $config_file)."
        return 0
    fi

    log "Codex permissions set in $config_file (approval_policy='${approval_policy}', sandbox_mode='${sandbox_mode}')."
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

# ── Install Claude Code and Codex if not present ─────────────────────────────
if ! has_cmd claude; then
    log "Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash || log "Claude Code install failed; continuing."
fi
if ! has_cmd codex; then
    log "Installing Codex..."
    curl -fsSL https://chatgpt.com/codex/install.sh | sh || log "Codex install failed; continuing."
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

git_user_name="$(git config --global --get user.name || true)"
git_user_email="$(git config --global --get user.email || true)"

if [ -n "$git_user_name" ] && [ -n "$git_user_email" ]; then
    log "Git identity already configured."
else
    log "Git identity missing. Enable Dev Containers copyGitConfig or set ~/.gitconfig.local manually."
fi

# ── Claude settings ────────────────────────────────────────────────────────────
tidy_claude_sync
merge_claude_settings
apply_claude_permission_mode
apply_codex_permission_mode

log "tmux and shell setup complete."
