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

## Usage

Configured via VS Code User Settings:
- `dev.containers.dotfilesRepository`: this repo
- `dev.containers.dotfilesInstallCommand`: `install.sh`

VS Code clones this repo into every dev container and runs `install.sh` automatically.
