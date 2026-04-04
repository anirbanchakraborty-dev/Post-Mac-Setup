#!/usr/bin/env bash
#
# ╔══════════════════════════════════════════════════════════════════════╗
# ║                     MAC SETUP SCRIPT v2.0                            ║
# ║              One-shot Mac development environment setup              ║
# ║                                                                      ║
# ║  Run:  chmod +x mac-setup.sh && ./mac-setup.sh                       ║
# ║  Rerun is safe — Homebrew skips already-installed packages.          ║
# ║                                                                      ║
# ║  Flags:  --help          Show usage                                  ║
# ║          --dry-run       Show what would be installed (no changes)   ║
# ║          --skip-casks    Skip GUI app (cask) installation            ║
# ║          --skip-formulae Skip CLI tool (formula) installation        ║
# ║          --skip-macos    Skip macOS .DS_Store defaults                ║
# ║          --skip-shell    Skip shell config (.zshrc, etc.)            ║
# ║          --no-log        Don't save output to a log file             ║
# ╚══════════════════════════════════════════════════════════════════════╝
#
# NOTE: This script will ask for your password at certain points
#       (adding shells to /etc/shells, changing default shell, mactex, etc.)
#
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────
# ARGUMENT PARSING
# ─────────────────────────────────────────────────────────────────────
DRY_RUN=false
SKIP_CASKS=false
SKIP_FORMULAE=false
SKIP_MACOS=false
SKIP_SHELL=false
NO_LOG=false

usage() {
    sed -n '3,17p' "$0" | sed 's/^# //; s/^#//'
    exit 0
}

for arg in "$@"; do
    case "$arg" in
        --help|-h)       usage ;;
        --dry-run)       DRY_RUN=true ;;
        --skip-casks)    SKIP_CASKS=true ;;
        --skip-formulae) SKIP_FORMULAE=true ;;
        --skip-macos)    SKIP_MACOS=true ;;
        --skip-shell)    SKIP_SHELL=true ;;
        --no-log)        NO_LOG=true ;;
        *)
            echo "Unknown option: $arg (try --help)"
            exit 1
            ;;
    esac
done

clear

# ─────────────────────────────────────────────────────────────────────
# COLORS & HELPERS
# ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[  OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[FAIL]${NC} $1"; }
section() {
    # Print section header and record timing for the previous section
    if [ -n "${SECTION_START:-}" ] && [ -n "${SECTION_NAME:-}" ]; then
        local elapsed=$(( SECONDS - SECTION_START ))
        info "⏱  ${SECTION_NAME} took ${elapsed}s"
    fi
    SECTION_NAME="$1"
    SECTION_START=$SECONDS
    echo -e "\n${CYAN}${BOLD}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}  $1${NC}"
    echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════════════${NC}\n"
}

# Track failures and successes for summary
FAILED_ITEMS=()
INSTALLED_COUNT=0
SKIPPED_COUNT=0
TOTAL_START=$SECONDS

install_or_warn() {
    local cmd="$1"
    local name="$2"
    if $DRY_RUN; then
        info "[DRY RUN] Would install: $name"
        return
    fi
    if ! eval "$cmd"; then
        warn "Failed to install: $name (continuing...)"
        FAILED_ITEMS+=("$name")
    else
        success "$name"
        (( INSTALLED_COUNT++ )) || true
    fi
}

# ─────────────────────────────────────────────────────────────────────
# LOGGING — tee all output to a timestamped log file
# ─────────────────────────────────────────────────────────────────────
LOG_DIR="$(mktemp -d)/mac-setup"
LOG_FILE="$LOG_DIR/mac-setup-$(date +%Y%m%d_%H%M%S).log"

if ! $NO_LOG; then
    mkdir -p "$LOG_DIR"
    # Redirect stdout and stderr through tee so everything is logged
    exec > >(tee -a "$LOG_FILE") 2>&1
    info "Logging to $LOG_FILE"
fi

# ─────────────────────────────────────────────────────────────────────
# PREFLIGHT CHECKS
# ─────────────────────────────────────────────────────────────────────
section "Preflight Checks"

# Network connectivity check
info "Checking internet connectivity..."
if ! curl -s --head --max-time 5 https://github.com >/dev/null 2>&1; then
    error "No internet connection. This script requires network access."
    exit 1
fi
success "Internet connection OK"

# Show what will be done based on flags
if $DRY_RUN; then
    warn "DRY RUN MODE — no changes will be made"
