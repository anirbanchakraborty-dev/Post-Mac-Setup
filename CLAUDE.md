# Post-Mac-Setup

Idempotent, single-file Bash script (`mac-setup.sh`) that bootstraps a full macOS
development environment from a clean install. Everything lives in that one file:
the package lists are plain Bash arrays near the middle, the helpers are near the
top, and the shell-config blocks are single-quoted heredoc-style strings near the
bottom. There is no config file to read and no library to import.

Two properties matter more than any feature, and most of the notes below exist to
protect one of them. The script is **rerun-safe**: running it twice must change
nothing the first run already did. And `--dry-run` is **honest**: it reports what
is actually on the machine rather than what the package lists say should be.

## What the script does

1. **Preflight** — checks internet, prints the flag configuration and waits for a
   keypress, caches `sudo` upfront with a backgrounded keep-alive, installs the
   Xcode Command Line Tools (polling every 5s until the toolchain is really
   present, because `xcode-select --install` returns immediately and pops a GUI),
   then installs Homebrew if missing and locates its prefix (Apple Silicon
   `/opt/homebrew` or Intel `/usr/local`).
2. **Homebrew update** — `brew update` always; `brew upgrade` only under
   `--upgrade`.
3. **Taps** — adds the third-party repos, then **trusts each one** and verifies
   that its packages resolve.
4. **Formulae** — one batched `brew install` for every CLI tool, with per-package
   fallback if the batch fails.
5. **Casks** — one batched `brew install --cask` for every GUI app and font, with
   on-disk verification of the ones that ship an `.app`.
6. **npm globals** — `netlistsvg` (a schematic viewer for Yosys JSON netlists),
   skipped when it is already in `npm list -g`.
7. **uv tool globals** — `graphifyy` via `uv tool install` (the PyPI package is
   `graphifyy` with a double y; the command it installs is `graphify`), skipped
   when it is already in `uv tool list`. Depends on `uv` from the formulae step.
8. **Extras (direct downloads)** — software fetched straight from the publisher
   rather than through Homebrew, in two shapes: a vendor `.pkg` run through
   `installer` (Microsoft Edge, via `install_pkg_from_url`), and a release
   tarball whose binaries are copied into `~/.local/bin` (Verible, via
   `install_binaries_from_tarball`).
9. **Post-install** — Homebrew bash and zsh into `/etc/shells` and `chsh` to the
   Homebrew zsh, `git lfs install`, interactive Git identity plus non-clobbering
   defaults, an optional GitHub CLI step, the Rust toolchain, fzf key bindings, a
   MacTeX PATH check, then Oh My Zsh, Powerlevel10k, and the three zsh plugins.
10. **Shell config** — writes `~/.zsh_paths`, `~/.zsh_aliases`, `~/.zshrc`,
    `~/.zshenv` and `~/.zprofile` through marker-based injection that preserves
    whatever the user already had in them.
11. **macOS defaults** — stops `.DS_Store` files being written to network and USB
    volumes.
12. **Cleanup** — `brew cleanup`, then a `Brewfile` snapshot exported next to the
    script.
13. **Summary** — printed from an `EXIT` trap, so it appears on Ctrl-C and on a
    mid-script failure as well as on success. Reports newly installed, already
    present, failures, and elapsed time.

## Repository layout

```text
Post-Mac-Setup/
  mac-setup.sh   — the setup script (single file, self-contained)
  README.md      — user-facing docs (package tables, flags, how it works)
  CLAUDE.md      — this file
  LICENSE        — MIT
  .gitignore     — .DS_Store and .claude/
```

The cleanup step writes a `Brewfile` into this same directory (not `$HOME`, not a
temp dir), so a snapshot of the machine's actual Homebrew state sits beside the
declared lists and the two can be diffed. It runs `brew bundle dump --force`.
**Never add `--describe`** — Homebrew 6.x disabled that switch outright, and
descriptions are emitted by default now.

Diff the snapshot against the arrays in **both** directions. A package the arrays
declare and the machine lacks is the obvious case; a package the machine carries
and the arrays do not is the one that gets missed. And Homebrew's own record is
not the last word: a cask can sit in the Caskroom marked "Installed (on request)"
with no application anywhere on disk, so when the dump surprises you, check
`/Applications`, `~/Applications` and `pkgutil --pkgs` before adding an entry.

## CLI flags

