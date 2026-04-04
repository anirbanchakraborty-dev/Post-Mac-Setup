# Post-Mac-Setup

Idempotent, single-file Bash script (`mac-setup.sh`) that bootstraps a full macOS development environment from a clean install.

## What the script does

1. **Preflight** — checks internet, installs Xcode CLT and Homebrew (Apple Silicon + Intel aware)
2. **Taps** — adds third-party Homebrew repos (Verible, bbrew)
3. **Formulae** — installs CLI tools: shells (bash, zsh), languages (Python, Node, Go, Rust, R, GCC), EDA tools (Icarus Verilog, Yosys, Verilator, Verible, Surfer), terminal utilities (bat, eza, fd, fzf, ripgrep, zoxide, jq, htop, tldr, dust, bottom, hyperfine, difftastic), build tools (cmake, llvm, pandoc)
4. **Casks** — installs GUI apps: VS Code, iTerm2, Claude, Microsoft Office, 1Password, Tailscale, Zotero, Inkscape, MacTeX, etc.
5. **npm globals** — netlistsvg
6. **Post-install** — shell setup (/etc/shells, default shell), Git LFS, Git global config, Rust toolchain, fzf bindings, MacTeX PATH, Oh My Zsh + Powerlevel10k + plugins
7. **Shell config** — writes `~/.zsh_paths`, `~/.zsh_aliases`, `~/.zshrc` using marker-based injection (`inject_block`) that preserves user content between runs
8. **macOS defaults** — prevents .DS_Store on network/USB volumes
9. **Cleanup** — `brew cleanup` + exports a `Brewfile` snapshot next to the script

## File structure

```
Post-Mac-Setup/
  mac-setup.sh   — the setup script (single file, self-contained)
  Brewfile        — auto-generated snapshot of installed Homebrew packages
  CLAUDE.md       — this file
```

## CLI flags

| Flag | Effect |
|---|---|
| `--help`, `-h` | Show usage |
| `--dry-run` | Preview actions without making changes |
| `--skip-casks` | Skip GUI app installation |
| `--skip-formulae` | Skip CLI tool installation |
| `--skip-macos` | Skip macOS .DS_Store defaults |
| `--skip-shell` | Skip shell config (.zshrc, .zsh_paths, .zsh_aliases) |
| `--no-log` | Don't write a log file |

## Key conventions

- **Idempotent** — safe to rerun; Homebrew skips installed packages, `inject_block` replaces existing marker-bounded blocks
- **Marker-based config injection** — shell config blocks are wrapped in `### BEGIN <ID>` / `### END <ID>` markers so they can be updated without clobbering user additions
- **Backups** — existing `.zshrc`, `.zsh_paths`, `.zsh_aliases` are backed up with a timestamp before modification
- **Failure tracking** — failed installs are collected in `FAILED_ITEMS` and reported in the summary, but don't halt the script (`set -e` is used, but `install_or_warn` catches errors)
- **Logging** — output is tee'd to a timestamped log file in a temp directory (unless `--no-log`)
- **Brewfile** — exported to the same directory as the script (not home or temp)

## Editing guidelines

- Package lists are plain Bash arrays (`TAPS`, `FORMULAE`, `CASKS`) — add/remove entries there
- Aliases go in the `ZSH_ALIASES` injection blocks; PATH/env vars go in `ZSH_PATHS` blocks
- The `inject_block` / `inject_block_top` helpers are the only mechanism for writing to dotfiles — don't echo/cat directly into shell configs
- The script uses `set -euo pipefail` — any new commands that may legitimately fail should be wrapped in `install_or_warn` or have `|| true` guards
- macOS `defaults write` commands go in the macOS System Defaults section