fi
echo ""
echo -e "  ${BOLD}Configuration:${NC}"
echo -e "    Formulae (CLI):    $( $SKIP_FORMULAE && echo "${YELLOW}SKIP${NC}" || echo "${GREEN}install${NC}" )"
echo -e "    Casks (GUI):       $( $SKIP_CASKS    && echo "${YELLOW}SKIP${NC}" || echo "${GREEN}install${NC}" )"
echo -e "    macOS defaults:    $( $SKIP_MACOS    && echo "${YELLOW}SKIP${NC}" || echo "${GREEN}apply${NC}" )"
echo -e "    Shell config:      $( $SKIP_SHELL    && echo "${YELLOW}SKIP${NC}" || echo "${GREEN}configure${NC}" )"
echo ""

if ! $DRY_RUN; then
    read -r -p "  Press Enter to continue (or Ctrl-C to abort)... "
fi

# Ensure Xcode CLT is installed (required by Homebrew and many formulae)
if ! xcode-select -p &>/dev/null; then
    info "Installing Xcode Command Line Tools..."
    xcode-select --install
    echo "  Press any key after CLT installation finishes..."
    read -r -n 1
fi
success "Xcode CLT installed"

# Install Homebrew if not present
if ! command -v brew &>/dev/null; then
    if $DRY_RUN; then
        info "[DRY RUN] Would install Homebrew"
        warn "Cannot continue dry run without Homebrew. Exiting."
        exit 0
    fi
    info "Homebrew not found. Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Post-install: add Homebrew to PATH for this session and shell profile
    # Apple Silicon uses /opt/homebrew, Intel uses /usr/local
    if [[ -f /opt/homebrew/bin/brew ]]; then
        BREW_PATH="/opt/homebrew/bin/brew"
    elif [[ -f /usr/local/bin/brew ]]; then
        BREW_PATH="/usr/local/bin/brew"
    else
        error "Homebrew installed but binary not found in expected locations."
        exit 1
    fi

    # Activate Homebrew in the current session
    eval "$("$BREW_PATH" shellenv)"

    # Persist to shell profiles so it works in new terminals
    # (the inject_block in .zshrc handles zsh; here we also cover .zprofile
    #  which is the standard place Homebrew recommends)
    ZPROFILE="$HOME/.zprofile"
    BREW_SHELLENV_LINE="eval \"\$(${BREW_PATH} shellenv)\""
    if [ ! -f "$ZPROFILE" ] || ! grep -qF "$BREW_SHELLENV_LINE" "$ZPROFILE"; then
        echo "" >> "$ZPROFILE"
        echo "# Homebrew (added by mac-setup.sh)" >> "$ZPROFILE"
        echo "$BREW_SHELLENV_LINE" >> "$ZPROFILE"
        success "Added Homebrew shellenv to $ZPROFILE"
    fi

    success "Homebrew installed and configured"
else
    success "Homebrew found: $(brew --version | head -1)"
fi

# Determine Homebrew prefix (Apple Silicon vs Intel)
BREW_PREFIX="$(brew --prefix)"
info "Homebrew prefix: $BREW_PREFIX"

# ─────────────────────────────────────────────────────────────────────
# UPDATE HOMEBREW
# ─────────────────────────────────────────────────────────────────────
section "Updating Homebrew"
brew update
brew upgrade
success "Homebrew updated"

# ─────────────────────────────────────────────────────────────────────
# TAPS (third-party repositories)
# ─────────────────────────────────────────────────────────────────────
section "Adding Taps"

TAPS=(
    "chipsalliance/verible"       # Verible (SystemVerilog tools)
    "Valkyrie00/homebrew-bbrew"   # Bold Brew (bbrew) TUI for Homebrew
)

for tap in "${TAPS[@]}"; do
    info "Tapping $tap..."
    install_or_warn "brew tap $tap" "tap: $tap"
done

# ─────────────────────────────────────────────────────────────────────
# FORMULAE (CLI tools — brew install)
# ─────────────────────────────────────────────────────────────────────
section "Installing Formulae (CLI Tools)"