| Flag | Effect |
|---|---|
| `--help`, `-h` | Show usage |
| `--dry-run` | Preview actions without making changes (no dotfile writes, no `brew update`, no `git config`) |
| `--upgrade` | Also run `brew upgrade` on already-installed packages (off by default, to avoid surprise breakage on a rerun) |
| `--skip-casks` | Skip GUI app installation |
| `--skip-formulae` | Skip CLI tool installation |
| `--skip-extras` | Skip non-Homebrew direct downloads (Microsoft Edge) |
| `--skip-github` | Skip the GitHub CLI auth and git credential step |
| `--skip-macos` | Skip the macOS `.DS_Store` defaults |
| `--skip-shell` | Skip shell config (`.zshrc`, `.zsh_paths`, `.zsh_aliases`, `.zshenv`, `.zprofile`) |
| `--no-log` | Don't write a log file |

An unrecognised flag is a hard error rather than a warning.

## Packages

These three tables are the contents of the `TAPS`, `FORMULAE` and `CASKS` arrays.
They are the authoritative lists; adding a package means editing an array.

### Taps

| Tap | Why |
|---|---|
| `jithin-sabu/tap` | Purge — only source, not in homebrew/cask |

`chipsalliance/verible` was here until 2026-09-06 and is gone for a reason worth
carrying. Homebrew evaluates every formula in every tap when it works out what is
installable, so that tap's formula calling `depends_on macos: :catalina` — removed
in Homebrew 6.x — made unrelated commands fail outright. **An abandoned tap is a
standing fault, not a dormant one.** The tap is dead upstream (last commit
2025-07-14) and Verible is not in `homebrew/core`, so Verible moved to the extras
section and installs from the project's own release tarball. Do not re-add the tap.

Because of that, every run now **reports third-party taps the script does not
manage**: it walks `brew tap`, skips `homebrew/*`, and warns for each tap absent
from `TAPS`. It only reads, so it runs under `--dry-run` too, and it warns rather
than untapping, since removing a tap can orphan an installed package.

### Formulae

| Category | Packages |
|---|---|
| Shells | `bash` (updated bash, replaces the macOS system bash 3.x), `zsh` (updated zsh, replaces the system zsh) |
| Version control | `git` (replaces the system git), `git-lfs`, `gh` (GitHub CLI), `git-filter-repo` (rewrite history, purge files, rewrite authors) |
| Languages & runtimes | `python@3` (replaces the system python), `node` (includes npm), `pnpm`, `r`, `gcc` (C, C++, Fortran), `go`, `rustup` (includes cargo, rustc) |
| Python tooling | `uv` (fast Python package manager) |
| EDA / hardware design | `icarus-verilog`, `yosys`, `sby` (SymbiYosys, the formal-verification front end for Yosys), `verilator`, `surfer` (waveform viewer for VCD, FST, GHW), `graphviz` |
| RISC-V toolchain | `riscv64-elf-gcc` (bare-metal cross compiler), `dtc` (device tree compiler) |
| Terminal utilities | `tree`, `fzf`, `jq`, `eza`, `zoxide`, `ripgrep`, `coreutils` (GNU `gls`, `gdate`, …), `wget`, `curl`, `bat`, `fd`, `htop`, `tlrc`, `dust`, `bottom` (the `btm` command), `hyperfine`, `difftastic` |
| Media & audio | `ffmpeg` (transcode and mux), `espeak-ng` (speech synthesiser for narration scratch tracks) |
| Build tools | `cmake`, `llvm`, `pandoc`, `plantuml` (uses graphviz), `poppler` (`pdftotext`, `pdfinfo`, `pdftoppm`, `pdfimages`) |
| Homebrew TUI | `bbrew` (Bold Brew, now in homebrew/core) |

`tlrc` is there because the `tldr` formula was disabled upstream on 2025-10-24;
see the disabled-package prune below for what that cost before it was noticed.

One package is **deliberately absent**, and it will look like drift if you do not
know why. `ghostscript` is a declared dependency of the `mactex` cask, so a bare
machine gets it automatically. Homebrew 6.x marks cask-required formulae as
`installed_on_request`, so it shows up in `brew bundle dump` and therefore in the
exported `Brewfile`, which makes it look like an undeclared package on every
audit. It is not. Do not add it. (Compare `gcc`, which *is* declared even though
it also arrives transitively via `r` and `openblas`.)

### Casks

