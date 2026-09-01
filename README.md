# Post-Mac-Setup

A single, idempotent Bash script that takes a Mac from a fresh install to a working development environment: Homebrew, 46 command-line tools, 26 GUI apps, a configured zsh, and a handful of macOS defaults. It is one file with no dependencies, and rerunning it is safe.

The script is deliberately self-contained. Everything it needs to bootstrap a machine that has nothing on it — no Homebrew, no Xcode Command Line Tools, no `git` identity — is in `mac-setup.sh` itself.

## Quick Start on a Brand-New Mac

The only thing you need is a network connection and `curl`, which ships with macOS. You do not need Homebrew, Xcode, `git`, or `gh` first; the script installs what it needs in the order that works.

```bash
# 1. Download the script.
curl -fsSLO https://raw.githubusercontent.com/anirbanchakraborty-dev/Post-Mac-Setup/main/mac-setup.sh

# 2. Read it before you run it (see below for why).
less mac-setup.sh

# 3. Run it.
chmod +x mac-setup.sh && ./mac-setup.sh
```

If you would rather have the whole repository:

```bash
curl -fsSL https://github.com/anirbanchakraborty-dev/Post-Mac-Setup/archive/refs/heads/main.tar.gz | tar -xz
cd Post-Mac-Setup-main && bash mac-setup.sh
```

**Why two steps instead of `curl … | bash`.** The one-liner is shorter and this script is a bad candidate for it. It runs `sudo`, installs system packages, changes your login shell with `chsh`, and rewrites five files in your home directory. All of that is reasonable for a setup script and none of it is something you should agree to sight unseen. Downloading first also means the copy that gets reviewed is the copy that runs, which is not true of a pipe.

### What the script handles for you

Three things that usually appear as separate manual steps in a new-Mac guide are not steps here.

**Xcode Command Line Tools.** Homebrew and many formulae need them. The script checks `xcode-select -p`, and if the toolchain is absent it runs `xcode-select --install`, which returns immediately and pops a GUI installer. It then polls every five seconds until the toolchain is actually present, rather than asking you to press a key when the window closes. You do not run `xcode-select --install` yourself.

**Homebrew.** If `brew` is not on `PATH`, the script runs the official Homebrew installer, works out whether the prefix is `/opt/homebrew` (Apple Silicon) or `/usr/local` (Intel), activates it for the current session, and appends the `brew shellenv` line to `~/.zprofile` so new terminals find it too.

**Your git identity.** A fresh Mac has no `user.name` or `user.email`, and every commit fails until it does. The script prompts for both and sets them globally. If they are already set it shows you what they are and asks whether to change them, so a rerun does not clobber them. It also sets `init.defaultBranch=main`, `pull.rebase=false`, and `core.autocrlf=input`, but only where you have not already chosen something else.

### The one thing it does not finish: GitHub authentication

`gh` is in the formula list, so the GitHub CLI is installed on your machine by the end of the run. Being authenticated is a separate matter, and on this repository's path it stays a manual follow-up.

The reason is structural. The script does not reimplement GitHub login; it delegates that work to a companion script so that several entry points can share one implementation. That companion script is not part of this repository. When it is absent — which is always, if you got here by cloning or downloading this repo — the step detects that, reports itself skipped in the run output, counts itself as skipped in the summary, and moves on. It is not an error and it does not stop the run.

So after the script finishes, log in yourself:

```bash
gh auth login       # opens a browser
gh auth setup-git   # registers gh as git's credential helper
```

Run both. `gh auth login` authenticates the CLI, and nothing more. Until `gh auth setup-git` has run, `git` itself has no credential helper, so the machine looks fully signed in and still cannot clone a private repository over HTTPS or push to one — and the error it gives you when you try does not mention the real cause. Pass `--skip-github` if you want to skip the step deliberately rather than have it skip itself.

### What it will ask you

The run is mostly unattended but not entirely. Expect a confirmation prompt before any changes are made, your password once for `sudo` (cached up front, with a background keep-alive so a long download does not outlast it), a password prompt from `chsh` when it sets Homebrew zsh as your login shell, and the two git identity questions described above. Set aside real time: MacTeX alone is roughly a 5 GB download.

