# dotfiles

Personal dev container setup script.

## What gets installed/configured

- `bun` (if missing)
- `uv` (if missing)
- `jcodemunch-mcp` and `jdocmunch-mcp` (via `uv tool install --upgrade`)
- `tmux` (via `apt-get`, if available)
- Linux clipboard helpers for tmux (`wl-clipboard`, `xclip`, `xsel` via `apt-get`, if available)
- `gitmux` (latest release, Linux `amd64`/`arm64`)
- `~/.tmux.conf` and `~/.gitmux.conf` copied from this repository
- TPM plugin manager (`~/.tmux/plugins/tpm`) if missing
- Claude settings synced from `https://github.com/JavierMNieto/.claude` into `~/.claude`

## tmux clipboard behavior

- `set-clipboard on` is enabled so terminals with OSC52 support can sync tmux copy operations to the system clipboard.
- For mouse drag copy in tmux copy-mode, the config also uses the first available external tool in this order:
  1. `pbcopy` (macOS)
  2. `wl-copy` (Wayland)
  3. `xclip` (X11)
  4. `xsel` (X11)
- If none are present, copy still works to the tmux internal buffer.

## Git config layout

This repo now ships a tracked `/home/runner/work/dotfiles/dotfiles/.gitconfig` with safe shared defaults.

Identity/secrets stay in untracked `~/.gitconfig.local`:

- `install.sh` adds the repo `.gitconfig` as a global include.
- If `~/.gitconfig.local` does not exist, a template is created.
- Update `~/.gitconfig.local` with your own `[user]` values.

## Claude sync

`install.sh` syncs your Claude repo into local container settings so shared config and agents stay updated.

- Source repo: `CLAUDE_SYNC_REPO` (default: `https://github.com/JavierMNieto/.claude.git`)
- Target path: `CLAUDE_SYNC_DEST` (default: `~/.claude`)
- Optional ref/branch/tag: `CLAUDE_SYNC_REF` (default: remote default branch)
- Enable/disable sync: `CLAUDE_SYNC_ENABLED` (`1` by default, set to `0` to disable)
- Optional delete mode: `CLAUDE_SYNC_DELETE` (`0` by default, set to `1` for `rsync --delete`)
- Optional preserved paths/patterns: `CLAUDE_SYNC_EXCLUDES` (comma-separated rsync exclude patterns)
- Optional cache location: `CLAUDE_SYNC_CACHE_DIR` (default: `~/.cache/dotfiles/claude-settings`)

Notes:
- `.git/` from the settings repo is never copied.
- On systems without `rsync`, a `cp` fallback is used (no delete/exclude pattern support in fallback mode).

## Usage

Configured via VS Code User Settings:
- `dev.containers.dotfilesRepository`: this repo
- `dev.containers.dotfilesInstallCommand`: `install.sh`

VS Code clones this repo into every dev container and runs `install.sh` automatically.