| Category | Packages |
|---|---|
| Editors & IDEs | `visual-studio-code`, `coteditor` |
| AI | `claude` (desktop app), `claude-code` (terminal CLI), `lm-studio` (run local models offline) |
| Productivity | `microsoft-office`, `setapp`, `obsidian`, `notion` |
| LaTeX | `mactex` (full TeX Live, ~5 GB), `texifier`, `skim` (PDF viewer with SyncTeX support) |
| Research & graphics | `zotero`, `inkscape` |
| Photography | `nx-studio` (Nikon viewing/processing suite; a pkg install with no `.app` artifact) |
| Media & audio | `iina` |
| Terminal | `iterm2` |
| Networking & security | `tailscale-app` (renamed upstream from `tailscale`) |
| Browser & messaging | `whatsapp` |
| Window management | `loop` |
| Menu bar | `blip`, `stats`, `thaw` |
| System maintenance | `pearcleaner`, `purge` (from `jithin-sabu/tap`) |
| Fonts (prompt) | `font-meslo-lg-nerd-font`, `font-jetbrains-mono-nerd-font` |
| Fonts (text & display) | `font-inter`, `font-poppins`, `font-archivo`, `font-archivo-black`, `font-anton`, `font-bebas-neue`, `font-caveat`, `font-patrick-hand`, `font-architects-daughter` |

The two Nerd Fonts are not decoration: Powerlevel10k's icons need a patched font,
and the summary at the end tells the user to point their terminal at one of them.

## Key conventions

**Bash-only, and it enforces that.** A guard near the top re-execs the script
under a real bash when another shell started it. `sh mac-setup.sh` ignores the
shebang, and on macOS `/bin/sh` *is* bash — but in POSIX mode, where process
substitution is disabled, so the logging line (`exec > >(tee ...)`) dies with a
syntax error a third of the way in, *after* the `EXIT` trap is armed, printing an
empty summary that reads like a script bug rather than a wrong invocation.
Testing `BASH_VERSION` alone is not enough, because `/bin/sh` sets it; the
discriminator is `set -o posix` reporting `on`, which is true under sh and false
under bash 3.2 and 5.x alike. `POSIXLY_CORRECT` is unset before the exec, since
sh exports it and a fresh bash that inherits it re-enters POSIX mode — that would
loop forever — with a `MAC_SETUP_REEXEC` sentinel as the backstop. Two
constraints on this block: it must stay POSIX-parseable, and it must stay **below
line 20**, because `usage()` prints lines 3–20 of the file as its help text and
anything inserted above silently truncates `--help`.

**Idempotent.** Already-installed packages are detected with one `brew list`
snapshot upfront (cheaper than letting brew skip them one at a time) and counted
into `SKIPPED_COUNT`. `inject_block` replaces existing marker-bounded blocks
rather than appending. Re-trusting a trusted tap is a no-op. Re-sourcing the PATH
file is a no-op.

**Detection runs under `--dry-run`.** The whole detection path — `brew list`,
`brew info`, file existence — is read-only, so a dry run executes it and reports
what it actually found. An early `return` at the top of `batch_install` used to
make a dry run print "Would install" for every package including ones already
present, and skipped the on-disk verification entirely, so a dry run could not
surface a missing app, which is the one thing that check exists to catch. The npm
and uv steps had the same bug and were fixed the same way: the `$DRY_RUN` branch
sits *after* the "already installed" test, never before it.

**Batched install.** `batch_install` calls `brew install <a> <b> <c> …` once for
all new packages, which is 5–10× faster than one call each, and falls back to
per-package installs if the batch fails.

**Disabled-package prune.** Before building the batch, `batch_install` runs one
`brew info --json=v2` over the install list (about 0.3s for the whole thing) and
drops anything Homebrew has **disabled upstream**, naming it in `FAILED_ITEMS`.
This exists because `brew install` refuses the *entire* batch when any single
argument is a disabled formula, so one upstream deprecation silently turns one
fast call into 40+ sequential installs — which is exactly what `tldr` did after
2025-10-24. The prune needs `jq`, which the formulae step installs, so on a first
run against a bare machine it is a no-op and the per-package fallback is the net.
**When a package stops installing, check
`brew info --json=v2 --formula <name> | jq '.formulae[].disabled'` before assuming
the script is broken.**