FORMULAE=(
    # Shells
    bash                # Updated bash (replaces macOS system bash 3.x)
    zsh                 # Updated zsh (replaces macOS system zsh)

    # Version control
    git                 # Updated git (replaces macOS system git)
    git-lfs             # Git Large File Storage
    gh                  # GitHub CLI (pr, issue, repo, etc.)

    # Languages & runtimes
    python@3            # Latest Python 3 (replaces macOS system python)
    node                # Node.js (includes npm)
    pnpm                # Fast Node.js package manager
    r                   # R language for statistical computing
    gcc                 # GNU Compiler Collection (C, C++, Fortran)
    go                  # Go programming language
    rustup              # Rust toolchain installer (includes cargo, rustc)

    # Python tooling
    uv                  # Fast Python package manager

    # EDA / Hardware design
    icarus-verilog      # Verilog simulation and synthesis
    yosys               # Verilog RTL synthesis
    verilator           # Verilog/SystemVerilog simulator
    verible             # SystemVerilog parser, linter, formatter (from tap)
    surfer              # Waveform viewer (VCD, FST, GHW)
    graphviz            # Graph visualization (dot, neato, etc.)

    # Terminal utilities
    tree                # Directory listing as tree
    fzf                 # Fuzzy finder
    jq                  # JSON processor
    eza                 # Modern replacement for ls (colors, icons)
    zoxide              # Smarter cd command ("oxide")
    ripgrep             # Fast grep replacement (rg)
    coreutils           # GNU core utilities (gls, gdate, etc.)
    wget                # Network downloader
    curl                # URL transfer tool (updated)
    bat                 # Cat clone with syntax highlighting
    fd                  # Fast find replacement
    htop                # Interactive process viewer
    tldr                # Simplified man pages
    dust                # Intuitive disk usage (du replacement)
    bottom              # System monitor (btm command)
    hyperfine           # Command-line benchmarking tool
    difftastic          # Structural diff tool (understands syntax)

    # Build tools
    cmake               # Cross-platform build system
    llvm                # LLVM compiler infrastructure
    pandoc              # Universal document converter

    # Homebrew TUI
    bbrew               # Bold Brew — TUI for Homebrew (from tap)
)

if $SKIP_FORMULAE; then
    warn "Skipping formulae (--skip-formulae)"
else
    for formula in "${FORMULAE[@]}"; do
        info "Installing $formula..."
        install_or_warn "brew install $formula" "$formula"
    done
fi

# ─────────────────────────────────────────────────────────────────────
# CASKS (GUI apps & fonts — brew install --cask)
# ─────────────────────────────────────────────────────────────────────
section "Installing Casks (GUI Apps)"

CASKS=(
    # Editors & IDEs
    visual-studio-code  # Code editor by Microsoft
    coteditor           # Lightweight plain-text editor for macOS

    # Git GUI
    github              # GitHub Desktop

    # AI
    claude              # Anthropic Claude desktop app

    # Productivity
    microsoft-office    # Microsoft 365 (Word, Excel, PowerPoint, etc.)
    setapp              # Setapp app subscription platform
    google-drive        # Google drive client

    # LaTeX
    mactex              # Full TeX Live distribution (large ~5 GB download)
    texifier            # LaTeX editor for macOS

    # Research & graphics
    zotero              # Reference manager
    inkscape            # Vector graphics editor

    # Terminal
    iterm2              # Terminal emulator

    # Networking & security
    tailscale           # Mesh VPN
    1password           # Password manager
    1password-cli       # 1Password CLI (op command)

    # Browser & messaging
    ulaa                # Ulaa Browser (Zoho, privacy-focused)
    whatsapp            # WhatsApp desktop

    # Window management
    alt-tab             # Windows-style alt-tab switcher
    rectangle-pro       # Window snapping and management

    # Fonts (Nerd Font patched — needed for Powerlevel10k icons)
    font-meslo-lg-nerd-font
    font-jetbrains-mono-nerd-font
)

if $SKIP_CASKS; then
    warn "Skipping casks (--skip-casks)"
else
    for cask in "${CASKS[@]}"; do
        info "Installing $cask..."
        install_or_warn "brew install --cask $cask" "$cask (cask)"
    done
fi

# ─────────────────────────────────────────────────────────────────────
# NPM GLOBAL PACKAGES (requires node to be installed first)
# ─────────────────────────────────────────────────────────────────────
section "Installing npm Global Packages"

# Ensure Homebrew node is on PATH for this session
export PATH="$BREW_PREFIX/bin:$PATH"

if command -v npm &>/dev/null; then
    info "Installing netlistsvg (schematic viewer for Yosys JSON netlists)..."
    install_or_warn "npm install -g netlistsvg" "netlistsvg (npm)"
else
    warn "npm not found — skipping netlistsvg. Install node first, then run: npm install -g netlistsvg"
    FAILED_ITEMS+=("netlistsvg (npm)")
fi