A note on `--dry-run` for this case specifically. It is genuinely useful on a machine that already has Homebrew, where the whole detection path runs and reports what it found. On a bare Mac it cannot get far: with no `brew` present it notes that it would install Homebrew, warns that it cannot continue a dry run without it, and exits. That is honest rather than broken — almost every later decision depends on querying Homebrew.

## Rerunning It

Rerunning is the normal case, not a recovery path. Already-installed packages are detected before `brew` is invoked at all and counted as skipped. Shell config is updated in place through marker-bounded blocks, so your own additions survive. Existing dotfiles are backed up with a timestamp before any modification. `brew upgrade` is **not** run unless you pass `--upgrade`, so a rerun to pick up one new package will not quietly move fifty others.

Two detection details are worth knowing because they are where naive "is it installed?" checks go wrong.

**GUI apps are verified on disk, not just in Homebrew's records.** `brew list --cask` reports what Homebrew believes. Drag an app to the Trash instead of running `brew uninstall --cask` and the Caskroom entry survives, so Homebrew keeps listing an app that is gone. For casks that ship an `.app`, the script resolves the artifact names and confirms the bundle exists in `/Applications` or `~/Applications` before believing the record, and repairs a missing one with `brew reinstall --cask` (a plain install refuses a cask Homebrew still thinks it has). Casks with no app artifact — CLI tools, fonts, `.pkg`-based installs — have nothing to check and are left alone. `--dry-run` performs the same check and tells you what it would repair.

**Aliases and versioned names are resolved before anything is called missing.** `brew list --formula` prints the resolved name, such as `python@3.14`, while the package list declares the stable alias `python@3`. An exact-match check never finds it and reports a reinstall of something already present on every single run. The script settles it with one `brew info --json=v2` query over the apparent misses, keyed off the authoritative `.installed` field.

## What Gets Installed

### CLI tools (46 formulae)

| Category | Packages |
|---|---|
| Shells | `bash`, `zsh` (updated, replacing the macOS system copies) |
| Version control | `git`, `git-lfs`, `gh`, `git-filter-repo` |
| Languages and runtimes | `python@3`, `node`, `pnpm`, `r`, `gcc`, `go`, `rustup` |
| Python tooling | `uv` |
| EDA / hardware design | `icarus-verilog`, `yosys`, `sby`, `verilator`, `verible`, `surfer`, `graphviz` |
| RISC-V toolchain | `riscv64-elf-gcc`, `dtc` |
| Terminal utilities | `tree`, `fzf`, `jq`, `eza`, `zoxide`, `ripgrep`, `coreutils`, `wget`, `curl`, `bat`, `fd`, `htop`, `tlrc`, `dust`, `bottom`, `hyperfine`, `difftastic` |
| Build tools | `cmake`, `llvm`, `pandoc`, `plantuml`, `poppler` |
| Homebrew TUI | `bbrew` |

`sby` is the SymbiYosys formal-verification front end for Yosys, `surfer` is a waveform viewer, and `tlrc` provides the `tldr` command (the `tldr` formula itself was disabled upstream on 2025-10-24). `poppler` is there for `pdftotext` and friends. Note that `gcc` is installed but is deliberately not put ahead of the system compiler; see the shell section below.

### GUI apps and fonts (26 casks)

| Category | Casks |
|---|---|
| Editors and IDEs | `visual-studio-code`, `coteditor` |
| AI | `claude`, `claude-code`, `lm-studio` |
| Productivity | `microsoft-office`, `setapp`, `obsidian` |
| LaTeX | `mactex`, `texifier`, `skim` |
| Research and graphics | `zotero`, `inkscape` |
| Photography | `nx-studio` |
| Media and audio | `iina` |
| Terminal | `iterm2` |
| Networking and security | `tailscale-app` |
| Browser and messaging | `whatsapp` |
| Window management | `loop` |
| Menu bar | `blip`, `stats`, `thaw` |
| System maintenance | `pearcleaner`, `purge` |
| Fonts | `font-meslo-lg-nerd-font`, `font-jetbrains-mono-nerd-font` |

