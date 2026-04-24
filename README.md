# dotfiles

Personal dev container setup script. Installs private tooling that is not part of shared project devcontainers:

- **jcodemunch-mcp** — code navigation MCP server for Claude Code
- **jdocmunch-mcp** — documentation MCP server for Claude Code

## Usage

Configured via VS Code User Settings:
- `dev.containers.dotfilesRepository`: this repo
- `dev.containers.dotfilesInstallCommand`: `install.sh`

VS Code clones this repo into every dev container and runs `install.sh` automatically.