# ─────────────────────────────────────────────────────────────────────
# POST-INSTALL: SHELL SETUP
# ─────────────────────────────────────────────────────────────────────
if $SKIP_SHELL; then
    section "Post-Install: Shell Configuration"
    warn "Skipping shell configuration (--skip-shell)"
else

section "Post-Install: Shell Configuration"

BREW_BASH="$BREW_PREFIX/bin/bash"
BREW_ZSH="$BREW_PREFIX/bin/zsh"

# Add Homebrew bash and zsh to /etc/shells if not already there
if [ -f "$BREW_BASH" ] && ! grep -qF "$BREW_BASH" /etc/shells; then
    info "Adding Homebrew bash to /etc/shells (requires password)..."
    echo "$BREW_BASH" | sudo tee -a /etc/shells >/dev/null
    success "Added $BREW_BASH to /etc/shells"
fi

if [ -f "$BREW_ZSH" ] && ! grep -qF "$BREW_ZSH" /etc/shells; then
    info "Adding Homebrew zsh to /etc/shells (requires password)..."
    echo "$BREW_ZSH" | sudo tee -a /etc/shells >/dev/null
    success "Added $BREW_ZSH to /etc/shells"
fi

# Set Homebrew zsh as default shell
if [ -f "$BREW_ZSH" ]; then
    CURRENT_SHELL="$(dscl . -read /Users/"$USER" UserShell | awk '{print $2}')"
    if [ "$CURRENT_SHELL" != "$BREW_ZSH" ]; then
        info "Changing default shell to Homebrew zsh (requires password)..."
        chsh -s "$BREW_ZSH"
        success "Default shell changed to $BREW_ZSH"
    else
        success "Default shell is already $BREW_ZSH"
    fi
fi

# ─────────────────────────────────────────────────────────────────────
# POST-INSTALL: GIT LFS
# ─────────────────────────────────────────────────────────────────────
section "Post-Install: Git LFS"

if command -v git-lfs &>/dev/null; then
    git lfs install
    success "Git LFS initialized"
else
    warn "git-lfs not found — skipping"
fi

# ─────────────────────────────────────────────────────────────────────
# POST-INSTALL: GIT GLOBAL CONFIG
# ─────────────────────────────────────────────────────────────────────
section "Post-Install: Git Global Config"

CURRENT_GIT_NAME="$(git config --global user.name 2>/dev/null || echo "")"
CURRENT_GIT_EMAIL="$(git config --global user.email 2>/dev/null || echo "")"

if [ -n "$CURRENT_GIT_NAME" ] && [ -n "$CURRENT_GIT_EMAIL" ]; then
    info "Git is already configured:"
    echo "    Name:  $CURRENT_GIT_NAME"
    echo "    Email: $CURRENT_GIT_EMAIL"
    echo ""
    read -r -p "    Do you want to change these? [y/N] " change_git
    if [[ "$change_git" =~ ^[Yy]$ ]]; then
        CURRENT_GIT_NAME=""
        CURRENT_GIT_EMAIL=""
    else
        success "Git global config unchanged"
    fi
fi

if [ -z "$CURRENT_GIT_NAME" ]; then
    echo ""
    read -r -p "    Enter your full name for Git (e.g. Your Name): " git_name
    if [ -n "$git_name" ]; then
        git config --global user.name "$git_name"
        success "Git user.name set to: $git_name"
    else
        warn "No name entered — skipping git user.name"
    fi
fi

if [ -z "$CURRENT_GIT_EMAIL" ]; then
    read -r -p "    Enter your email for Git (e.g. you@example.com): " git_email
    if [ -n "$git_email" ]; then
        git config --global user.email "$git_email"
        success "Git user.email set to: $git_email"
    else
        warn "No email entered — skipping git user.email"
    fi
fi

# Set sensible defaults if not already configured
git config --global init.defaultBranch main 2>/dev/null
git config --global pull.rebase false 2>/dev/null
git config --global core.autocrlf input 2>/dev/null
success "Git defaults set (init.defaultBranch=main, pull.rebase=false, core.autocrlf=input)"

# ─────────────────────────────────────────────────────────────────────
# POST-INSTALL: RUST (rustup-init)
# ─────────────────────────────────────────────────────────────────────
section "Post-Install: Rust Toolchain"

# rustup is keg-only, so we need the full path
RUSTUP_INIT="$BREW_PREFIX/opt/rustup/bin/rustup-init"
if [ -f "$RUSTUP_INIT" ]; then
    if [ ! -d "$HOME/.rustup" ]; then
        info "Initializing Rust toolchain via rustup (non-interactive)..."
        "$RUSTUP_INIT" -y --no-modify-path
        success "Rust toolchain installed"
    else
        success "Rust toolchain already initialized (~/.rustup exists)"
    fi