`mactex` is the full TeX Live distribution and is by far the largest item in the run. `nx-studio` installs from a `.pkg` and leaves no `.app` artifact, so it is exempt from the on-disk verification above. The two Nerd Fonts are patched fonts, needed for the Powerlevel10k prompt's icons to render.

### Taps

Two third-party taps, each carrying exactly one package that is not in `homebrew/core` or `homebrew/cask`:

| Tap | Provides |
|---|---|
| `chipsalliance/verible` | `verible` |
| `jithin-sabu/tap` | `purge` |

Each tap is **trusted** with `brew trust --tap` immediately after it is added. Recent Homebrew sets `$HOMEBREW_REQUIRE_TAP_TRUST` by default and refuses to load formulae from untrusted third-party taps: it prints a skip notice and leaves the package uninstalled, so without this the two packages above silently never arrive and `brew upgrade` ignores them too. Trust is granted at tap level rather than per formula, because the same setting also gates the commands that evaluate every formula and cask, which is what the `brew bundle dump` in the cleanup step does. The step is guarded on `brew trust` existing at all, since older Homebrew lacks the subcommand and does not enforce trust either way. Afterwards each tapped package is resolved with `brew info` as a verification pass, so a typo in a tap name or a tap that failed to clone surfaces as a reported failure instead of a package that quietly never installs.

### Outside Homebrew

Two globals are installed through other package managers: a schematic renderer for Yosys JSON netlists via `npm install -g`, and a knowledge-graph builder CLI via `uv tool install`. Both are skipped when already present, and both degrade gracefully — if `npm` or `uv` is missing, the step warns, records the item in the failure summary, and continues.

One application is installed straight from the publisher's `.pkg` rather than through a cask: **Microsoft Edge**, gated behind `--skip-extras`. That deserves an explanation, because the obvious approach is wrong on Apple Silicon. Microsoft's `fwlink/?linkid=2069148` redirector advertises itself as the canonical "latest" Edge package and serves an x86_64-only build, so a Mac that installs from it ends up running Edge under Rosetta with nothing to indicate anything went wrong. The script therefore takes both the version string and the download URL from Microsoft's EdgeUpdates JSON API (`https://edgeupdates.microsoft.com/api/products`, the Stable / MacOS / universal artifact), so the two cannot disagree. On an `arm64` host, if that API is unreachable or cannot name a universal build, Edge is **skipped and reported** rather than installed from the fallback: a browser missing until the next run is a smaller problem than a browser silently emulated. Intel hosts have no such hazard, so the redirector stays a fine fallback there. The installed bundle is described as `<version> (<arch>)` so a single comparison catches both a stale version and a wrong-architecture build, and the architecture is read with `lipo -archs` rather than `file` — `file`'s output for a universal binary spans three lines, one of which ends in the exact string `Mach-O 64-bit executable x86_64` and would make a correct universal build look Intel-only, forcing a pointless reinstall on every run. After installing, the bundle is re-read and a non-native result is recorded as a failure.

### A note on batching

Formulae and casks are each installed in a single batched `brew install` call rather than one call per package, which is several times faster, with a per-package fallback if the batch fails. One consequence needed handling: `brew install` refuses the *entire* batch when any single argument is a formula Homebrew has disabled upstream, which turns one fast call into forty-odd sequential ones. So before the batch is built, one `brew info --json=v2` query over the install list drops anything marked disabled and names the casualty in the summary. That query needs `jq`, which is itself installed by the formulae step, so on a first run against a bare machine the prune is a no-op and the per-package fallback is the safety net.

## CLI Flags

```text
--help, -h        Show usage
--dry-run         Show what would be installed (no changes)
--upgrade         Also run 'brew upgrade' (off by default)
--skip-casks      Skip GUI app (cask) installation
--skip-formulae   Skip CLI tool (formula) installation
--skip-extras     Skip direct downloads (Edge, etc.)
--skip-github     Skip GitHub CLI auth + git credential setup
--skip-macos      Skip macOS .DS_Store defaults
--skip-shell      Skip shell config (.zshrc, etc.)
--no-log          Don't save output to a log file
```