**Casks are verified on disk, not just in Homebrew's records.** `brew list --cask`
reports what Homebrew *believes*. Dragging an app to the Trash instead of running
`brew uninstall --cask` leaves the Caskroom entry behind — 0 B, but present — so
brew keeps listing it and the script reported "already installed" for an app that
was gone. For casks that ship an `.app`, `batch_install` resolves the artifact
names from one `brew info --json=v2` call and confirms the bundle exists in
`/Applications` or `~/Applications` before believing the record. A cask with no
`app` artifact (the Nerd Fonts, pkg-based installs like `nx-studio`) has
nothing to verify and is left alone. A missing bundle is
repaired with `brew reinstall --cask`, because a plain `brew install --cask`
refuses a cask Homebrew still believes in.

**Alias and versioned names are resolved before anything is called missing.**
`brew list --formula` prints the *resolved* name (`python@3.14`) while `FORMULAE`
declares the stable alias (`python@3`), so an exact-match snapshot never finds it
and every run reports `Would install formula: python@3` for a package that is
already there. Pinning the array to `python@3.14` would trade that for a version
that breaks at 3.15, so the fix lives in `batch_install`: one
`brew info --json=v2` over only the apparent misses, keying off `.installed`,
which is authoritative whenever the package is present under *any* of its names.
The alias and oldname lists are used only to map the answer back to the declared
token. This needs `jq` too, so a bare first run skips it — where the miss is real
anyway.

**Taps are trusted, and the trust is verified.** Recent Homebrew sets
`$HOMEBREW_REQUIRE_TAP_TRUST` by default and silently skips formulae from
untrusted third-party taps, printing "Skipping … because it is not trusted" and
leaving the package uninstalled, so `brew install purge` becomes a no-op and
`brew upgrade` skips it too. Each tap is therefore trusted with
`brew trust --tap` right after tapping. Trust is granted at *tap* level rather
than per-formula because the same setting also gates the commands that evaluate
every formula and cask, which is what `brew bundle dump` in the cleanup step does.
`TRUST_FORMULAE` is then a **verification** pass: `brew trust` does no existence
check of its own, so each entry is resolved with `brew info`, turning a typo or a
tap that failed to clone into a reported failure instead of a package that
quietly never installs. Despite the name, that array holds tapped **casks** as
well as formulae, so the check tries `--formula` and then `--cask`; it was
`--formula` only until the tapped cask was added, at which point it started
reporting a working tap as broken. A bare `brew info` is not a substitute, since
it is ambiguous when a formula and a cask share a name. The whole step is guarded
on `brew trust` existing, because older Homebrew lacks the subcommand and also
does not enforce trust.

Two spelling rules ride along. Write `TAPS` entries the way `brew tap` *prints*
them — `<user>/<name>`, no `homebrew-` prefix — because the already-tapped check
is a full-line grep against that output, and a `homebrew-`-prefixed entry can
never match, so the tap gets re-tapped on every run and counted as newly
installed. And keep `TRUST_FORMULAE` in sync with `TAPS`, so a new tap cannot be
added without also proving it resolves.

**The `rustup` formula no longer ships `rustup-init`** — `brew info rustup` says
so outright. The post-install block looked for
`$BREW_PREFIX/opt/rustup/bin/rustup-init`, never found it, and warned and skipped
on every run; that warning was the only visible symptom of a Rust toolchain the
script never set up. It now probes `rustup default`, which prints the active
toolchain or fails when none is set. The matching PATH bug was worse because it
was silent: `PATH-OVERRIDES` added only `~/.cargo/bin`, a directory that need not
exist, so `rustc` and `cargo` were absent from PATH entirely while rustup and a
working stable toolchain sat in the keg. Both directories are now added — the
keg (`$BREW_PREFIX/opt/rustup/bin`) for rustup's own shims, `~/.cargo/bin` for
whatever `cargo install` puts there.

