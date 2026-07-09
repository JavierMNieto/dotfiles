# dotfiles

Personal dev container setup script.

## What gets installed/configured

- `bun` (if missing)
- `uv` (if missing)
- `jcodemunch-mcp` and `jdocmunch-mcp` (via `uv tool install --upgrade`)
- `tmux` (via `apt-get`, if available)
- `gitmux` (latest release, Linux `amd64`/`arm64`)
- `~/.tmux.conf` and `~/.gitmux.conf` copied from this repository
- TPM plugin manager (`~/.tmux/plugins/tpm`) if missing

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
