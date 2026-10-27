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
- `claude/settings.json` merged into the user-scope `~/.claude/settings.json`

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
- `install.sh` does **not** write/reset your identity values.
- If identity is missing, configure it via host Git config copy (`copyGitConfig`) or create `~/.gitconfig.local` manually.

For local Dev Containers, prefer enabling Git config copy so identity is automatic:

```json
"dev.containers.copyGitConfig": true
```

Limitation: host Git config copy applies to local Dev Containers; remote environments like Codespaces cannot read your host `~/.gitconfig`.

## Claude settings

`claude/settings.json` is the only Claude configuration this repository tracks. `install.sh` merges it into `~/.claude/settings.json` key by key: an object key (`env`, `permissions`, `extraKnownMarketplaces`, `enabledPlugins`, `modelSettings`, `pluginConfigs`, `worktree`) is merged one level down, a scalar or a list is set, and every other key already in the file is kept. The file is written through a temp file, never replaced wholesale; `python3` is used, falling back to `jq`. The rest of `~/.claude` is Claude Code's own (credentials, history, projects, plugins) and is not touched.

What the tracked file holds, and why:

- `model`, `effortLevel`, `modelSettings`: the default model and the effort per model.
- `env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`: compact at 75 percent of the context.
- `env.CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`: the workflow's agents spawn subagents one level deep.
- `permissions.allow`: the read-only commands every project uses (Claude Code's docs, `git log`, `gh api`, GitHub pages).
- `extraKnownMarketplaces`, `enabledPlugins`: the `workflow` marketplace at `main`, auto-updated, and the Codex plugin; `workflow@workflow` and `codex@openai-codex` are on everywhere. `code-simplifier`, `context7`, `claude-md-management` and `claude-mem`, which the old `.claude` repository turned on, are set to `false`, not left out: the merge keeps keys it does not name, so on a `~/.claude` that survives a rebuild an old `true` would stay; a project that wants one turns it on in its own `.claude/settings.json`.
- `pluginConfigs`: the workflow plugin's `owner`.
- `statusLine`: the workflow plugin's status line.
- `worktree`: background sessions without isolation; new worktrees from the remote's default branch.
- `tui`, `theme`, `agentPushNotifEnabled`: the interface.

Left out on purpose:

- The jcodemunch and jdocmunch hooks and `enabledMcpjsonServers`: a project that wants them names them under **Reading** in its `.claude/workflow.md` and puts the hooks in its own `.claude/settings.json`. This script still installs both tools.
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`, `CLAUDE_CODE_SPAWN_BACKEND`, `teammateMode`: the workflow's agents never use teams.
- `CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX`: the workflow names sessions per project.
- Permissions for retired connectors and plugins not kept.
- A project's own plugins and marketplaces, and machine-specific keys such as `remote.defaultEnvironmentId`.
- `writing@workflow`: the research-writing skills are turned on per project, with `"enabledPlugins": { "writing@workflow": true }` in that project's `.claude/settings.json`.

The agents come from the workflow plugin, not from files in `~/.claude`.

### The one-time tidy

Containers set up before this change had `https://github.com/JavierMNieto/.claude` synced over `~/.claude`. When `~/.claude/README.md` is that sync's, `install.sh` moves `agents`, `hooks`, `scripts`, `skills/create-hook`, `skills/install-hook`, `style`, `.claude`, `.devcontainer`, `README.md`, `.gitignore`, `CLAUDE.md` and `output-styles` (each only if present) into `~/.claude/synced-removed-<date>/` and logs where. Nothing is deleted; remove that directory when you are sure. Later runs find no such README and do nothing.

### Container permission mode

- `CLAUDE_CONTAINER_DETECTION` — container detection mode for permission override (`auto` by default; accepts `on`/`off`)
- `CLAUDE_CONTAINER_PERMISSION_MODE` — Claude `permissions.defaultMode` to apply in containers (`bypassPermissions` by default; set empty to disable override)

Notes:
- When container detection matches, `install.sh` merges `permissions.defaultMode` into the user-scope `~/.claude/settings.json` (Claude Code ignores `bypassPermissions` from project/local scope). When the mode is `bypassPermissions`, it also sets top-level `skipDangerousModePermissionPrompt: true`. A stale `permissions.bypassAllToolUsePermissions` key is removed.
- The override runs after the settings merge, so the tracked settings can't overwrite it. Existing keys are preserved; the file is never replaced wholesale.
- The merge uses `python3`, falling back to `jq`. If neither is available, or the existing file isn't a valid JSON object, the override is logged and skipped.
- Container detection checks: `/.dockerenv`, `/run/.containerenv`, `REMOTE_CONTAINERS`, `DEVCONTAINER`, `CODESPACES`, and `/proc/1/{cgroup,environ}` runtime markers.

## Usage

Configured via VS Code User Settings:
- `dev.containers.dotfilesRepository`: this repo
- `dev.containers.dotfilesInstallCommand`: `install.sh`

VS Code clones this repo into every dev container and runs `install.sh` automatically.