**PATH applies to every shell, and that takes three files rather than one.**
`~/.zsh_paths` holds the whole PATH policy and is sourced from `~/.zshenv` (read
by *every* zsh, so scripts, `zsh -c`, cron and `ssh <host> <cmd>` get it), again
from `~/.zprofile`, and again from `~/.zshrc`. The repetition is not redundancy.
`/etc/zprofile` runs `/usr/libexec/path_helper` for every **login** shell, which
rebuilds PATH from `/etc/paths` and `/etc/paths.d` with the system directories
near the front and undoes whatever `~/.zshenv` prepended; zsh reads
`/etc/zprofile` *before* `~/.zprofile`, so the `~/.zprofile` copy is what restores
the intended ordering. When the file was sourced from `~/.zshrc` alone the entire
policy applied to interactive shells only, and a script and a terminal on the
same machine resolved `clang` to different compilers. Re-sourcing is safe because
`typeset -U path PATH` makes repeat prepends idempotent, and cheap because the
Homebrew block is guarded on `HOMEBREW_PREFIX` — a cold shell pays about 11 ms
for `brew shellenv`, every nested one about 0.2 ms, since that variable is
exported and inherited. One further constraint on `~/.zshenv`: it is also read by
`scp` and `sftp` sessions, so nothing sourced from it may write to stdout.

**`brew shellenv` rebuilds PATH, it does not prepend.** It runs `path_helper`
with `PATH_HELPER_ROOT` set to the Homebrew prefix, and recovers prior entries
from the PATH it inherits. A shell started with *no* PATH in its environment
(`env -i`, some daemons, some CI runners) gives that subprocess nothing to
recover, so the rebuild drops `/usr/bin` and `/bin` and even `grep` stops
resolving. The `path+=(/usr/bin /bin /usr/sbin /sbin)` line closing the
`HOMEBREW-ENV` block is the guard, and `typeset -U` makes it a no-op whenever
those directories are already present. It was invisible while the file was
sourced from `~/.zshrc` alone, because an interactive shell always had a
populated PATH by then; moving the source into `~/.zshenv` is what exposed it.
**Do not remove that line.**

**Compiler policy — Homebrew clang is the default, Homebrew GCC deliberately is
not.** `PATH-OVERRIDES` puts `$BREW_PREFIX/opt/llvm/bin` ahead of `/usr/bin`, so
`clang`, `clang++`, `clangd`, `dsymutil` and `lldb` resolve to Homebrew LLVM.
That has one measured cost: Homebrew `clang++` defaults to `gnu++17` where Apple
`clang++` defaults to `gnu++14`, so five ordinary pre-C++17 constructs —
`register`, dynamic exception specs, `std::random_shuffle`, `auto_ptr`,
`unary_function` — compile under `/usr/bin/clang++` and fail under the shadowed
one. Pin `-std=gnu++14` when that bites, and note it masks in reverse too, since
C++17 code builds here and fails on a stock Mac.

`gcc` gets no such treatment, and the asymmetry is intentional. **The reason is
not a macOS-specific Homebrew policy**, which is the tempting wrong explanation:
the formula configures with `--program-suffix=-16`, in the shared args array
*outside* the `if OS.mac?` branch, so Linux gets the same names. The unversioned
drivers are never built, so there is nothing to link. A bare `gcc` therefore
stays the Apple clang driver at `/usr/bin/gcc`, which is what Python C
extensions, `node-gyp`, and anything touching ObjC or the Apple frameworks
assume. Exactly one driver is unversioned — `gfortran` — so plain `gfortran`
already *is* GCC 16. **Do not "fix" this by symlinking `gcc` into
`$BREW_PREFIX/bin`**: brew clobbers it on the next upgrade, and the breakage
surfaces in unrelated builds whose errors never mention the symlink. Use
`gcc-16` / `g++-16`, or set `CC` / `CXX` per project.

**LLVM build flags are exported as `LLVM_LDFLAGS` / `LLVM_CPPFLAGS`, never the
bare names.** They were plain `LDFLAGS` and `CPPFLAGS` in every login shell,
which meant every autotools `configure`, make implicit rule, setuptools
C-extension build and `node-gyp` run inherited the LLVM header and library search
paths whether or not it wanted them — and as a clobbering assignment, so nothing
else could contribute to them. `brew info llvm` documents these as flags you opt
into per build, and warns that llvm is keg-only precisely because a parallel
toolchain causes trouble. Opt in at the point of use:
`LDFLAGS="$LLVM_LDFLAGS" CPPFLAGS="$LLVM_CPPFLAGS" ./configure`.

**Homebrew `curl` wins, with a caveat.** curl is keg-only because macOS ships its
own, so `$BREW_PREFIX/opt/curl/bin` is prepended explicitly; without that line the
"prefer Homebrew" intent is simply false for curl. The Homebrew build links
OpenSSL and reads its own CA bundle rather than the macOS Keychain, so a root
installed the normal macOS way (an internal corporate CA, a TLS-inspecting proxy)
is trusted by `/usr/bin/curl` and *not* by this one, which fails with "SSL
certificate problem: unable to get local issuer certificate". Pass `--ca-native`
to fall back to the Keychain, or drop the line.

