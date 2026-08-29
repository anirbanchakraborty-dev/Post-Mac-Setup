#!/usr/bin/env bash
#
# ╔══════════════════════════════════════════════════════════════════════╗
# ║                    MAC SETUP SCRIPT v2.0                             ║
# ║              One-shot Mac development environment setup              ║
# ║                                                                      ║
# ║  Run:  chmod +x mac-setup.sh && ./mac-setup.sh                       ║
# ║  Rerun is safe - Homebrew skips already-installed packages.          ║
# ║                                                                      ║
# ║  Flags:  --help          Show usage                                  ║
# ║          --dry-run       Show what would be installed (no changes)   ║
# ║          --upgrade       Also run 'brew upgrade' (off by default)    ║
# ║          --skip-casks    Skip GUI app (cask) installation            ║
# ║          --skip-formulae Skip CLI tool (formula) installation        ║
# ║          --skip-extras   Skip direct downloads (Edge, etc.)          ║
# ║          --skip-github   Skip GitHub CLI auth + git credential setup ║
# ║          --skip-macos    Skip macOS .DS_Store defaults               ║
# ║          --skip-shell    Skip shell config (.zshrc, etc.)            ║
# ║          --no-log        Don't save output to a log file             ║
# ╚══════════════════════════════════════════════════════════════════════╝
#
# NOTE: This script will ask for your password at certain points
#       (adding shells to /etc/shells, changing default shell, mactex, etc.)
#
# Re-exec under a real bash when started by some other shell. `sh mac-setup.sh`
# ignores the shebang above; on macOS /bin/sh IS bash, but in POSIX mode, where
# process substitution is disabled - so the logging line (`exec > >(tee ...)`)
# dies with "syntax error near unexpected token `>'" a third of the way in,
# AFTER the EXIT trap is armed, printing an empty summary that reads like a
# script bug rather than a wrong invocation. (`echo -e` also stops working, so
# the output picks up literal "-e " prefixes.) Arrays and [[ ]] are used
# throughout too.
#
# Testing BASH_VERSION alone is not enough: /bin/sh sets it. `set -o posix` is
# the discriminator - "on" under sh, "off" under bash 3.2 and bash 5.x alike.
# POSIXLY_CORRECT must be unset before the exec, because sh exports it and a
# fresh bash that inherits it re-enters POSIX mode, which would make this
# re-exec loop forever. The sentinel is the backstop if that ever fails anyway.
#
# Keep this block POSIX-parseable, and keep it BELOW line 20: usage() prints
# lines 3-20 of this file as the help text.
if [ -z "${BASH_VERSION:-}" ] || [ "$(set -o 2>/dev/null | awk '$1 == "posix" { print $2 }')" = "on" ]; then
    if [ -n "${MAC_SETUP_REEXEC:-}" ]; then
        echo "mac-setup.sh: could not get a non-POSIX bash. Run it as: bash $0" >&2
        exit 1
    fi
    MAC_SETUP_REEXEC=1
    export MAC_SETUP_REEXEC
    unset POSIXLY_CORRECT
    exec bash "$0" "$@"
fi

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────
# ARGUMENT PARSING
# ─────────────────────────────────────────────────────────────────────
DRY_RUN=false
UPGRADE=false
SKIP_CASKS=false
SKIP_FORMULAE=false
SKIP_EXTRAS=false
SKIP_GITHUB=false
SKIP_MACOS=false
SKIP_SHELL=false
NO_LOG=false

usage() {
    sed -n '3,20p' "$0" | sed 's/^# //; s/^#//'
    exit 0
}

for arg in "$@"; do
    case "$arg" in
        --help|-h)       usage ;;
        --dry-run)       DRY_RUN=true ;;
        --upgrade)       UPGRADE=true ;;
        --skip-casks)    SKIP_CASKS=true ;;
        --skip-formulae) SKIP_FORMULAE=true ;;
        --skip-extras)   SKIP_EXTRAS=true ;;
        --skip-github)   SKIP_GITHUB=true ;;
        --skip-macos)    SKIP_MACOS=true ;;
        --skip-shell)    SKIP_SHELL=true ;;
        --no-log)        NO_LOG=true ;;
        *)
            echo "Unknown option: $arg (try --help)"
            exit 1
            ;;
    esac
done

# Guarded: `clear` exits non-zero when TERM is unset (piped output, cron, CI),
# and under `set -e` that would kill the run here - before the EXIT trap that
# prints the summary is even registered, so it would die with no explanation.
clear 2>/dev/null || true

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
SCRIPT_COMPLETED=false
SUDO_KEEPALIVE_PID=""

