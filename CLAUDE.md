# Post-Mac-Setup

Idempotent, single-file Bash script (`mac-setup.sh`) that bootstraps a full macOS development environment from a clean install.

## What the script does

1. **Preflight** — checks internet, caches `sudo` upfront with a backgrounded keep-alive, installs Xcode CLT (polls until present rather than waiting for a keypress), installs Homebrew (Apple Silicon + Intel aware)
2. **Taps** — adds third-party Homebrew repos (Verible, bbrew); already-tapped repos are detected via `brew tap` and skipped
3. **Formulae** — installs CLI tools in a **single batched `brew install`** call (with per-package fallback on batch failure). Shells (bash, zsh), languages (Python, Node, Go, Rust, R, GCC), EDA tools (Icarus Verilog, Yosys, Verilator, Verible, Surfer), terminal utilities (bat, eza, fd, fzf, ripgrep, zoxide, jq, htop, tldr, dust, bottom, hyperfine, difftastic), build tools (cmake, llvm, pandoc)
4. **Casks** — single batched `brew install --cask` for all GUI apps: VS Code, iTerm2, Claude, Microsoft Office, 1Password, Tailscale, Zotero, Inkscape, MacTeX, Blip, etc.
5. **npm globals** — netlistsvg (skipped if already in `npm list -g`)
6. **Extras (direct downloads)** — vendor `.pkg` installers downloaded straight from the publisher (e.g. **Microsoft Edge** via Microsoft's stable fwlink → `installer -pkg ... -target /`). Use this category when the publisher's installer is preferred over a Homebrew cask. Driven by the `install_pkg_from_url` helper
7. **Post-install** — shell setup (/etc/shells, default shell), Git LFS, Git global config (uses `set_git_default` to avoid clobbering existing user-set values), Rust toolchain, fzf bindings, Oh My Zsh + Powerlevel10k + plugins
8. **Shell config** — writes `~/.zsh_paths`, `~/.zsh_aliases`, `~/.zshrc` using marker-based injection (`inject_block`) that preserves user content between runs
9. **macOS defaults** — prevents .DS_Store on network/USB volumes
10. **Cleanup** — `brew cleanup` + exports a `Brewfile` snapshot next to the script
11. **Summary** — printed via `EXIT` trap (so it appears even on Ctrl-C / mid-script failure); reports newly installed / already present / failures / elapsed time

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
| `--dry-run` | Preview actions without making changes (no dotfile writes, no `brew update`, no `git config`, etc.) |
| `--upgrade` | Also run `brew upgrade` on already-installed packages (off by default to avoid surprise breakage on rerun) |
| `--skip-casks` | Skip GUI app installation |
| `--skip-formulae` | Skip CLI tool installation |
| `--skip-extras` | Skip non-Homebrew direct downloads (Microsoft Edge, etc.) |
| `--skip-macos` | Skip macOS .DS_Store defaults |
| `--skip-shell` | Skip shell config (.zshrc, .zsh_paths, .zsh_aliases) |
| `--no-log` | Don't write a log file |

## Key conventions

- **Idempotent** — safe to rerun. Already-installed packages are detected via `brew list` upfront (cheaper than letting brew skip them) and counted toward `SKIPPED_COUNT`. `inject_block` replaces existing marker-bounded blocks
- **Batched install** — `batch_install` calls `brew install <a> <b> <c> …` once for all new packages (5–10× faster than one call each), with a per-package fallback if the batch fails
- **Marker-based config injection** — shell config blocks are wrapped in `### BEGIN <ID>` / `### END <ID>` markers so they can be updated without clobbering user additions
- **Backups** — existing `.zshrc`, `.zsh_paths`, `.zsh_aliases` are backed up with a timestamp before modification
- **Failure tracking** — failed installs are collected in `FAILED_ITEMS` and reported in the summary, but don't halt the script (`set -e` is used, but `batch_install` and the `run` helper catch errors)
- **Sudo keep-alive** — `sudo -v` runs upfront and a background loop refreshes the timestamp every 60s so long downloads (e.g. MacTeX) don't outlast the cached creds. The keep-alive PID is killed in the `EXIT` trap
- **EXIT trap** — `print_summary` is registered as the `EXIT` handler, so the stats summary prints on every exit path (success, error, Ctrl-C). Manual-steps + "Happy coding" only print when `SCRIPT_COMPLETED=true` (set just before normal end)
- **Logging** — output is tee'd to a timestamped log file in `~/Library/Logs/mac-setup/` (survives reboots; unless `--no-log`)
- **Brewfile** — exported to the same directory as the script (not home or temp)

## Editing guidelines

- Package lists are plain Bash arrays (`TAPS`, `FORMULAE`, `CASKS`) — add/remove entries there
- Aliases go in the `ZSH_ALIASES` injection blocks; PATH/env vars go in `ZSH_PATHS` blocks
- The `inject_block` / `inject_block_top` helpers are the only mechanism for writing to dotfiles — don't echo/cat directly into shell configs
- The script uses `set -euo pipefail`. Helpers:
  - **`run cmd args…`** — executes the command, or just prints `[DRY RUN] Would run: …` under `--dry-run`. Use this for any side-effecting command that should respect dry-run
  - **`batch_install formula|cask pkg1 pkg2 …`** — handles already-installed detection, batched install, fallback, and counter updates
  - **`install_pkg_from_url <app-path> <label> <url>`** — downloads a publisher `.pkg` and runs `sudo installer -pkg ... -target /`. Use for non-Homebrew apps where you want the vendor's own installer. Already-present apps are detected by `app_path` and skipped; honors `--dry-run`
  - When adding new state-changing commands, wrap with `run`, gate with `if $DRY_RUN`, or guard with `|| true` so failures land in `FAILED_ITEMS` rather than killing the script
- macOS `defaults write` commands go in the macOS System Defaults section
- New dotfile-writing logic must live inside the `if $DRY_RUN ... else ... fi` block in the "Updating Shell Config Files" section — otherwise dry-run will mutate the user's home directory
- New non-Homebrew app installs go in the **Extras (Direct Downloads)** section; gate with `$SKIP_EXTRAS` and call `install_pkg_from_url`