else
    warn "rustup-init not found at $RUSTUP_INIT — skipping Rust setup"
fi

# ─────────────────────────────────────────────────────────────────────
# POST-INSTALL: FZF KEY BINDINGS & COMPLETION
# ─────────────────────────────────────────────────────────────────────
section "Post-Install: fzf Key Bindings"

FZF_INSTALL="$BREW_PREFIX/opt/fzf/install"
if [ -f "$FZF_INSTALL" ]; then
    info "Installing fzf key bindings and fuzzy completion..."
    "$FZF_INSTALL" --all --no-bash --no-fish --key-bindings --completion --update-rc
    success "fzf key bindings installed"
else
    warn "fzf install script not found — skipping"
fi

# ─────────────────────────────────────────────────────────────────────
# POST-INSTALL: MacTeX PATH
# ─────────────────────────────────────────────────────────────────────
section "Post-Install: MacTeX PATH"

if [ -d "/Library/TeX/texbin" ]; then
    info "MacTeX detected — running path_helper to update PATH..."
    eval "$(/usr/libexec/path_helper)"
    success "MacTeX PATH configured"
else
    warn "MacTeX texbin not found — it may still be installing. Run later:"
    echo "    eval \"\$(/usr/libexec/path_helper)\""
fi

# ─────────────────────────────────────────────────────────────────────
# POST-INSTALL: OH MY ZSH
# ─────────────────────────────────────────────────────────────────────
section "Post-Install: Oh My Zsh"

if [ ! -d "$HOME/.oh-my-zsh" ]; then
    info "Installing Oh My Zsh (unattended)..."
    RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    success "Oh My Zsh installed"
else
    success "Oh My Zsh already installed"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# ─────────────────────────────────────────────────────────────────────
# POST-INSTALL: POWERLEVEL10K THEME
# ─────────────────────────────────────────────────────────────────────
section "Post-Install: Powerlevel10k Theme"

P10K_DIR="$ZSH_CUSTOM/themes/powerlevel10k"
if [ ! -d "$P10K_DIR" ]; then
    info "Cloning Powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
    success "Powerlevel10k installed"
else
    success "Powerlevel10k already installed"
fi

# ─────────────────────────────────────────────────────────────────────
# POST-INSTALL: ZSH PLUGINS
# ─────────────────────────────────────────────────────────────────────
section "Post-Install: Zsh Plugins"

# zsh-autosuggestions
AUTOSUGG_DIR="$ZSH_CUSTOM/plugins/zsh-autosuggestions"
if [ ! -d "$AUTOSUGG_DIR" ]; then
    info "Cloning zsh-autosuggestions..."
    git clone https://github.com/zsh-users/zsh-autosuggestions.git "$AUTOSUGG_DIR"
    success "zsh-autosuggestions installed"
else
    success "zsh-autosuggestions already installed"
fi

# zsh-syntax-highlighting (provides better autocomplete visual feedback)
SYNHI_DIR="$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
if [ ! -d "$SYNHI_DIR" ]; then
    info "Cloning zsh-syntax-highlighting..."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$SYNHI_DIR"
    success "zsh-syntax-highlighting installed"
else
    success "zsh-syntax-highlighting already installed"
fi

# zsh-completions (additional completion definitions)
ZSHCOMP_DIR="$ZSH_CUSTOM/plugins/zsh-completions"
if [ ! -d "$ZSHCOMP_DIR" ]; then
    info "Cloning zsh-completions..."
    git clone https://github.com/zsh-users/zsh-completions.git "$ZSHCOMP_DIR"
    success "zsh-completions installed"
else
    success "zsh-completions already installed"
fi

# ─────────────────────────────────────────────────────────────────────
# UPDATE SHELL CONFIG FILES
# Preserves existing content in all files using marker-based injection.
# Structure:
#   ~/.zsh_paths   — PATH exports, env variables
#   ~/.zsh_aliases — aliases and shell shortcuts
#   ~/.zshrc       — sources both + Oh My Zsh + plugins
# ─────────────────────────────────────────────────────────────────────
section "Updating Shell Config Files (preserving your existing config)"