**Marker-based config injection.** Every managed block in a dotfile is wrapped in
`### BEGIN <ID> (managed by mac-setup.sh - do not edit)` and `### END <ID>`, so a
rerun replaces the block's body and leaves everything else in the file untouched.
`inject_block_top` is the variant for content that must be first in the file,
which is where the Powerlevel10k instant prompt has to go. Before any of this
runs, all five dotfiles are backed up with a timestamp suffix.

**The GitHub CLI step is optional and delegated.** Installing `gh` is not the same
as being able to use it: the formulae step puts the binary on the machine, and
this step logs it in and runs `gh auth setup-git` so that git itself can
authenticate to GitHub over HTTPS. Without that last part a machine looks
completely set up and still cannot clone a private repo or push to one. The logic
is not implemented here — the step looks for a companion setup script beside this
folder (checking one level up first, then a flatter layout) so that several
entry points can share one implementation. **In a standalone clone of this repo
that file is simply absent, and the step reports itself skipped**, which is the
expected outcome, not a failure. It is gated on `--skip-github`, and a non-zero
exit from the companion script lands in `FAILED_ITEMS` rather than aborting the
run. It deliberately does *not* pre-check for `gh` before delegating, because the
companion script is what installs `gh` on a bare machine, and a "gh is missing"
guard would refuse to delegate in exactly the case delegation exists to serve.
One subtlety worth preserving if you ever touch this: the logging line makes
stdout a pipe, `gh` treats a piped stdout as non-interactive and refuses to
prompt, so the companion script binds its interactive I/O to `/dev/tty`. That
both restores the browser flow and keeps the OAuth exchange out of the log file.

**Microsoft Edge is fetched by architecture, not by convenience.** The fwlink
redirector (`linkid=2069148`) advertises itself as the canonical "latest" Edge
`.pkg` and serves an x86_64-only build, so an Apple Silicon Mac installing from it
ends up running Edge under Rosetta. Both the version string and the `.pkg` URL
therefore come from the same response of Microsoft's EdgeUpdates JSON API
(`https://edgeupdates.microsoft.com/api/products`, Stable / MacOS / universal),
so they cannot disagree. On an `arm64` host, if the API is unreachable or cannot
name a universal build, Edge is **skipped and reported** rather than installed
from fwlink — a browser missing until the next run is a smaller problem than a
browser silently emulated. fwlink stays as the fallback on Intel hosts only,
where there is no such hazard. The installed bundle is described as
`<version> (<arch>)` so one string comparison catches both a stale version and a
wrong-architecture build, and the architecture is read with **`lipo -archs`**,
which prints a single line such as `x86_64 arm64`. Do **not** use `file` here:
its output for a universal binary spans three lines, one of which ends in the
exact string `Mach-O 64-bit executable x86_64`, which makes a correct universal
build look Intel-only and forces a pointless reinstall on every run. After
installing, the bundle is re-read and a non-native result is recorded in
`FAILED_ITEMS`.

**Failure tracking.** The script runs under `set -euo pipefail`, but failed
installs are collected into `FAILED_ITEMS` and reported in the summary instead of
halting the run: `batch_install` and the `run` helper catch their own errors.
`clear` is guarded with `|| true` for the same reason — it exits non-zero when
`TERM` is unset (piped output, cron, CI), and that would otherwise kill the run
before the `EXIT` trap is even registered, giving no explanation at all.

**Sudo keep-alive.** `sudo -v` runs upfront and a background loop refreshes the
timestamp every 60s, so a long download such as MacTeX cannot outlast the cached
credentials and stall on a password prompt nobody is watching. The keep-alive PID
is killed in the `EXIT` trap.

**EXIT trap.** `print_summary` is the `EXIT` handler, so the stats block prints on
every exit path — success, error, Ctrl-C. The manual-steps list and the closing
message print only when `SCRIPT_COMPLETED=true`, which is set just before the
natural end.

**Logging.** Output is tee'd to a timestamped file under
`~/Library/Logs/mac-setup/`, the macOS-native location, so logs survive reboots
and the periodic `/tmp` purge. Suppressed by `--no-log`.