# Always print a stats summary on exit (success, failure, or Ctrl-C).
# Manual-steps section only prints when the script reached its natural end.
print_summary() {
    local exit_code=$?

    # Stop the sudo keep-alive child if it's still running.
    if [ -n "$SUDO_KEEPALIVE_PID" ] && kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi

    local elapsed=$(( SECONDS - TOTAL_START ))
    local mins=$(( elapsed / 60 ))
    local secs=$(( elapsed % 60 ))

    echo ""
    echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════════════${NC}"
    if $SCRIPT_COMPLETED; then
        echo -e "${CYAN}${BOLD}  Setup Complete!${NC}"
    else
        echo -e "${CYAN}${BOLD}  Setup Aborted (exit $exit_code) - partial summary${NC}"
    fi
    echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BOLD}Stats:${NC}"
    echo -e "    Newly installed:     ${GREEN}${INSTALLED_COUNT}${NC}"
    echo -e "    Already present:     ${CYAN}${SKIPPED_COUNT}${NC}"
    echo -e "    Failures:            ${YELLOW}${#FAILED_ITEMS[@]}${NC}"
    echo -e "    Total time:          ${CYAN}${mins}m ${secs}s${NC}"
    echo ""

    if [ ${#FAILED_ITEMS[@]} -gt 0 ]; then
        echo -e "${YELLOW}${BOLD}Items that had issues (may need manual attention):${NC}"
        for item in "${FAILED_ITEMS[@]}"; do
            echo -e "  ${YELLOW}•${NC} $item"
        done
        echo ""
    fi

    if $SCRIPT_COMPLETED; then
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
        echo "     which git     → should show ${BREW_PREFIX:-/opt/homebrew}/bin/git"
        echo "     which python3 → should show ${BREW_PREFIX:-/opt/homebrew}/bin/python3"
        echo "     which zsh     → should show ${BREW_PREFIX:-/opt/homebrew}/bin/zsh"
        echo "     which bash    → should show ${BREW_PREFIX:-/opt/homebrew}/bin/bash"
        echo ""
        echo -e "  ${CYAN}5.${NC} ${BOLD}Sign in to apps:${NC} 1Password, Setapp, Tailscale, etc."
        echo ""

        if ! $NO_LOG && [ -n "${LOG_FILE:-}" ]; then
            echo -e "  ${BOLD}Log saved to:${NC} $LOG_FILE"
            echo ""
        fi

        echo -e "${GREEN}${BOLD}Happy coding! 🚀${NC}"
    fi
}
trap print_summary EXIT

# Run a command, or just describe it under --dry-run.
# Use as: run cmd arg1 arg2 ...   (no shell-eval; arguments preserved)
run() {
    if $DRY_RUN; then
        info "[DRY RUN] Would run: $*"
        return 0
    fi
    "$@"
}

# Install a list of formulae or casks in a single 'brew install' call
# (much faster than per-package), with per-package fallback on batch failure.
# Skips packages already installed and tracks INSTALLED_COUNT / SKIPPED_COUNT.
#
# Usage: batch_install formula pkg1 pkg2 ...
#        batch_install cask   pkg1 pkg2 ...
batch_install() {
    local kind="$1"; shift
    local items=("$@")
    
    # Build the base brew command to avoid empty array expansion errors in Bash 3.2
    local brew_cmd=(brew install)
    [[ "$kind" == "cask" ]] && brew_cmd+=(--cask)

    # Detection below is entirely read-only -- brew list, brew info, and file
    # existence -- so it runs under --dry-run too. That is deliberate: a dry
    # run that cannot see a missing app cannot warn about one, and this helper
    # exists to catch exactly that.

    # Snapshot what is already installed so we can skip without invoking brew.
    local installed_list
    if [[ "$kind" == "cask" ]]; then
        installed_list="$(brew list --cask 2>/dev/null || true)"
    else
        installed_list="$(brew list --formula 2>/dev/null || true)"
    fi

    local to_install=() claimed=()
    for item in "${items[@]}"; do
        # Strip any tap prefix (e.g. chipsalliance/verible/verible -> verible)
        local short="${item##*/}"
        if grep -qFx -- "$short" <<<"$installed_list"; then
            claimed+=("$item")
        else
            to_install+=("$item")
        fi
    done

    # Resolve alias and versioned names before believing anything is missing.
    # `brew list --formula` prints the RESOLVED name (python@3.14) while the
    # FORMULAE array declares the stable alias (python@3), so the exact-match
    # above never found it and every run - including every dry run - reported
    # "Would install formula: python@3" for a package that was already there.
    # Pinning the array to python@3.14 would trade this for a version that
    # breaks at 3.15, so the fix belongs here rather than in the array.
    #
    # One `brew info --json=v2` over just the apparent misses settles it. The
    # `.installed` field is authoritative - non-empty whenever the package is
    # present under ANY of its names - so no name-matching heuristic is needed;
    # the alias list is used only to map the answer back to the declared token.
    # Needs jq, which the formulae step installs, so on a bare first run this
    # is skipped and the miss is real anyway.
    if (( ${#to_install[@]} > 0 )) && command -v jq >/dev/null 2>&1; then
        local alias_flag="--formula" alias_json present_names
        [[ "$kind" == "cask" ]] && alias_flag="--cask"
        if alias_json="$(brew info --json=v2 "$alias_flag" "${to_install[@]}" 2>/dev/null)" \
           && [ -n "$alias_json" ]; then
            present_names="$(printf '%s' "$alias_json" | jq -r '
                ((.formulae // [])[] | select((.installed // [] | length) > 0)
                    | [.name, .full_name] + (.aliases // []) + (.oldnames // []) | .[]),
                ((.casks // [])[] | select(.installed != null)
                    | [.token] + (.old_tokens // []) | .[])
            ' 2>/dev/null || true)"
            if [ -n "$present_names" ]; then
                local still_missing=()
                for item in "${to_install[@]}"; do
                    if grep -qFx -- "${item##*/}" <<<"$present_names"; then
                        claimed+=("$item")
                    else
                        still_missing+=("$item")
                    fi
                done
                to_install=(${still_missing[@]+"${still_missing[@]}"})
            fi
        fi
    fi

    # `brew list --cask` reports Homebrew's RECORDS, not what is on disk. Drag
    # an app to the Trash instead of running `brew uninstall --cask` and the
    # Caskroom entry survives (0 B, but present), so brew keeps listing it and
    # this script kept reporting "already installed" for an app that was gone.
    # That happened to the Claude desktop app on 2026-08-22.
    #
    # So for casks that actually ship an .app, confirm the bundle exists before
    # believing the record. One `brew info --json=v2` covers the whole list.
    # Casks with no app artifact -- CLI tools like 1password-cli, fonts,
    # pkg-based installs -- have nothing to check here and are left alone.
    local to_reinstall=()
    if [[ "$kind" == "cask" && ${#claimed[@]} -gt 0 ]] && command -v jq >/dev/null 2>&1; then
        local cask_json app_line token apps found app
        if cask_json="$(brew info --json=v2 --cask "${claimed[@]}" 2>/dev/null)" && [ -n "$cask_json" ]; then
            while IFS=$'\t' read -r token apps; do
                [ -n "$token" ] || continue
                [ -n "$apps" ] || continue          # no .app artifact: nothing to verify
                found=0
                # Bash 3.2: no mapfile, so split the newline-joined list by IFS.
                local OLD_IFS="$IFS"; IFS='|'
                for app in $apps; do
                    IFS="$OLD_IFS"
                    if [ -e "/Applications/$app" ] || [ -e "$HOME/Applications/$app" ]; then
                        found=1; break
                    fi
                    IFS='|'
                done
                IFS="$OLD_IFS"
                if [ "$found" -eq 0 ]; then
                    warn "$token: Homebrew lists it, but its app is not on disk - reinstalling"
                    to_reinstall+=("$token")
                fi
            done < <(printf '%s' "$cask_json" | jq -r '
                .casks[] | [.token, ([.artifacts[]? | objects | .app? // empty | .[]?] | join("|"))] | @tsv' 2>/dev/null)
        fi
    fi

    # Report the ones that survived verification, then repair the rest. A
    # plain `brew install --cask` refuses a cask brew still believes in
    # ("already installed"), so repairing needs `reinstall`.
    for item in ${claimed[@]+"${claimed[@]}"}; do
        local short="${item##*/}"
        case " ${to_reinstall[*]-} " in
            *" $short "*) ;;
            *) success "$item (already installed)"; (( SKIPPED_COUNT++ )) || true ;;
        esac
    done

    if $DRY_RUN; then
        for item in ${to_install[@]+"${to_install[@]}"}; do
            info "[DRY RUN] Would install $kind: $item"
        done
        for item in ${to_reinstall[@]+"${to_reinstall[@]}"}; do
            info "[DRY RUN] Would reinstall $kind (app missing from disk): $item"
        done
        return
    fi

    if (( ${#to_reinstall[@]} > 0 )); then
        info "Reinstalling ${#to_reinstall[@]} $kind(s) whose app is missing: ${to_reinstall[*]}"
        for item in "${to_reinstall[@]}"; do
            if brew reinstall --cask "$item" >/dev/null 2>&1; then
                success "$item (reinstalled)"
                (( INSTALLED_COUNT++ )) || true
            else
                error "Failed to reinstall $item"
                FAILED_ITEMS+=("$item (cask, reinstall)")
            fi
        done
    fi

    if (( ${#to_install[@]} == 0 )); then
        info "Nothing new to install for $kind"
        return
    fi

    # Drop packages Homebrew has DISABLED upstream before we build the batch.
    # `brew install a b c ...` refuses the entire batch when any one argument
    # is a disabled formula, so a single upstream deprecation turns one fast
    # batched call into 40+ sequential installs. (`tldr` was disabled on
    # 2025-10-24 and did exactly that.) One `brew info --json=v2` call covers
    # the whole list in about 0.3s and carries each package's disabled flag,
    # so the casualty gets named in the summary instead of being buried in
    # brew's output. Requires jq, which the formulae step installs - on a
    # first run against a bare machine jq is not there yet, so this is a
    # best-effort guard and the per-package fallback below remains the net.
    if command -v jq >/dev/null 2>&1; then
        local kind_flag="--formula"
        [[ "$kind" == "cask" ]] && kind_flag="--cask"
        local meta_json disabled_list
        if meta_json="$(brew info --json=v2 "$kind_flag" "${to_install[@]}" 2>/dev/null)" \
           && [ -n "$meta_json" ]; then
            disabled_list="$(printf '%s' "$meta_json" | jq -r '
                ((.formulae // [])[] | select(.disabled == true)
                    | [.name, .full_name] + (.aliases // []) + (.oldnames // []) | .[]),
                ((.casks // [])[] | select(.disabled == true)
                    | [.token] + (.old_tokens // []) | .[])
            ' 2>/dev/null || true)"
            if [ -n "$disabled_list" ]; then
                local kept=()
                for item in "${to_install[@]}"; do
                    local short="${item##*/}"
                    if grep -qFx -- "$short" <<<"$disabled_list" \
                       || grep -qFx -- "$item" <<<"$disabled_list"; then
                        warn "Skipping $item - Homebrew disabled this $kind upstream"
                        FAILED_ITEMS+=("$item ($kind, disabled upstream)")
                    else
                        kept+=("$item")
                    fi
                done
                # Bash 3.2 (the system bash a fresh Mac still runs this under)
                # errors on "${empty[@]}" with set -u; the ${x[@]+...} guard
                # expands to nothing instead.
                to_install=(${kept[@]+"${kept[@]}"})
            fi
        fi
        if (( ${#to_install[@]} == 0 )); then
            info "Nothing installable left for $kind"
            return
        fi
    fi

    info "Installing ${#to_install[@]} new $kind(s) in one batch: ${to_install[*]}"
    if "${brew_cmd[@]}" "${to_install[@]}"; then
        for item in "${to_install[@]}"; do
            success "$item"
            (( INSTALLED_COUNT++ )) || true
        done
        return
    fi

    warn "Batch install failed - falling back to one-by-one"
    for item in "${to_install[@]}"; do
        if "${brew_cmd[@]}" "$item"; then
            success "$item"
            (( INSTALLED_COUNT++ )) || true
        else
            warn "Failed to install $kind: $item (continuing...)"
            FAILED_ITEMS+=("$item ($kind)")
        fi
    done
}

# Download a .pkg from a URL and run /usr/sbin/installer on it.
# Used for vendor apps that don't have a Homebrew cask, or where the user
# explicitly wants the publisher's own installer (e.g. Microsoft Edge).
#
# Usage: install_pkg_from_url "<app-path>" "<label>" "<url>" [installed_ver] [latest_ver]
#
# If both installed_ver and latest_ver are non-empty and equal, the install
# is skipped. If they differ, the .pkg is (re)downloaded to upgrade in place.
# If either is empty (e.g. couldn't fetch latest), falls back to the legacy
# behavior: skip if app_path exists, else install.
install_pkg_from_url() {
    local app_path="$1"
    local label="$2"
    local url="$3"
    local installed_ver="${4:-}"
    local latest_ver="${5:-}"

    if [ -d "$app_path" ]; then
        if [ -n "$installed_ver" ] && [ -n "$latest_ver" ]; then
            if [ "$installed_ver" = "$latest_ver" ]; then
                success "$label (already installed, $installed_ver up to date)"
                (( SKIPPED_COUNT++ )) || true
                return
            else
                info "$label installed: $installed_ver, latest: $latest_ver - upgrading"
                # fall through to download + install
            fi
        else
            success "$label (already installed)"
            (( SKIPPED_COUNT++ )) || true
            return
        fi
    fi

    if $DRY_RUN; then
        info "[DRY RUN] Would download $label from $url and run 'sudo installer -pkg ... -target /'"
        return
    fi

    local tmpdir pkg_path
    tmpdir="$(mktemp -d)"
    # Filename matters for installer logging only; .pkg extension required.
    pkg_path="$tmpdir/$(echo "$label" | tr ' ' '_').pkg"

    info "Downloading $label from $url ..."
    if ! curl -fsSL --retry 3 --retry-delay 2 -o "$pkg_path" "$url"; then
        warn "Failed to download $label"
        FAILED_ITEMS+=("$label (download)")
        rm -rf "$tmpdir"
        return
    fi

    info "Installing $label (requires sudo)..."
    if sudo installer -pkg "$pkg_path" -target /; then
        success "$label"
        (( INSTALLED_COUNT++ )) || true
    else
        warn "Failed to install $label via /usr/sbin/installer"
        FAILED_ITEMS+=("$label (installer)")
    fi
    rm -rf "$tmpdir"
}

# ─────────────────────────────────────────────────────────────────────
# LOGGING - tee all output to a timestamped log file
# Uses ~/Library/Logs (the macOS-native log location) so logs survive
# reboots and the periodic /tmp purge.
# ─────────────────────────────────────────────────────────────────────
LOG_DIR="$HOME/Library/Logs/mac-setup"
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
    warn "DRY RUN MODE - no changes will be made"
fi
echo ""
echo -e "  ${BOLD}Configuration:${NC}"
echo -e "    Formulae (CLI):    $( $SKIP_FORMULAE && echo "${YELLOW}SKIP${NC}" || echo "${GREEN}install${NC}" )"
echo -e "    Casks (GUI):       $( $SKIP_CASKS    && echo "${YELLOW}SKIP${NC}" || echo "${GREEN}install${NC}" )"
echo -e "    Extras (direct):   $( $SKIP_EXTRAS   && echo "${YELLOW}SKIP${NC}" || echo "${GREEN}install${NC}" )"
echo -e "    GitHub CLI auth:   $( $SKIP_GITHUB  && echo "${YELLOW}SKIP${NC}" || echo "${GREEN}configure${NC}" )"
echo -e "    macOS defaults:    $( $SKIP_MACOS    && echo "${YELLOW}SKIP${NC}" || echo "${GREEN}apply${NC}" )"
echo -e "    Shell config:      $( $SKIP_SHELL    && echo "${YELLOW}SKIP${NC}" || echo "${GREEN}configure${NC}" )"
echo ""

if ! $DRY_RUN; then
    read -r -p "  Press Enter to continue (or Ctrl-C to abort)... "
fi

# Cache sudo credentials upfront so /etc/shells, chsh, etc. don't block
# halfway through a 5 GB MacTeX download. Background keep-alive refreshes
# the timestamp every minute until the script exits.
if ! $DRY_RUN; then
    info "Caching sudo credentials (you'll be prompted once)..."
    if ! sudo -v; then
        error "Could not obtain sudo. Some steps (e.g. /etc/shells, chsh) will fail."
    else
        # Keep the sudo timestamp warm; child exits when this script does.
        ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 60; done ) &
        SUDO_KEEPALIVE_PID=$!
        info "Sudo cached (keep-alive PID: $SUDO_KEEPALIVE_PID)"
    fi
fi

# Ensure Xcode CLT is installed (required by Homebrew and many formulae).
# 'xcode-select --install' returns immediately and pops a GUI installer;
# poll until the toolchain is actually present rather than waiting for a key.
if ! xcode-select -p &>/dev/null; then
    if $DRY_RUN; then
        info "[DRY RUN] Would install Xcode Command Line Tools"
    else
        info "Installing Xcode Command Line Tools (GUI installer will appear)..."
        xcode-select --install 2>/dev/null || true
        info "Waiting for installation to complete (polling every 5s)..."
        until xcode-select -p &>/dev/null; do
            sleep 5
        done
    fi
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
run brew update
if $UPGRADE; then
    info "--upgrade flag set: upgrading already-installed packages..."
    run brew upgrade
else
    info "Skipping 'brew upgrade' (pass --upgrade to enable)"
fi
success "Homebrew updated"

# ─────────────────────────────────────────────────────────────────────
# TAPS (third-party repositories)
# ─────────────────────────────────────────────────────────────────────
section "Adding Taps"

# Write each entry the way `brew tap` PRINTS it - "<user>/<name>", with no
# "homebrew-" prefix - because the already-tapped check below is a full-line
# grep against that output. "Valkyrie00/homebrew-bbrew" could never match the
# printed "valkyrie00/bbrew", so that tap was re-tapped on every single run and
# counted as newly installed in the summary. (The -i flag covers the casing;
# the "homebrew-" prefix is what actually broke it.)
TAPS=(
    "chipsalliance/verible"       # Verible - only source, not in homebrew/core
    "jithin-sabu/tap"             # Purge - only source, not in homebrew/cask
)

# Each tap above is TRUSTED right after it is tapped. Recent Homebrew sets
# $HOMEBREW_REQUIRE_TAP_TRUST by default and refuses to load formulae from
# untrusted third-party taps - it prints "Skipping <tap> because it is not
# trusted" and silently leaves the package uninstalled, so without this
# `brew install verible` below is a no-op and `brew upgrade` skips it too.
# (bbrew was the other formula this protected until it graduated to
# homebrew/core; its tap was dropped 2026-08-21.) Trust is recorded in ~/.homebrew/trust.json
# (or $XDG_CONFIG_HOME/homebrew/trust.json when that env var is set).
#
# Trust is granted at TAP level rather than per-formula. Per-formula trust is
# tighter, but $HOMEBREW_REQUIRE_TAP_TRUST also gates the commands that
# evaluate every formula and cask - which is what `brew bundle dump` in the
# cleanup step does - so a tap-level entry is what keeps the whole run clean.
#
# The formulae below are then resolved as a check that the trust actually
# took: `brew info` resolves against the tap, so a typo in a tap name or a
# tap that failed to clone surfaces here as a reported failure instead of a
# silent no-op at install time.
# Despite the name, this array holds tapped CASKS as well as formulae - the
# resolution check below tries both. Keeping one list means a new tap cannot be
# added without also proving it resolves.
TRUST_FORMULAE=(
    "chipsalliance/verible/verible"   # Verible (from chipsalliance/verible) - formula
    "jithin-sabu/tap/purge"           # Purge (from jithin-sabu/tap) - CASK, not a formula
)

if $DRY_RUN; then
    for tap in "${TAPS[@]}"; do
        info "[DRY RUN] Would tap and trust: $tap"
    done
    for f in "${TRUST_FORMULAE[@]}"; do
        info "[DRY RUN] Would verify tapped formula resolves: $f"
    done
else
    EXISTING_TAPS="$(brew tap)"
    for tap in "${TAPS[@]}"; do
        if grep -qFix -- "$tap" <<<"$EXISTING_TAPS"; then
            success "tap: $tap (already tapped)"
            (( SKIPPED_COUNT++ )) || true
        else
            info "Tapping $tap..."
            if brew tap "$tap"; then
                success "tap: $tap"
                (( INSTALLED_COUNT++ )) || true
            else
                warn "Failed to tap: $tap"
                FAILED_ITEMS+=("tap: $tap")
            fi
        fi

        # Trust the tap so the install/upgrade steps below actually load its
        # formulae. `brew trust` is a recent subcommand; older Homebrew lacks
        # it and also does not enforce trust, so guard on its availability.
        # Re-trusting an already-trusted tap prints "Already trusted tap" and
        # changes nothing, so this is safe on every rerun.
        if brew trust --help >/dev/null 2>&1; then
            brew trust --tap "$tap" >/dev/null 2>&1 || true
        fi
    done

    # Verify each tapped package now resolves. `brew trust` does no existence
    # check of its own, so its exit code cannot confirm the tap is usable;
    # `brew info` does resolve against the tap, which turns a typo or a tap
    # that failed to clone into a reported failure rather than a package that
    # quietly never installs.
    #
    # Both --formula and --cask are tried, because this list holds both kinds.
    # The check was --formula only until 2026-08-27, which was fine while every
    # entry was a formula; adding the tapped cask jithin-sabu/tap/purge made it
    # report a working tap as broken. Neither flag can be dropped in favour of a
    # bare `brew info`, which is ambiguous when a formula and a cask share a name.
    if brew trust --help >/dev/null 2>&1; then
        for f in "${TRUST_FORMULAE[@]}"; do
            if brew info --formula "$f" >/dev/null 2>&1 || brew info --cask "$f" >/dev/null 2>&1; then
                success "trusted and resolvable: $f"
            else
                warn "Could not resolve $f (typo in TRUST_FORMULAE or missing tap?) - brew may skip it"
                FAILED_ITEMS+=("trust: $f")
            fi
        done
    else
        info "brew trust unavailable on this Homebrew - tap-trust step skipped"
    fi
fi

# ─────────────────────────────────────────────────────────────────────
# FORMULAE (CLI tools - brew install)
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
    git-filter-repo     # Rewrite git history (purge files, rewrite authors)

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
    sby                 # SymbiYosys - formal verification front-end for Yosys
    verilator           # Verilog/SystemVerilog simulator
    verible             # SystemVerilog parser, linter, formatter (from tap)
    surfer              # Waveform viewer (VCD, FST, GHW)
    graphviz            # Graph visualization (dot, neato, etc.)

    # RISC-V toolchain (for the CPU-design-from-scratch project)
    riscv64-elf-gcc     # Bare-metal RISC-V cross compiler (riscv64-elf target)
    dtc                 # Device tree compiler

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
    tlrc                # Simplified man pages (the `tldr` formula was disabled upstream 2025-10-24)
    dust                # Intuitive disk usage (du replacement)
    bottom              # System monitor (btm command)
    hyperfine           # Command-line benchmarking tool
    difftastic          # Structural diff tool (understands syntax)

    # Build tools
    cmake               # Cross-platform build system
    llvm                # LLVM compiler infrastructure
    pandoc              # Universal document converter
    plantuml            # UML/sequence/activity diagrams from plain text (uses graphviz)
    poppler             # PDF utilities (pdftotext, pdfinfo, pdftoppm, pdfimages)

    # Homebrew TUI
    bbrew               # Bold Brew - TUI for Homebrew (now in homebrew/core)

    # Deliberately NOT listed: ghostscript. It is a declared dependency of the
    # mactex cask below, so a bare machine gets it automatically. Homebrew 6.x
    # marks cask-required formulae installed_on_request, so it surfaces in
    # `brew bundle dump` and looks like undeclared drift on every audit - it
    # is not. Same call was made in f0c9a03; see also gcc, which IS listed but
    # arrives transitively via r/openblas.
)

if $SKIP_FORMULAE; then
    warn "Skipping formulae (--skip-formulae)"
else
    batch_install formula "${FORMULAE[@]}"
fi

# ─────────────────────────────────────────────────────────────────────
# CASKS (GUI apps & fonts - brew install --cask)
# ─────────────────────────────────────────────────────────────────────
section "Installing Casks (GUI Apps)"

CASKS=(
    # Editors & IDEs
    visual-studio-code  # Code editor by Microsoft
    coteditor           # Lightweight plain-text editor for macOS

    # AI
    claude              # Anthropic Claude desktop app (GUI)
    claude-code         # Anthropic Claude Code (terminal CLI assistant)
    lm-studio           # Local LLM runner (discover, download, run models offline)

    # Productivity
    microsoft-office    # Microsoft 365 (Word, Excel, PowerPoint, etc.)
    setapp              # Setapp app subscription platform
    obsidian            # Markdown-based knowledge base / note-taking app

    # LaTeX
    mactex              # Full TeX Live distribution (large ~5 GB download)
    texifier            # LaTeX editor for macOS
    skim                # PDF viewer with SyncTeX support (preferred for LaTeX)

    # Research & graphics
    zotero              # Reference manager
    inkscape            # Vector graphics editor

    # Photography (Nikon Z6III workflow - see Photography/ in the hub)
    nx-studio           # Nikon viewing/processing/editing suite (pkg install, no .app artifact)

    # Media & audio
    iina                # Media player (free, open-source)
    finetune            # Per-application volume mixer, equalizer and audio routing

    # Terminal
    iterm2              # Terminal emulator

    # Networking & security
    tailscale-app       # Mesh VPN (cask renamed from 'tailscale' upstream)
    1password           # Password manager
    1password-cli       # 1Password CLI (op command)

    # Browser & messaging
    whatsapp            # WhatsApp desktop

    # Window management
    loop                # Window manager (replaced rectangle-pro 2026-08-27)

    # Menu bar
    blip                # Wallpaper manager
    stats               # System monitor for the menu bar
    thaw                # Menu bar manager

    # System maintenance
    pearcleaner         # Uninstall apps and remove their leftover files
    purge               # Clear cache and junk files (from jithin-sabu/tap - see TAPS)

    # Fonts (Nerd Font patched - needed for Powerlevel10k icons)
    font-meslo-lg-nerd-font
    font-jetbrains-mono-nerd-font
)

if $SKIP_CASKS; then
    warn "Skipping casks (--skip-casks)"
else
    batch_install cask "${CASKS[@]}"
fi

# ─────────────────────────────────────────────────────────────────────
# NPM GLOBAL PACKAGES (requires node to be installed first)
# ─────────────────────────────────────────────────────────────────────
section "Installing npm Global Packages"

# Ensure Homebrew node is on PATH for this session
export PATH="$BREW_PREFIX/bin:$PATH"

# Detection runs under --dry-run too. It is read-only, and an unconditional
# "[DRY RUN] Would install" placed ahead of it reported packages that were
# already present - the same early-return bug batch_install had until
# 2026-08-22. A dry run that cannot tell present from missing reports nothing.
if ! command -v npm &>/dev/null; then
    warn "npm not found - skipping netlistsvg. Install node first, then run: npm install -g netlistsvg"
    FAILED_ITEMS+=("netlistsvg (npm)")
elif npm list -g --depth=0 netlistsvg &>/dev/null; then
    success "netlistsvg (npm) (already installed)"
    (( SKIPPED_COUNT++ )) || true
elif $DRY_RUN; then
    info "[DRY RUN] Would install netlistsvg via npm"
else
    info "Installing netlistsvg (schematic viewer for Yosys JSON netlists)..."
    if npm install -g netlistsvg; then
        success "netlistsvg (npm)"
        (( INSTALLED_COUNT++ )) || true
    else
        warn "Failed to install netlistsvg"
        FAILED_ITEMS+=("netlistsvg (npm)")
    fi
fi

# ──────────────────────────────────────────────────────────────────
# uv TOOL GLOBAL PACKAGES (CLI tools installed via `uv tool install`)
# ─────────────────────────────────────────────────────────────────────
section "Installing uv Tool Global Packages"

# graphifyy - knowledge-graph builder used by the /graphify skill, vendored into
# Research-Projects/pqc-refmodel/.claude/skills/graphify/ and
# Website-Building-Projects/dranirbanchakraborty.com/.claude/skills/graphify/.
# PyPI package is `graphifyy` (double-y), CLI is `graphify`.
# Detection runs under --dry-run too. It is read-only, and an unconditional
# "[DRY RUN] Would install" placed ahead of it reported packages that were
# already present - the same early-return bug batch_install had until
# 2026-08-22. A dry run that cannot tell present from missing reports nothing.
if ! command -v uv &>/dev/null; then
    warn "uv not found - skipping graphifyy. uv comes from the Homebrew formulae step above; if it failed, install manually then run: uv tool install graphifyy"
    FAILED_ITEMS+=("graphifyy (uv tool)")
elif uv tool list 2>/dev/null | grep -q '^graphifyy '; then
    success "graphifyy (uv tool) (already installed)"
    (( SKIPPED_COUNT++ )) || true
elif $DRY_RUN; then
    info "[DRY RUN] Would install graphifyy via uv tool"
else
    info "Installing graphifyy (knowledge-graph builder for /graphify skill)..."
    if uv tool install graphifyy; then
        success "graphifyy (uv tool)"
        (( INSTALLED_COUNT++ )) || true
    else
        warn "Failed to install graphifyy via uv tool"
        FAILED_ITEMS+=("graphifyy (uv tool)")
    fi
fi

# ──────────────────────────────────────────────────────────────────
# EXTRAS - Direct downloads (apps installed via vendor .pkg, not Homebrew)
# Use this for apps where the publisher's installer is preferred over a
# Homebrew cask (e.g. Microsoft Edge, where the cask just wraps the same
# .pkg but adds an extra layer of staleness).
# ─────────────────────────────────────────────────────────────────────
section "Installing Extras (Direct Downloads)"

if $SKIP_EXTRAS; then
    warn "Skipping extras (--skip-extras)"
else
    # Microsoft Edge - fetched from Microsoft's EdgeUpdates JSON API, which
    # is the only source here that names the architecture it is handing you.
    # The fwlink redirector (linkid=2069148) advertises itself as the
    # canonical "latest" Edge .pkg but serves an x86_64-only build, so an
    # Apple Silicon Mac installing from it ends up running Edge under
    # Rosetta. That is the failure this section exists to prevent, so on an
    # arm64 host fwlink is not used at all: if the API cannot be reached, or
    # cannot name a universal build, Edge is SKIPPED and reported rather than
    # installed wrong. A browser missing until the next run is a smaller
    # problem than a browser silently emulated. On Intel hosts there is no
    # such hazard and fwlink remains a fine fallback.
    EDGE_APP="/Applications/Microsoft Edge.app"
    EDGE_EXE="$EDGE_APP/Contents/MacOS/Microsoft Edge"
    EDGE_FWLINK="https://go.microsoft.com/fwlink/?linkid=2069148"
    EDGE_API="https://edgeupdates.microsoft.com/api/products"
    EDGE_INSTALLED=""
    EDGE_LATEST=""
    EDGE_URL=""
    HOST_ARCH="$(uname -m)"

    # Describe what is on disk as "<version> (<arch>)" so one string compare
    # in install_pkg_from_url catches BOTH a stale version and a
    # wrong-architecture build. Architecture comes from `lipo -archs`, which
    # prints a single line ("x86_64 arm64" for a universal binary). Do not
    # use `file` here: its output for a universal binary spans three lines,
    # and the middle one ends in the exact string "Mach-O 64-bit executable
    # x86_64", which makes a correctly-installed universal build look
    # Intel-only and provokes a pointless reinstall on every run.
    if [ -d "$EDGE_APP" ]; then
        EDGE_VER="$(defaults read "$EDGE_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || true)"
        case "$(lipo -archs "$EDGE_EXE" 2>/dev/null || echo unknown)" in
            *arm64*) EDGE_ARCH="native"  ;;
            *x86_64) EDGE_ARCH="x86_64"  ;;
            *)       EDGE_ARCH="unknown" ;;
        esac
        EDGE_INSTALLED="${EDGE_VER:-unknown} ($EDGE_ARCH)"
    fi

    # Ask the API for the stable macOS universal build, taking the version
    # string and the .pkg URL from the same response so they cannot disagree.
    if command -v jq >/dev/null 2>&1; then
        EDGE_API_JSON="$(curl -fsSL --max-time 10 "$EDGE_API" 2>/dev/null || true)"
        if [ -n "$EDGE_API_JSON" ]; then
            EDGE_LATEST_VER="$(printf '%s' "$EDGE_API_JSON" \
                | jq -r '.[] | select(.Product == "Stable") | .Releases[] | select(.Platform == "MacOS" and .Architecture == "universal") | .ProductVersion' 2>/dev/null \
                | head -1 || true)"
            EDGE_URL="$(printf '%s' "$EDGE_API_JSON" \
                | jq -r '.[] | select(.Product == "Stable") | .Releases[] | select(.Platform == "MacOS" and .Architecture == "universal") | .Artifacts[] | select(.ArtifactName == "pkg") | .Location' 2>/dev/null \
                | head -1 || true)"
            [ -n "${EDGE_LATEST_VER:-}" ] && EDGE_LATEST="$EDGE_LATEST_VER (native)"
        fi
    else
        warn "jq not available - cannot query the EdgeUpdates API for the universal build"
    fi

    if [ -n "$EDGE_URL" ] && [ -n "$EDGE_LATEST" ]; then
        install_pkg_from_url \
            "$EDGE_APP" \
            "Microsoft Edge" \
            "$EDGE_URL" \
            "$EDGE_INSTALLED" \
            "$EDGE_LATEST"
    elif [ "$HOST_ARCH" = "arm64" ]; then
        warn "EdgeUpdates API did not yield a universal build - refusing the x86_64 fwlink installer on Apple Silicon"
        warn "Edge left as-is; rerun once $EDGE_API is reachable"
        FAILED_ITEMS+=("Microsoft Edge (no universal build resolved; Intel fallback refused)")
    else
        info "EdgeUpdates API unavailable - falling back to the fwlink installer (no arch hazard on Intel)"
        install_pkg_from_url \
            "$EDGE_APP" \
            "Microsoft Edge" \
            "$EDGE_FWLINK" \
            "$EDGE_INSTALLED" \
            ""
    fi

    # Confirm what actually landed. The whole point of the section is the
    # architecture, so verify it rather than trusting that the .pkg the API
    # named was the one it described.
    if ! $DRY_RUN && [ "$HOST_ARCH" = "arm64" ] && [ -d "$EDGE_APP" ]; then
        if lipo -archs "$EDGE_EXE" 2>/dev/null | grep -q 'arm64'; then
            success "Microsoft Edge is a native arm64 build"
        else
            warn "Microsoft Edge on disk is still x86_64-only - it will run under Rosetta"
            FAILED_ITEMS+=("Microsoft Edge (installed build is not native arm64)")
        fi
    fi

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
    if $DRY_RUN; then
        info "[DRY RUN] Would add $BREW_BASH to /etc/shells"
    else
        info "Adding Homebrew bash to /etc/shells (requires password)..."
        echo "$BREW_BASH" | sudo tee -a /etc/shells >/dev/null
        success "Added $BREW_BASH to /etc/shells"
    fi
fi

if [ -f "$BREW_ZSH" ] && ! grep -qF "$BREW_ZSH" /etc/shells; then
    if $DRY_RUN; then
        info "[DRY RUN] Would add $BREW_ZSH to /etc/shells"
    else
        info "Adding Homebrew zsh to /etc/shells (requires password)..."
        echo "$BREW_ZSH" | sudo tee -a /etc/shells >/dev/null
        success "Added $BREW_ZSH to /etc/shells"
    fi
fi

# Set Homebrew zsh as default shell
if [ -f "$BREW_ZSH" ]; then
    CURRENT_SHELL="$(dscl . -read /Users/"$USER" UserShell | awk '{print $2}')"
    if [ "$CURRENT_SHELL" != "$BREW_ZSH" ]; then
        if $DRY_RUN; then
            info "[DRY RUN] Would chsh to $BREW_ZSH"
        else
            info "Changing default shell to Homebrew zsh (requires password)..."
            chsh -s "$BREW_ZSH"
            success "Default shell changed to $BREW_ZSH"
        fi
    else
        success "Default shell is already $BREW_ZSH"
    fi
fi

# ─────────────────────────────────────────────────────────────────────
# POST-INSTALL: GIT LFS
# ─────────────────────────────────────────────────────────────────────
section "Post-Install: Git LFS"

if command -v git-lfs &>/dev/null; then
    run git lfs install
    success "Git LFS initialized"
else
    warn "git-lfs not found - skipping"
fi

# ─────────────────────────────────────────────────────────────────────
# POST-INSTALL: GIT GLOBAL CONFIG
# ─────────────────────────────────────────────────────────────────────
section "Post-Install: Git Global Config"

if $DRY_RUN; then
    info "[DRY RUN] Would prompt for git user.name/user.email and set defaults"
else
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
            warn "No name entered - skipping git user.name"
        fi
    fi

    if [ -z "$CURRENT_GIT_EMAIL" ]; then
        read -r -p "    Enter your email for Git (e.g. you@example.com): " git_email
        if [ -n "$git_email" ]; then
            git config --global user.email "$git_email"
            success "Git user.email set to: $git_email"
        else
            warn "No email entered - skipping git user.email"
        fi
    fi

    # Set sensible defaults only if the user hasn't already chosen otherwise.
    # 'git config --get' returns nonzero when the key is unset; that's our signal.
    set_git_default() {
        local key="$1" value="$2"
        if ! git config --global --get "$key" >/dev/null 2>&1; then
            git config --global "$key" "$value"
            info "Set git $key=$value"
        fi
    }
    set_git_default init.defaultBranch main
    set_git_default pull.rebase false
    set_git_default core.autocrlf input
    success "Git defaults checked"
fi

# ─────────────────────────────────────────────────────────────────────
# POST-INSTALL: GITHUB CLI AUTHENTICATION
# ─────────────────────────────────────────────────────────────────────
#
# Installing gh is not the same as being able to use it. The formulae step
# above puts the binary on the machine; this step logs it in and, critically,
# runs 'gh auth setup-git' so that git itself can authenticate to GitHub over
# HTTPS. Without that last part a machine looks completely set up and still
# cannot clone a private repo or push to one.
#
# The logic lives in the hub's Utilities/github-setup.sh rather than here, so
# that this script, hub-bootstrap.sh, and a bare machine with no clone at all
# all run the same code. When mac-setup.sh is run from the standalone copy of
# this folder -- outside the hub -- that file is simply absent and the step
# reports itself skipped instead of failing.
#
# Note on interactivity: everything above runs with stdout redirected into a
# tee (see the LOGGING section), which makes stdout a pipe. gh treats a piped
# stdout as non-interactive and refuses to prompt. github-setup.sh handles that
# by binding its interactive I/O to /dev/tty, which also keeps the OAuth
# exchange out of the log file on disk. Do not "simplify" that away.
section "Post-Install: GitHub CLI"

if $SKIP_GITHUB; then
    warn "Skipping GitHub CLI setup (--skip-github)"
else
    MAC_SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    GITHUB_SETUP="$MAC_SETUP_DIR/../../Utilities/github-setup.sh"
    # Post-Mac-Setup lives at <hub>/Utilities/Post-Mac-Setup, so the sibling
    # script is one level up. Check that spelling first, then the flatter one
    # in case this folder is ever relocated.
    [ -f "$GITHUB_SETUP" ] || GITHUB_SETUP="$MAC_SETUP_DIR/../github-setup.sh"

    if [ ! -f "$GITHUB_SETUP" ]; then
        info "github-setup.sh not found next to this script - skipping GitHub auth"
        info "  (expected when running the standalone copy, outside the hub)"
        (( SKIPPED_COUNT++ )) || true
    elif $DRY_RUN; then
        info "[DRY RUN] Would run: $GITHUB_SETUP --dry-run"
        bash "$GITHUB_SETUP" --dry-run || true
    else
        if bash "$GITHUB_SETUP"; then
            success "GitHub CLI authenticated and git credential helper configured"
        else
            # github-setup.sh exits non-zero while anything still needs a
            # human. That is a reportable outcome, not a reason to abort the
            # rest of the machine setup.
            warn "GitHub setup left something for you - see the items listed above"
            FAILED_ITEMS+=("GitHub CLI auth (see github-setup output)")
        fi
    fi
fi

# ─────────────────────────────────────────────────────────────────────
# POST-INSTALL: RUST
# ─────────────────────────────────────────────────────────────────────
section "Post-Install: Rust Toolchain"

# The Homebrew rustup formula NO LONGER SHIPS rustup-init - `brew info rustup`
# says so in as many words. This block looked for it at
# $BREW_PREFIX/opt/rustup/bin/rustup-init until 2026-08-29, never found it, and
# warned and skipped on every single run. That warning was the only symptom of
# a toolchain that was never being set up by this script at all.
#
# The modern formula ships `rustup` itself, keg-only. Presence of a default
# toolchain is the right question, and `rustup default` answers it directly:
# it prints the active toolchain, or fails when none is set.
RUSTUP_BIN="$BREW_PREFIX/opt/rustup/bin/rustup"
if [ -x "$RUSTUP_BIN" ]; then
    if "$RUSTUP_BIN" default >/dev/null 2>&1; then
        success "Rust toolchain already initialized ($("$RUSTUP_BIN" default 2>/dev/null))"
        (( SKIPPED_COUNT++ )) || true
    elif $DRY_RUN; then
        info "[DRY RUN] Would run rustup default stable"
    else
        info "Installing the stable Rust toolchain via rustup..."
        if "$RUSTUP_BIN" default stable; then
            success "Rust toolchain installed"
            (( INSTALLED_COUNT++ )) || true
        else
            warn "rustup could not install the stable toolchain"
            FAILED_ITEMS+=("rust toolchain (rustup)")
        fi
    fi
else
    warn "rustup not found at $RUSTUP_BIN - skipping Rust setup"
    FAILED_ITEMS+=("rust toolchain (rustup missing)")
fi

# ─────────────────────────────────────────────────────────────────────
# POST-INSTALL: FZF KEY BINDINGS & COMPLETION
# ─────────────────────────────────────────────────────────────────────
section "Post-Install: fzf Key Bindings"

FZF_INSTALL="$BREW_PREFIX/opt/fzf/install"
if [ -f "$FZF_INSTALL" ]; then
    if $DRY_RUN; then
        info "[DRY RUN] Would run $FZF_INSTALL --all --no-bash --no-fish --key-bindings --completion --update-rc"
    else
        info "Installing fzf key bindings and fuzzy completion..."
        "$FZF_INSTALL" --all --no-bash --no-fish --key-bindings --completion --update-rc
        success "fzf key bindings installed"
    fi
else
    warn "fzf install script not found - skipping"
fi

# ─────────────────────────────────────────────────────────────────────
# POST-INSTALL: MacTeX PATH
# ─────────────────────────────────────────────────────────────────────
section "Post-Install: MacTeX PATH"

# The MacTeX PATH is wired into ~/.zsh_paths below, so future shells pick it up
# automatically. Nothing to do for the current process - this section just
# verifies the install completed.
if [ -d "/Library/TeX/texbin" ]; then
    success "MacTeX detected at /Library/TeX/texbin (PATH configured via ~/.zsh_paths)"
else
    warn "MacTeX texbin not found - it may still be installing in the background"
fi

# ─────────────────────────────────────────────────────────────────────
# POST-INSTALL: OH MY ZSH
# ─────────────────────────────────────────────────────────────────────
section "Post-Install: Oh My Zsh"

if [ ! -d "$HOME/.oh-my-zsh" ]; then
    if $DRY_RUN; then
        info "[DRY RUN] Would install Oh My Zsh (unattended)"
    else
        info "Installing Oh My Zsh (unattended)..."
        RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        success "Oh My Zsh installed"
    fi
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
    if $DRY_RUN; then
        info "[DRY RUN] Would git clone Powerlevel10k -> $P10K_DIR"
    else
        info "Cloning Powerlevel10k..."
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
        success "Powerlevel10k installed"
    fi
else
    success "Powerlevel10k already installed"
fi

# ─────────────────────────────────────────────────────────────────────
# POST-INSTALL: ZSH PLUGINS
# ─────────────────────────────────────────────────────────────────────
section "Post-Install: Zsh Plugins"

# Each entry: "plugin-name git-url"
ZSH_PLUGINS=(
    "zsh-autosuggestions     https://github.com/zsh-users/zsh-autosuggestions.git"
    "zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting.git"
    "zsh-completions         https://github.com/zsh-users/zsh-completions.git"
)
for entry in "${ZSH_PLUGINS[@]}"; do
    read -r plugin_name plugin_url <<<"$entry"
    plugin_dir="$ZSH_CUSTOM/plugins/$plugin_name"
    if [ -d "$plugin_dir" ]; then
        success "$plugin_name already installed"
    elif $DRY_RUN; then
        info "[DRY RUN] Would git clone $plugin_url -> $plugin_dir"
    else
        info "Cloning $plugin_name..."
        if git clone --depth=1 "$plugin_url" "$plugin_dir"; then
            success "$plugin_name installed"
        else
            warn "Failed to clone $plugin_name"
            FAILED_ITEMS+=("$plugin_name")
        fi
    fi
done

# ─────────────────────────────────────────────────────────────────────
# UPDATE SHELL CONFIG FILES
# Preserves existing content in all files using marker-based injection.
# Structure:
#   ~/.zsh_paths   - PATH exports, env variables
#   ~/.zsh_aliases - aliases and shell shortcuts
#   ~/.zshrc       - sources both + Oh My Zsh + plugins
# ─────────────────────────────────────────────────────────────────────
section "Updating Shell Config Files (preserving your existing config)"

ZSHRC="$HOME/.zshrc"
ZSH_PATHS="$HOME/.zsh_paths"
ZSH_ALIASES="$HOME/.zsh_aliases"
ZSHENV="$HOME/.zshenv"
ZPROFILE="$HOME/.zprofile"

if $DRY_RUN; then
    info "[DRY RUN] Would back up and inject managed blocks into:"
    echo "    $ZSH_PATHS, $ZSH_ALIASES, $ZSHRC, $ZSHENV, $ZPROFILE"
else

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# Back up any existing files
for f in "$ZSHRC" "$ZSH_PATHS" "$ZSH_ALIASES" "$ZSHENV" "$ZPROFILE"; do
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
    local begin_marker="### BEGIN $block_id (managed by mac-setup.sh - do not edit)"
    local end_marker="### END $block_id"

    if grep -qF "$begin_marker" "$target_file" 2>/dev/null; then
        # Block exists - replace its content.
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
        # Block doesn't exist - append it
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
    local begin_marker="### BEGIN $block_id (managed by mac-setup.sh - do not edit)"
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
#  FILE 1: ~/.zsh_paths - PATH exports and environment variables
# ═════════════════════════════════════════════════════════════════════
info "Configuring ~/.zsh_paths ..."

inject_block "$ZSH_PATHS" "HOMEBREW-ENV" \
'# Keep PATH free of duplicates. zsh ties the path array to PATH, and
# typeset -U makes it unique-on-assignment, keeping the FIRST occurrence.
# That ordering is what makes it safe here: the prepends further down
# deliberately put Homebrew, coreutils and TeX ahead of the system copies,
# while brew shellenv (also run from ~/.zprofile) and the macOS path_helper
# each add some of them again lower down. Without this, /opt/homebrew/bin,
# /opt/homebrew/sbin and /Library/TeX/texbin each appeared twice in every
# interactive shell. Deduping keeps the intended winner and drops the echo.
# NOTE: keep this comment free of apostrophes - the whole block is a
# single-quoted bash string and one apostrophe ends it.
typeset -U path PATH

# Homebrew shell environment (Apple Silicon vs Intel).
#
# Guarded on HOMEBREW_PREFIX, which brew shellenv exports itself, so the whole
# block is skipped on the second and third sourcing of this file. That matters
# because the file is now loaded three times for a login shell - from ~/.zshenv,
# then ~/.zprofile, then ~/.zshrc - and brew shellenv costs about 8ms with brew
# --prefix another 6ms. The guard also lets HOMEBREW_PREFIX stand in for that
# separate prefix call, removing it entirely. Re-sourcing still restores PATH
# ordering, because the prepends below need only BREW_PREFIX, not a fresh
# shellenv run.
if [[ -z "$HOMEBREW_PREFIX" ]]; then
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi
BREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"

# Safety net: guarantee the system directories are on PATH.
#
# brew shellenv does not prepend any more - it re-runs path_helper with
# PATH_HELPER_ROOT set to the Homebrew prefix, and path_helper REBUILDS PATH
# rather than extending it. It recovers the previous entries from the PATH it
# inherits, so in a shell started with no PATH in its environment at all
# (env -i, some daemons and CI runners) the subprocess sees nothing to recover,
# the rebuild drops /usr/bin and /bin, and even grep stops resolving. This did
# not surface while the file was sourced only from ~/.zshrc, because an
# interactive shell always had a populated PATH by then; sourcing it from
# ~/.zshenv exposed it. Appending costs nothing in the normal case, since
# typeset -U keeps the first occurrence and drops these as duplicates.
path+=(/usr/bin /bin /usr/sbin /sbin)'

inject_block "$ZSH_PATHS" "PATH-OVERRIDES" \
'# Prefer Homebrew binaries over system defaults (git, python, coreutils, curl)
export PATH="$BREW_PREFIX/bin:$BREW_PREFIX/sbin:$PATH"

# GNU coreutils (use ls instead of gls, etc.)
export PATH="$BREW_PREFIX/opt/coreutils/libexec/gnubin:$PATH"
export MANPATH="$BREW_PREFIX/opt/coreutils/libexec/gnuman:${MANPATH:-}"

# curl (keg-only: Homebrew will not symlink it into bin, because macOS ships
# its own. Without this line the "prefer Homebrew" comment above is false for
# curl and /usr/bin/curl keeps winning.)
#
# Trade-off: the Homebrew build links OpenSSL and reads its own CA bundle,
# not the macOS Keychain. A root installed the normal macOS way (an internal
# corporate CA, a TLS-inspecting proxy) is trusted by /usr/bin/curl and NOT
# by this one, which fails with "SSL certificate problem: unable to get local
# issuer certificate". Pass --ca-native to fall back to the Keychain, or drop
# this line if that ever bites.
# NOTE: keep this comment free of apostrophes - the whole block is a
# single-quoted bash string and one apostrophe ends it.
export PATH="$BREW_PREFIX/opt/curl/bin:$PATH"

# LLVM (clang, clang++, clang-tidy, lldb, and the llvm-* tools). Note that
# lld is NOT in this keg despite the formula name - it ships separately now,
# so run brew install lld if a build wants the LLVM linker.
#
# This deliberately makes Homebrew clang win over /usr/bin/clang, shadowing
# exactly five names: clang, clang++, clangd, dsymutil, lldb. Know the cost
# before relying on it. Homebrew clang++ defaults to gnu++17 where Apple
# clang++ defaults to gnu++14, so five ordinary pre-C++17 constructs build
# under /usr/bin/clang++ and fail here: register, dynamic exception specs,
# std::random_shuffle, auto_ptr, unary_function. Pin -std=gnu++14 when that
# bites. It masks in reverse too, since C++17 code builds here and then fails
# on a stock Mac.
#
# Note the asymmetry with gcc, which is intended and not an oversight: the gcc
# formula IS installed (see FORMULAE above) but is NOT put ahead of the system.
# The reason is NOT a macOS-specific Homebrew policy, which is the tempting
# wrong explanation - the formula configures with --program-suffix=-16
# (gcc.rb:81, in the shared args array outside the OS.mac? branch, so Linux
# gets the same names). The unversioned drivers are never built, so there is
# nothing to link. A bare gcc therefore stays the Apple clang driver, which is
# what Python C extensions, node-gyp and anything touching ObjC or the Apple
# frameworks assume. Exactly one driver is unversioned: gfortran, so plain
# gfortran already IS GCC 16. For GNU C or C++, name it - gcc-16, g++-16 - or
# set CC and CXX per project.
# NOTE: keep this comment free of apostrophes - the whole block is a
# single-quoted bash string and one apostrophe ends it.
export PATH="$BREW_PREFIX/opt/llvm/bin:$PATH"

# Flags for building against Homebrew LLVM, under LLVM_-prefixed names.
#
# These were once exported as bare LDFLAGS and CPPFLAGS, which meant every
# autotools configure, make implicit rule, setuptools C-extension build and
# node-gyp run in every login shell inherited the LLVM header and library
# search paths whether or not it wanted them. brew info llvm documents these
# as flags you opt into per build, and warns that llvm is keg-only precisely
# because a parallel toolchain causes trouble. The bare names were also a
# clobbering assignment, so nothing else could add to them.
#
# Opt in when you actually are building against LLVM:
#   LDFLAGS="$LLVM_LDFLAGS" CPPFLAGS="$LLVM_CPPFLAGS" ./configure
export LLVM_LDFLAGS="-L$BREW_PREFIX/opt/llvm/lib"
export LLVM_CPPFLAGS="-I$BREW_PREFIX/opt/llvm/include"

# Rust. Two directories, and both are needed.
#
# rustup is keg-only and its shims - rustc, cargo, rustfmt, clippy - live in
# the keg, which brew info rustup tells you to put on PATH. Until 2026-08-29
# only ~/.cargo/bin was added here, and on this machine that directory did not
# even exist, so rustc and cargo were absent from PATH entirely while rustup
# and a working stable toolchain were installed the whole time.
#
# ~/.cargo/bin stays as well, but for the other thing: it is where `cargo
# install <tool>` puts binaries, which the keg knows nothing about.
export PATH="$BREW_PREFIX/opt/rustup/bin:$PATH"
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
#  FILE 2: ~/.zsh_aliases - aliases and shell shortcuts
# ═════════════════════════════════════════════════════════════════════
info "Configuring ~/.zsh_aliases ..."

inject_block "$ZSH_ALIASES" "EZA-ALIASES" \
'# eza - modern ls replacement with icons and git status
if command -v eza &>/dev/null; then
  alias ls='\''eza --icons --color=always --group-directories-first'\''
  alias ll='\''eza -l --icons --color=always --group-directories-first --git --time-style=long-iso'\''
  alias la='\''eza -la --icons --color=always --group-directories-first --git --time-style=long-iso'\''
  alias lt='\''eza -l --sort=modified --icons --color=always --group-directories-first --git --time-style=long-iso'\''
  alias tree='\''eza --tree --icons --color=always --group-directories-first'\''
fi'

inject_block "$ZSH_ALIASES" "BAT-ALIASES" \
'# bat - cat with syntax highlighting
if command -v bat &>/dev/null; then
  alias cat='\''bat --paging=never'\''
  alias catp='\''bat'\''
fi'

inject_block "$ZSH_ALIASES" "FD-ALIASES" \
'# fd - fast find replacement
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
#  FILE 3: ~/.zshrc - main shell config (sources paths & aliases)
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
'# zoxide - smarter cd command (use "z" to jump, "zi" for interactive)
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

# ═════════════════════════════════════════════════════════════════════
#  FILES 4 & 5: ~/.zshenv and ~/.zprofile - make PATH apply to ALL shells
# ═════════════════════════════════════════════════════════════════════
# ~/.zshrc alone covers INTERACTIVE zsh only, so scripts, `zsh -c`, cron jobs
# and `ssh <host> <cmd>` used to get the system PATH while the terminal got
# the Homebrew one - same command, different compiler and different coreutils.
# Fixing that takes both files below, for two different reasons.
info "Configuring ~/.zshenv and ~/.zprofile ..."

inject_block "$ZSHENV" "SOURCE-PATHS" \
'# Load PATH exports and environment variables.
#
# zsh reads this file for EVERY shell - interactive or not, login or not - so
# this is what makes scripts, zsh -c, cron and ssh <host> <cmd> see the same
# PATH the terminal does. It is deliberately not the only place: for a LOGIN
# shell the macOS path_helper runs afterwards out of /etc/zprofile and rebuilds
# PATH with the system directories near the front, undoing these prepends. That
# is what the matching block in ~/.zprofile repairs.
# NOTE: this file is also read by scp and sftp sessions, so nothing here may
# ever write to stdout - any output corrupts those transfers.
[[ -f ~/.zsh_paths ]] && source ~/.zsh_paths'

inject_block "$ZPROFILE" "SOURCE-PATHS" \
'# Re-load PATH exports AFTER the macOS path_helper has run.
#
# /etc/zprofile runs /usr/libexec/path_helper for every login shell, which
# rebuilds PATH from /etc/paths and /etc/paths.d and puts /usr/bin near the
# front - undoing the prepends ~/.zshenv just made. zsh reads /etc/zprofile
# before ~/.zprofile, so re-sourcing here is what puts Homebrew LLVM, coreutils,
# curl and TeX back ahead of the system copies. Without it a non-interactive
# login shell (zsh -lc, ssh <host> <cmd>) silently gets the system clang and
# system coreutils while the terminal gets Homebrew.
#
# Re-sourcing is safe and cheap: typeset -U in the sourced file makes repeat
# prepends idempotent, and its Homebrew block is guarded on HOMEBREW_PREFIX so
# brew shellenv does not run a second time.
[[ -f ~/.zsh_paths ]] && source ~/.zsh_paths'

success "~/.zshenv and ~/.zprofile configured (PATH now applies to non-interactive shells)"

success "~/.zshrc configured (sources ~/.zsh_paths and ~/.zsh_aliases)"
info "File structure:"
echo "    ~/.zsh_paths   - PATH exports, env variables (edit paths here)"
echo "    ~/.zsh_aliases - aliases and shortcuts (edit aliases here)"
echo "    ~/.zshrc       - sources both + Oh My Zsh + plugins (interactive only)"
echo "    ~/.zshenv      - sources ~/.zsh_paths for EVERY shell (scripts, zsh -c, cron)"
echo "    ~/.zprofile    - re-sources it after the macOS path_helper reorders PATH"

fi  # end DRY_RUN guard around dotfile writes

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

# Mark the script as having reached its natural end. The EXIT trap
# (registered near the top) prints the final summary + manual steps
# whether we get here normally or exit early via Ctrl-C / error.
SCRIPT_COMPLETED=true