ZSHRC="$HOME/.zshrc"
ZSH_PATHS="$HOME/.zsh_paths"
ZSH_ALIASES="$HOME/.zsh_aliases"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# Back up any existing files
for f in "$ZSHRC" "$ZSH_PATHS" "$ZSH_ALIASES"; do
    if [ -f "$f" ]; then
        cp "$f" "${f}.backup.${TIMESTAMP}"
        info "Backed up $(basename "$f") to $(basename "${f}.backup.${TIMESTAMP}")"
    else
        touch "$f"
    fi
done

# ── Helper: inject a block between markers into a given file ─────────
# Usage: inject_block "FILE" "BLOCK_ID" "content"
inject_block() {
    local target_file="$1"
    local block_id="$2"
    local content="$3"
    local begin_marker="### BEGIN $block_id (managed by mac-setup.sh — do not edit)"
    local end_marker="### END $block_id"

    if grep -qF "$begin_marker" "$target_file" 2>/dev/null; then
        # Block exists — replace its content.
        # Write new content to a temp file so awk can read it
        # (awk -v can't handle multi-line strings).
        local content_file tmpfile
        content_file="$(mktemp)"
        tmpfile="$(mktemp)"
        printf '%s\n' "$content" > "$content_file"
        awk -v bm="$begin_marker" -v em="$end_marker" -v cf="$content_file" '
            $0 == bm { print; while ((getline line < cf) > 0) print line; close(cf); skip=1; next }
            $0 == em  { skip=0; print; next }
            !skip     { print }
        ' "$target_file" > "$tmpfile"
        mv "$tmpfile" "$target_file"
        rm -f "$content_file"
    else
        # Block doesn't exist — append it
        {
            echo ""
            echo "$begin_marker"
            echo "$content"
            echo "$end_marker"
        } >> "$target_file"
    fi
}

# ── Helper: inject a block that MUST be at the very top of a file ────
inject_block_top() {
    local target_file="$1"
    local block_id="$2"
    local content="$3"
    local begin_marker="### BEGIN $block_id (managed by mac-setup.sh — do not edit)"
    local end_marker="### END $block_id"

    # Remove existing block if present
    if grep -qF "$begin_marker" "$target_file" 2>/dev/null; then
        local tmpfile
        tmpfile="$(mktemp)"
        awk -v bm="$begin_marker" -v em="$end_marker" '
            $0 == bm { skip=1; next }
            $0 == em { skip=0; next }
            !skip { print }
        ' "$target_file" > "$tmpfile"
        mv "$tmpfile" "$target_file"
    fi

    # Prepend to top
    local tmpfile
    tmpfile="$(mktemp)"
    {
        echo "$begin_marker"
        echo "$content"
        echo "$end_marker"
        echo ""
        cat "$target_file"
    } > "$tmpfile"
    mv "$tmpfile" "$target_file"
}

# ═════════════════════════════════════════════════════════════════════
#  FILE 1: ~/.zsh_paths — PATH exports and environment variables
# ═════════════════════════════════════════════════════════════════════
info "Configuring ~/.zsh_paths ..."

