---
name: Dotfiles
branch: main
form: compact
---

# The dotfiles' part of the workflow

One repository, one script: `install.sh` runs on every container's
creation. Nothing here is private: the repository is public.
`claude/settings.json` is the only Claude configuration tracked; what a
project needs is that project's `.claude/settings.json`.

## While working

A change is made in a chat with the maker, tested by running
`bash -n install.sh` and the changed function against a copy of
`~/.claude/settings.json` in /tmp, and committed on `main`.
