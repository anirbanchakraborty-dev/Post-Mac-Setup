# Post-Mac-Setup

A single, idempotent Bash script that bootstraps a complete macOS development environment from a fresh install. Run it once on a new Mac and get everything — Homebrew, CLI tools, GUI apps, shell config, and sensible defaults — ready to go.

## Quick Start

```bash
chmod +x mac-setup.sh && ./mac-setup.sh
```

Rerunning is safe. Homebrew skips already-installed packages, and shell configs are updated in-place using marker-based injection.

## What Gets Installed

### CLI Tools (Formulae)

| Category | Packages |
|---|---|
| Shells | `bash`, `zsh` (updated, replacing macOS system versions) |
| Version Control | `git`, `git-lfs`, `gh` |
| Languages | `python@3`, `node`, `pnpm`, `r`, `gcc`, `go`, `rustup`, `uv` |
| EDA / Hardware | `icarus-verilog`, `yosys`, `verilator`, `verible`, `surfer`, `graphviz` |
| Terminal Utilities | `bat`, `eza`, `fd`, `fzf`, `ripgrep`, `zoxide`, `jq`, `tree`, `htop`, `tldr`, `dust`, `bottom`, `hyperfine`, `difftastic`, `coreutils`, `wget`, `curl` |
| Build Tools | `cmake`, `llvm`, `pandoc` |
| Homebrew TUI | `bbrew` |

### GUI Apps (Casks)

| Category | Apps |
|---|---|
| Editors & IDEs | VS Code, CotEditor |
| Git | GitHub Desktop |
| AI | Claude |
| Productivity | Microsoft Office, Setapp, Google Drive |
| LaTeX | MacTeX, Texifier |
| Research | Zotero, Inkscape |
| Terminal | iTerm2 |
| Networking | Tailscale, 1Password, 1Password CLI |
| Browser & Messaging | Ulaa, WhatsApp |
| Window Management | AltTab, Rectangle Pro |
| Menu Bar | Blip |
| Fonts | MesloLG Nerd Font, JetBrains Mono Nerd Font |

### Shell Environment

- **Oh My Zsh** with Powerlevel10k theme
- **Plugins**: zsh-autosuggestions, zsh-syntax-highlighting, zsh-completions, fzf
- **Aliases**: `eza` as `ls`, `bat` as `cat`, `fd` as `find`, `dust` as `du`, `btm` as `top`, `difft` as `diff`, plus git shortcuts
- **Config files**: `~/.zshrc`, `~/.zsh_paths`, `~/.zsh_aliases` (cleanly separated)

### macOS Defaults

- Prevents `.DS_Store` files on network and USB volumes

## CLI Flags

```
--help, -h        Show usage
--dry-run         Preview what would be installed (no changes made)
--skip-casks      Skip GUI app installation
--skip-formulae   Skip CLI tool installation
--skip-macos      Skip macOS .DS_Store defaults
--skip-shell      Skip shell configuration (.zshrc, etc.)
--no-log          Don't save output to a log file
```

### Examples

```bash
# See what would happen without making changes
./mac-setup.sh --dry-run

# Install only CLI tools (no GUI apps)
./mac-setup.sh --skip-casks

# Minimal run — just packages, no shell or macOS config
./mac-setup.sh --skip-shell --skip-macos
```

## How It Works

1. **Preflight** — verifies internet connectivity, installs Xcode Command Line Tools and Homebrew
2. **Install** — taps third-party repos, installs formulae, casks, and npm globals
3. **Configure** — sets up shells in `/etc/shells`, configures Git, initializes Rust, fzf, and MacTeX
4. **Shell Config** — writes `~/.zsh_paths`, `~/.zsh_aliases`, and `~/.zshrc` using marker-based block injection that preserves your own additions between runs
5. **macOS Defaults** — applies `.DS_Store` prevention
6. **Cleanup** — runs `brew cleanup` and exports a `Brewfile` snapshot

### Marker-Based Injection

Shell config blocks are wrapped in markers like:

```bash
### BEGIN BLOCK-ID (managed by mac-setup.sh — do not edit)
# ... managed content ...
### END BLOCK-ID
```

Anything you add outside these markers is preserved across reruns.

## Post-Install Manual Steps

1. **Restart your terminal** (or `exec zsh`)
2. **Run `p10k configure`** to set up the Powerlevel10k prompt
3. **Set iTerm2 font**: Preferences > Profiles > Text > Font > MesloLGS Nerd Font
4. **Verify Homebrew versions**: `which git`, `which python3`, `which zsh`
5. **Sign in to apps**: 1Password, Setapp, Tailscale, GitHub Desktop, etc.

## File Structure

```
Post-Mac-Setup/
  mac-setup.sh    # The setup script
  Brewfile         # Auto-generated Homebrew package snapshot
  CLAUDE.md        # AI assistant context
  README.md        # This file
```

## License

MIT