```bash
# See what would happen, on a machine that already has Homebrew
./mac-setup.sh --dry-run

# CLI tools only, no GUI apps
./mac-setup.sh --skip-casks

# Packages only: leave the shell and macOS settings alone
./mac-setup.sh --skip-shell --skip-macos

# Rerun and also upgrade what is already installed
./mac-setup.sh --upgrade
```

`--dry-run` is not a partial simulation. The entire detection path — `brew list`, `brew info`, checking for app bundles on disk — is read-only, so a dry run actually executes it and reports what it genuinely found, including a GUI app whose bundle has gone missing. An early return that reported "would install" for everything, including packages already present, would make the dry run unable to surface exactly the problem the check exists to catch.

The script insists on running under a real bash, and re-execs itself if it was not. `sh mac-setup.sh` therefore works, but only because of that guard: on macOS `/bin/sh` *is* bash, in POSIX mode, where the process substitution used for logging is disabled. Testing `BASH_VERSION` is not enough to tell the two apart, since `/bin/sh` sets it; the discriminator is whether `set -o posix` reports `on`.

## What It Configures in Your Shell

Skippable in full with `--skip-shell`. Every managed block is wrapped in `### BEGIN <ID>` / `### END <ID>` markers, and anything you write outside those markers is preserved across reruns. Existing files are backed up with a timestamp first.

**Five files, and the split is deliberate.**

```text
~/.zsh_paths     PATH exports and environment variables (edit paths here)
~/.zsh_aliases   aliases and shortcuts (edit aliases here)
~/.zshrc         sources both, plus Oh My Zsh and plugins (interactive shells)
~/.zshenv        sources ~/.zsh_paths for EVERY shell (scripts, zsh -c, cron)
~/.zprofile      re-sources it after the macOS path_helper reorders PATH
```

`~/.zshrc` alone covers interactive shells only, which means a script, `zsh -c`, a cron job, and `ssh host cmd` all get the system `PATH` while your terminal gets the Homebrew one — the same command resolving to a different compiler depending on how it was started. Sourcing from `~/.zshenv` fixes that for every shell. The third copy in `~/.zprofile` is not redundancy: `/etc/zprofile` runs `/usr/libexec/path_helper` for every *login* shell, which rebuilds `PATH` with the system directories near the front and undoes what `~/.zshenv` just did, and zsh reads `/etc/zprofile` before `~/.zprofile`. Re-sourcing is cheap and idempotent because the file declares `typeset -U path PATH` and guards its Homebrew block on `HOMEBREW_PREFIX`.

**PATH policy.** Homebrew `bin` and `sbin` go ahead of the system directories, along with GNU coreutils (so `ls` is GNU `ls`, not `gls`), Homebrew `curl` (keg-only, so without an explicit entry `/usr/bin/curl` keeps winning), Homebrew LLVM, the `rustup` keg plus `~/.cargo/bin`, `$GOPATH/bin`, and `/Library/TeX/texbin` when MacTeX is present.

Two consequences of that are worth knowing before they surprise you. First, `clang` and `clang++` resolve to Homebrew LLVM, which defaults to `gnu++17` where Apple's `clang++` defaults to `gnu++14`; a handful of ordinary pre-C++17 constructs compile with `/usr/bin/clang++` and fail here, so pin `-std=gnu++14` when that bites. It masks in the other direction too — C++17 code that builds on this machine can fail on a stock Mac. Second, `gcc` is installed but is deliberately *not* put ahead of the system compiler, and that asymmetry is intentional. The Homebrew formula builds its drivers with a version suffix, so there is no unversioned `gcc` to link in the first place; a bare `gcc` stays the Apple clang driver at `/usr/bin/gcc`, which is what Python C extensions, `node-gyp`, and anything touching the Apple frameworks assume. Use `gcc-16` and `g++-16`, or set `CC` and `CXX` per project, and do not "fix" this by symlinking `gcc` into the Homebrew prefix — brew clobbers it on the next upgrade and the breakage shows up in unrelated builds whose errors never mention the symlink. Exactly one driver is unversioned, `gfortran`, so plain `gfortran` already is Homebrew GCC.