inject_block "$ZSH_PATHS" "HOMEBREW-ENV" \
'# Homebrew shell environment (Apple Silicon vs Intel)
if [[ -f /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi
BREW_PREFIX="$(brew --prefix 2>/dev/null || echo '\''/opt/homebrew'\'')"'

inject_block "$ZSH_PATHS" "PATH-OVERRIDES" \
'# Prefer Homebrew binaries over system defaults (git, python, coreutils, curl)
export PATH="$BREW_PREFIX/bin:$BREW_PREFIX/sbin:$PATH"

# GNU coreutils (use ls instead of gls, etc.)
export PATH="$BREW_PREFIX/opt/coreutils/libexec/gnubin:$PATH"
export MANPATH="$BREW_PREFIX/opt/coreutils/libexec/gnuman:${MANPATH:-}"

# LLVM (clang, clang++, lld, etc.)
export PATH="$BREW_PREFIX/opt/llvm/bin:$PATH"
export LDFLAGS="-L$BREW_PREFIX/opt/llvm/lib"
export CPPFLAGS="-I$BREW_PREFIX/opt/llvm/include"

# Rust (rustup is keg-only — add cargo bin)
export PATH="$HOME/.cargo/bin:$PATH"

# Go
export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:$PATH"

# MacTeX
if [[ -d "/Library/TeX/texbin" ]]; then
  export PATH="/Library/TeX/texbin:$PATH"
fi'

inject_block "$ZSH_PATHS" "EDITOR-CONFIG" \
'# Default editor
export EDITOR='\''code --wait'\''
export VISUAL='\''code --wait'\'''

inject_block "$ZSH_PATHS" "FZF-ENV" \
'# fzf: use ripgrep as default file finder if available
if command -v rg &>/dev/null; then
  export FZF_DEFAULT_COMMAND='\''rg --files --hidden --follow --glob "!.git/*"'\''
fi'

success "~/.zsh_paths configured"

# ═════════════════════════════════════════════════════════════════════
#  FILE 2: ~/.zsh_aliases — aliases and shell shortcuts
# ═════════════════════════════════════════════════════════════════════
info "Configuring ~/.zsh_aliases ..."

inject_block "$ZSH_ALIASES" "EZA-ALIASES" \
'# eza — modern ls replacement with icons and git status
if command -v eza &>/dev/null; then
  alias ls='\''eza --icons --color=always --group-directories-first'\''
  alias ll='\''eza -l --icons --color=always --group-directories-first --git --time-style=long-iso'\''
  alias la='\''eza -la --icons --color=always --group-directories-first --git --time-style=long-iso'\''
  alias lt='\''eza -l --sort=modified --icons --color=always --group-directories-first --git --time-style=long-iso'\''
  alias tree='\''eza --tree --icons --color=always --group-directories-first'\''
fi'

inject_block "$ZSH_ALIASES" "BAT-ALIASES" \
'# bat — cat with syntax highlighting
if command -v bat &>/dev/null; then
  alias cat='\''bat --paging=never'\''
  alias catp='\''bat'\''
fi'

inject_block "$ZSH_ALIASES" "FD-ALIASES" \
'# fd — fast find replacement
if command -v fd &>/dev/null; then
  alias find='\''fd'\''
fi'

inject_block "$ZSH_ALIASES" "GENERAL-ALIASES" \
'# General shortcuts
alias ..='\''cd ..'\''
alias ...='\''cd ../..'\''
alias ....='\''cd ../../..'\''
alias mkdir='\''mkdir -p'\''
alias df='\''df -h'\''
alias du='\''dust'\''
alias top='\''btm'\''
alias diff='\''difft'\''
alias ports='\''lsof -iTCP -sTCP:LISTEN -n -P'\''
alias myip='\''curl -s ifconfig.me'\''
alias reload='\''exec zsh'\'''

inject_block "$ZSH_ALIASES" "GIT-ALIASES" \
'# Git shortcuts (supplement oh-my-zsh git plugin)
alias gs='\''git status'\''
alias gd='\''git diff'\''
alias gds='\''git diff --staged'\''
alias glog='\''git log --oneline --graph --decorate -20'\'''

success "~/.zsh_aliases configured"

# ═════════════════════════════════════════════════════════════════════
#  FILE 3: ~/.zshrc — main shell config (sources paths & aliases)
# ═════════════════════════════════════════════════════════════════════
info "Configuring ~/.zshrc ..."

# P10k instant prompt MUST be the very first thing in .zshrc
inject_block_top "$ZSHRC" "P10K-INSTANT-PROMPT" \
'# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi'

# Source paths file (must come early, before Oh My Zsh needs BREW_PREFIX)
inject_block "$ZSHRC" "SOURCE-PATHS" \
'# Load PATH exports and environment variables
[[ -f ~/.zsh_paths ]] && source ~/.zsh_paths'

# Oh My Zsh configuration
inject_block "$ZSHRC" "OH-MY-ZSH-CONFIG" \
'# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

# Plugins
plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
  zsh-completions
  fzf
)

# zsh-completions: add to fpath BEFORE compinit (sourced by oh-my-zsh)
fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src

source "$ZSH/oh-my-zsh.sh"'

# Source aliases file (after Oh My Zsh so aliases can override omz defaults)
inject_block "$ZSHRC" "SOURCE-ALIASES" \
'# Load aliases and shell shortcuts
[[ -f ~/.zsh_aliases ]] && source ~/.zsh_aliases'

# zoxide init (needs to run, not just be an alias)
inject_block "$ZSHRC" "ZOXIDE" \
'# zoxide — smarter cd command (use "z" to jump, "zi" for interactive)
if command -v zoxide &>/dev/null; then
  eval "$(zoxide init zsh)"
fi'

# fzf source
inject_block "$ZSHRC" "FZF-SOURCE" \
'# fzf key bindings and fuzzy completion
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh'

# Shell history options
inject_block "$ZSHRC" "SHELL-OPTIONS" \
'# History
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_SAVE_NO_DUPS
setopt SHARE_HISTORY'

# P10k config sourcing (should be near the bottom)
inject_block "$ZSHRC" "P10K-SOURCE" \
'# To customize prompt, run: p10k configure
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh'

success "~/.zshrc configured (sources ~/.zsh_paths and ~/.zsh_aliases)"
info "File structure:"
echo "    ~/.zsh_paths   — PATH exports, env variables (edit paths here)"
echo "    ~/.zsh_aliases — aliases and shortcuts (edit aliases here)"
echo "    ~/.zshrc       — sources both + Oh My Zsh + plugins"

fi  # end SKIP_SHELL

# ─────────────────────────────────────────────────────────────────────
# POST-INSTALL: macOS SYSTEM DEFAULTS
# ─────────────────────────────────────────────────────────────────────
if $SKIP_MACOS; then
    section "macOS System Defaults"
    warn "Skipping macOS defaults (--skip-macos)"
else
    section "macOS System Defaults"
    info "Preventing .DS_Store on network and USB volumes..."

    if ! $DRY_RUN; then
        defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true   # No .DS_Store on network volumes
        defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true       # No .DS_Store on USB
        success ".DS_Store defaults applied"
    else
        info "[DRY RUN] Would apply .DS_Store defaults"
    fi
fi

# ─────────────────────────────────────────────────────────────────────
# CLEANUP
# ─────────────────────────────────────────────────────────────────────
section "Cleanup & Brewfile Export"

if ! $DRY_RUN; then
    brew cleanup
    success "Homebrew cache cleaned"

    # Export a Brewfile snapshot for easy replication
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    BREWFILE="$SCRIPT_DIR/Brewfile"
    brew bundle dump --file="$BREWFILE" --force 2>/dev/null && \
        success "Brewfile exported to $BREWFILE" || \
        warn "Could not export Brewfile (brew bundle may not be available)"
else
    info "[DRY RUN] Would clean Homebrew cache and export Brewfile"
fi

# ─────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────
section "Setup Complete!"

TOTAL_ELAPSED=$(( SECONDS - TOTAL_START ))
TOTAL_MIN=$(( TOTAL_ELAPSED / 60 ))
TOTAL_SEC=$(( TOTAL_ELAPSED % 60 ))

echo -e "${GREEN}${BOLD}Everything installed and configured.${NC}\n"
echo -e "  ${BOLD}Stats:${NC}"
echo -e "    Packages installed:  ${GREEN}${INSTALLED_COUNT}${NC}"
echo -e "    Failures:            ${YELLOW}${#FAILED_ITEMS[@]}${NC}"
echo -e "    Total time:          ${CYAN}${TOTAL_MIN}m ${TOTAL_SEC}s${NC}"
echo ""

if [ ${#FAILED_ITEMS[@]} -gt 0 ]; then
    echo -e "${YELLOW}${BOLD}The following items had issues (may need manual attention):${NC}"
    for item in "${FAILED_ITEMS[@]}"; do
        echo -e "  ${YELLOW}•${NC} $item"
    done
    echo ""
fi

echo -e "${BOLD}Manual steps remaining:${NC}"
echo ""
echo -e "  ${CYAN}1.${NC} ${BOLD}Restart your terminal${NC} (or run: exec zsh)"
echo ""
echo -e "  ${CYAN}2.${NC} ${BOLD}Run 'p10k configure'${NC} to set up the Powerlevel10k prompt."
echo "     Choose MesloLGS NF or JetBrainsMono NF as your terminal font."
echo ""
echo -e "  ${CYAN}3.${NC} ${BOLD}Set your iTerm2 font:${NC}"
echo "     Preferences → Profiles → Text → Font → MesloLGS Nerd Font"
echo ""
echo -e "  ${CYAN}4.${NC} ${BOLD}Verify Homebrew versions are default:${NC}"
echo "     which git     → should show $BREW_PREFIX/bin/git"
echo "     which python3 → should show $BREW_PREFIX/bin/python3"
echo "     which zsh     → should show $BREW_PREFIX/bin/zsh"
echo "     which bash    → should show $BREW_PREFIX/bin/bash"
echo ""
echo -e "  ${CYAN}5.${NC} ${BOLD}Sign in to apps:${NC} 1Password, Setapp, Tailscale, GitHub Desktop, etc."
echo ""

if ! $NO_LOG; then
    echo -e "  ${BOLD}Log saved to:${NC} $LOG_FILE"
    echo ""
fi

echo -e "${GREEN}${BOLD}Happy coding! 🚀${NC}"