**Bash 3.2 compatibility.** A fresh Mac still runs this under the system bash 3.2
until the re-exec picks up a newer one, so there is no `mapfile`, and `"${arr[@]}"`
on an empty array is a hard error under `set -u`. Empty-array expansions are
written as `${arr[@]+"${arr[@]}"}`, which expands to nothing instead. Keep new
array code to that idiom.

## Editing guidelines

Package lists are plain Bash arrays — `TAPS`, `TRUST_FORMULAE`, `FORMULAE`,
`CASKS` — and adding or removing a package means editing one of them and nothing
else. Aliases go in the `ZSH_ALIASES` injection blocks; PATH and environment
variables go in the `ZSH_PATHS` blocks. `inject_block` and `inject_block_top` are
the only sanctioned mechanism for writing to a dotfile; never `echo` or `cat`
directly into a shell config.

The injected blocks are single-quoted Bash strings, which has one non-obvious
consequence: **an apostrophe anywhere inside one, including in a comment, ends
the string** and breaks the script in a way whose error message points somewhere
else entirely. Several blocks carry a `NOTE:` line saying so. Write "does not"
rather than "doesn't" inside them.

The four helpers are:

- **`run cmd args…`** — executes the command, or prints `[DRY RUN] Would run: …`
  under `--dry-run`. No shell eval; arguments are preserved. Use it for any
  side-effecting command that should respect dry-run.
- **`batch_install formula|cask pkg1 pkg2 …`** — handles already-installed
  detection, alias resolution, on-disk cask verification, the disabled-package
  prune, the batched install, the per-package fallback, and the counters.
- **`install_pkg_from_url <app-path> <label> <url> [installed_ver] [latest_ver]`**
  — downloads a publisher `.pkg` and runs `sudo installer -pkg … -target /`. Use
  it for apps where the vendor's own installer is preferred over a cask. When
  both version strings are supplied and equal, the install is skipped as up to
  date; when they differ, the `.pkg` is re-downloaded to upgrade in place; when
  either is empty (the latest could not be fetched, say) it falls back to
  "skip if the app exists". Version *detection* is left to the call site, which
  is where the vendor-specific knowledge belongs.
- **`install_binaries_from_tarball <label> <url> <probe> [installed_ver] [latest_ver]`**
  — downloads a release tarball, finds the `bin/` directory inside it with
  `find … -type d -name bin -print -quit` so the archive's top-level folder name
  does not matter, and copies every executable into `~/.local/bin` with
  `install -m 0755`. No `sudo`, which is why that destination. The skip and
  upgrade contract is identical to the `.pkg` helper's. `<probe>` is one binary
  from the set, used both for the presence check and for the architecture check
  afterwards: on an `arm64` host the installed file is read with **`lipo -archs`**
  and a build without `arm64` is warned about and recorded in `FAILED_ITEMS`.
  Use `lipo`, never `file` — the reason is under the Edge notes above.

When adding a new state-changing command, wrap it in `run`, gate it on
`$DRY_RUN`, or guard it with `|| true` so a failure lands in `FAILED_ITEMS`
rather than killing the script. `defaults write` commands go in the macOS System
Defaults section. New dotfile-writing logic must live inside the
`if $DRY_RUN … else … fi` block in the shell-config section, or a dry run will
mutate the user's home directory. New non-Homebrew installs go in the Extras
section, gated on `$SKIP_EXTRAS`, calling `install_pkg_from_url` for a vendor
`.pkg` or `install_binaries_from_tarball` for a release archive of plain
binaries. `HOST_ARCH` is set once at the top of that section's `else` branch;
read it rather than calling `uname -m` again.

## Before calling a change done

Run `./mac-setup.sh --dry-run` and read the output rather than the exit code. The
dry run does real detection, so it is the cheapest check that the change did not
break idempotency: every package already on the machine should report "already
installed", and nothing should report "Would install" for something that is
plainly present. Then confirm `--help` still prints the full flag list, since the
usage text is a `sed` range over lines 3–20 of the file and any insertion above
that line silently truncates it. Check that `FAILED_ITEMS` is empty, that no
dotfile was clobbered, and — for anything touching the injected blocks — open the
generated `~/.zsh_paths` and confirm no comment inside a single-quoted block
picked up an apostrophe.

Commits follow Conventional Commits with a scope, one logical change per commit,
and a body that explains why rather than what.