LLVM's build flags are exported as `LLVM_LDFLAGS` and `LLVM_CPPFLAGS`, not as bare `LDFLAGS` and `CPPFLAGS`. Under the bare names every `configure` run, make implicit rule, setuptools C-extension build, and `node-gyp` invocation in every login shell would inherit LLVM's header and library search paths whether it wanted them or not. Opt in at the point of use: `LDFLAGS="$LLVM_LDFLAGS" CPPFLAGS="$LLVM_CPPFLAGS" ./configure`.

**Prompt and plugins.** Oh My Zsh is installed unattended (keeping your existing `.zshrc`), with the Powerlevel10k theme and the `git`, `zsh-autosuggestions`, `zsh-syntax-highlighting`, `zsh-completions`, and `fzf` plugins. `fzf`'s key bindings and fuzzy completion are installed, with `ripgrep` as its default file finder. `zoxide` is initialised, giving you `z` and `zi`.

**Aliases.** `eza` replaces `ls` (plus `ll`, `la`, `lt`, and `tree`), `bat` replaces `cat`, `fd` replaces `find`, `dust` replaces `du`, `bottom`'s `btm` replaces `top`, and `difftastic`'s `difft` replaces `diff`. There are also directory hops (`..`, `...`, `....`), `mkdir -p` by default, `df -h`, `ports` for listening sockets, `myip`, `reload`, and short git commands (`gs`, `gd`, `gds`, `glog`).

**Login shell and Git LFS.** Homebrew's `bash` and `zsh` are added to `/etc/shells`, Homebrew `zsh` is set as your login shell with `chsh`, and `git lfs install` is run.

**macOS defaults.** One setting, skippable with `--skip-macos`: `.DS_Store` files are prevented on network and USB volumes.

## Logs and Output

Unless you pass `--no-log`, everything the script prints is tee'd to a timestamped file under `~/Library/Logs/mac-setup/`. That location is used rather than `/tmp` so logs survive both a reboot and the periodic temp purge.

A summary prints on **every** exit path, including a mid-script failure and Ctrl-C, because it is registered as an `EXIT` trap: newly installed, already present, failures, and elapsed time, with each individual failure named. Individual failures are collected rather than fatal, so one unavailable package does not abandon the rest of the machine. The manual-steps list and the closing message print only when the script reached its natural end, so an aborted run is never mistaken for a complete one.

The cleanup step runs `brew cleanup` and exports a `Brewfile` snapshot of everything installed, written next to the script.

## After the Run

The script prints these itself when it finishes:

1. Restart your terminal, or run `exec zsh`.
2. Run `p10k configure` to set up the prompt, choosing MesloLGS NF or JetBrainsMono NF as the terminal font.
3. Set the iTerm2 font: Preferences → Profiles → Text → Font → MesloLGS Nerd Font.
4. Confirm the Homebrew versions are winning: `which git`, `which python3`, `which zsh`, `which bash` should all point inside the Homebrew prefix.
5. Sign in to the apps that need accounts.

And, on this repository's path, the GitHub step from the quick start above: `gh auth login` followed by `gh auth setup-git`.

## File Structure

```text
Post-Mac-Setup/
  mac-setup.sh   the setup script (single file, self-contained)
  README.md      this file
  CLAUDE.md      context for AI coding assistants
  LICENSE        MIT
  Brewfile       generated by the run: a snapshot of installed packages
```

Package lists are plain Bash arrays named `TAPS`, `FORMULAE`, and `CASKS`. Adding or removing a package means editing an array, and nothing else.

## License and Forking

MIT. This is one person's setup rather than a general-purpose provisioning tool, and the package lists reflect that: they lean heavily toward hardware design, LaTeX, and writing. You are welcome to fork it and cut the arrays down to what you actually use, which is the intended way to adopt it. The machinery around the lists — the idempotent detection, the on-disk cask verification, the batching and the disabled-package prune, the marker-based dotfile injection — is the part worth keeping, and it does not care what is in the arrays.
