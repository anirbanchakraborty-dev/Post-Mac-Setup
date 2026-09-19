# Brewfile - a `brew bundle dump` of the reference Mac (Darwin arm64),
# regenerated 2026-09-19. Restore with `brew bundle install`.
#
# Regenerate with plain `brew bundle dump --force`. Do NOT pass --describe:
# Homebrew 6.x disabled that switch outright, because emitting the one-line
# descriptions below is now the default behaviour.
#
# This file and the FORMULAE / CASKS arrays in mac-setup.sh are close but not
# identical, and all three differences are deliberate rather than drift:
#
#   gcc            declared by mac-setup.sh, absent here. It arrives
#                  transitively via r and openblas, so Homebrew does not mark
#                  it installed_on_request and a dump does not name it.
#   ghostscript    present here, deliberately not declared by mac-setup.sh. It
#                  is a declared dependency of the mactex cask, and Homebrew
#                  marks cask-required formulae installed_on_request, so a dump
#                  names it even though nobody asked for it by name.
#   emacs-plus@31  installed on the reference Mac and in neither file, and its
#                  d12frosted/emacs-plus tap is out of both too. It is the one
#                  package here that compiles from source instead of arriving
#                  as a prebuilt bottle, and a source build leans on a compiler
#                  the same run has only just installed. So it is a documented
#                  manual step that follows the automated run rather than
#                  joining it - see the Emacs section of the README. A plain
#                  `brew bundle dump --force` puts both lines back; delete them
#                  again, and ship-check.mjs in the hub repo will say so if you
#                  forget.
#
# pkgconf used to be a third difference and is not any more: it is declared
# in both since 2026-09-13, because nothing installed needs it at run time and
# a bottle install does not pull in build dependencies.
#
# Verible is absent from this file on purpose. Its only Homebrew source was
# the chipsalliance/verible tap, which went dead upstream (last commit
# 2025-07-14) and whose formula stopped loading under Homebrew 6.x, breaking
# every brew command on the machine. It is installed from the project's own
# release tarball now - see the EXTRAS section of mac-setup.sh.
# Language server for NASM/GAS/GO Assembly
brew "asm-lsp"
# Tool for generating GNU Standards-compliant Makefiles
brew "automake"
# Open-source, cross-platform JavaScript runtime environment
brew "node"
# Pyright fork with various improvements and built-in pylance features
brew "basedpyright"
# Bourne-Again SHell, a UNIX command interpreter
brew "bash"
# Language Server for Bash
brew "bash-language-server"
# Clone of cat(1) with syntax highlighting and Git integration
brew "bat"
# TUI for managing Homebrew, Flatpak, and Mac App Store packages
brew "bbrew"
# Yet another cross-platform graphical process/system monitor
brew "bottom"
# Cross-platform make
brew "cmake"
# GNU File, Shell, and Text utilities
brew "coreutils"
# Get a file from an HTTP, HTTPS or FTP server
brew "curl"
# Debugger for the Go programming language
brew "delve"
# Diff that understands syntax
brew "difftastic"
# Load/unload environment variables based on $PWD
brew "direnv"
# Language server for Dockerfiles powered by Node, TypeScript, and VSCode
brew "dockerfile-language-server"
# .NET Core
brew "dotnet"
# Device tree compiler
brew "dtc"
# More intuitive version of du in rust
brew "dust"
# Language Server and Debugger for Elixir
brew "elixir-ls"
# Spellchecker wrapping library
brew "enchant"
# Speech synthesizer that supports more than hundred languages and accents
brew "espeak-ng"
# Modern, maintained replacement for ls
brew "eza"
# Simple, fast and user-friendly alternative to find
brew "fd"
# Play, record, convert, and stream select audio and video codecs
brew "ffmpeg"
# Command-line fuzzy finder written in Go
brew "fzf"
# GitHub command-line tool
brew "gh"
# Interpreter for PostScript and PDF
brew "ghostscript"
# Distributed revision control system
brew "git"
# Quickly rewrite git repository history
brew "git-filter-repo"
# Git extension for versioning large files
brew "git-lfs"
# Open source programming language to build simple/reliable/efficient software
brew "go"
# Graph visualization software from AT&T and Bell Labs
brew "graphviz"
# Grammar Checker for Developers
brew "harper"
# Improved top (interactive process viewer)
brew "htop"
# Command-line benchmarking tool
brew "hyperfine"
# Verilog simulation and synthesis tool
brew "icarus-verilog"
# Interpreted, interactive, object-oriented programming language
brew "python@3.14"
# Java language specific implementation of the Language Server Protocol
brew "jdtls"
# Lightweight and flexible command-line JSON processor
brew "jq"
# Next-gen compiler infrastructure
brew "llvm"
# Language Server for the Lua language
brew "lua-language-server"
# Language Server Protocol for Markdown
brew "marksman"
# Another cmake lsp
brew "neocmakelsp"
# Swiss-army knife of markup format conversion
brew "pandoc"
# Package compiler and linker metadata toolkit
brew "pkgconf"
# Draw UML diagrams
brew "plantuml"
# Fast, disk space efficient package manager
brew "pnpm"
# PDF rendering library (based on the xpdf-3.0 code base)
brew "poppler"
# Code formatter for JavaScript, CSS, JSON, GraphQL, Markdown, YAML
brew "prettier"
# Software environment for statistical computing
brew "r"
# Search tool like grep and The Silver Searcher
brew "ripgrep"
# GNU compiler collection for riscv64-elf
brew "riscv64-elf-gcc"
# Opinionated language server for Ruby
brew "ruby-lsp"
# Extremely fast Python linter, written in Rust
brew "ruff"
# Rust toolchain installer
brew "rustup"
# Framework for Verilog RTL synthesis
brew "yosys"
# Front-end for Yosys-based formal verification flows
brew "sby"
# Static analysis and lint tool, for (ba)sh scripts
brew "shellcheck"
# Autoformat shell script source code
brew "shfmt"
# Waveform viewer, supporting VCD, FST, or GHW format
brew "surfer"
# TOML toolkit written in Rust
brew "taplo"
# Implementation of the Language Server Protocol for LaTeX
brew "texlab"
# Official tldr client written in Rust
brew "tlrc"
# Display directories as trees (with optional color/HTML output)
brew "tree"
# Language Server Protocol implementation for TypeScript wrapping tsserver
brew "typescript-language-server"
# Extremely fast Python package installer and resolver, written in Rust
brew "uv"
# Verilog simulator
brew "verilator"
# Language servers for HTML, CSS, JavaScript, and JSON extracted from vscode
brew "vscode-langservers-extracted"
# Internet file retriever
brew "wget"
# Language Server for Yaml Files
brew "yaml-language-server"
# Shell extension to navigate your filesystem faster
brew "zoxide"
# UNIX shell (command interpreter)
brew "zsh"
# Send any size file between devices
cask "blip"
# Anthropic's official Claude AI desktop app
cask "claude"
# Terminal-based AI coding assistant
cask "claude-code"
# Plain-text editor for web pages, program source codes and more
cask "coteditor"
cask "font-anton"
cask "font-architects-daughter"
cask "font-archivo"
cask "font-archivo-black"
cask "font-bebas-neue"
cask "font-caveat"
cask "font-inter"
cask "font-jetbrains-mono-nerd-font"
cask "font-meslo-lg-nerd-font"
cask "font-patrick-hand"
cask "font-poppins"
# Vector graphics editor
cask "inkscape"
# Terminal emulator as alternative to Apple's Terminal app
cask "iterm2"
# Blocks all Keyboard and TouchBar input
cask "keyboardcleantool"
# Discover, download, and run local LLMs
cask "lm-studio"
# Window manager
cask "loop"
# Full TeX Live distribution with GUI applications
cask "mactex"
# Office suite
cask "microsoft-office"
# App to write, plan, collaborate, and get organised
cask "notion"
# Nikon suite for viewing, processing, and editing photos and videos
cask "nx-studio"
# Collection of apps available by subscription
cask "setapp"
# PDF reader and note-taking application
cask "skim"
# VPN client for secure internet access and private browsing
cask "surfshark"
# Mesh VPN based on WireGuard
cask "tailscale-app"
# LaTeX editor
cask "texifier"
# Open-source code editor
cask "visual-studio-code"
# Native desktop client for WhatsApp
cask "whatsapp"
# Collect, organise, cite, and share research sources
cask "zotero"
vscode "anthropic.claude-code"
vscode "bierner.markdown-checkbox"
vscode "bierner.markdown-footnotes"
vscode "bierner.markdown-mermaid"
vscode "bierner.markdown-preview-github-styles"
vscode "bierner.markdown-yaml-preamble"
vscode "bmewburn.vscode-intelephense-client"
vscode "bracketpaircolordlw.bracket-pair-color-dlw"
vscode "bradlc.vscode-tailwindcss"
vscode "charliermarsh.ruff"
vscode "christian-kohler.npm-intellisense"
vscode "codezombiech.gitignore"
vscode "connor.bib-checker"
vscode "dart-code.dart-code"
vscode "dart-code.flutter"
vscode "davidanson.vscode-markdownlint"
vscode "dbaeumer.vscode-eslint"
vscode "deerawan.vscode-dash"
vscode "ecmel.vscode-html-css"
vscode "esbenp.prettier-vscode"
vscode "github.vscode-github-actions"
vscode "github.vscode-pull-request-github"
vscode "golang.go"
vscode "hansuxdev.bootstrap5-snippets"
vscode "hossaini.bootstrap-intellisense"
vscode "james-yu.latex-workshop"
vscode "jebbs.plantuml"
vscode "magicstack.magicpython"
vscode "matthiasschedel.bibtex-manager"
vscode "mechatroner.rainbow-csv"
vscode "mhutchie.git-graph"
vscode "mrmlnc.vscode-autoprefixer"
vscode "ms-dotnettools.csdevkit"
vscode "ms-dotnettools.csharp"
vscode "ms-dotnettools.vscode-dotnet-runtime"
vscode "ms-edgedevtools.vscode-edge-devtools"
vscode "ms-python.autopep8"
vscode "ms-python.black-formatter"
vscode "ms-python.debugpy"
vscode "ms-python.flake8"
vscode "ms-python.isort"
vscode "ms-python.pylint"
vscode "ms-python.python"
vscode "ms-python.vscode-pylance"
vscode "ms-python.vscode-python-envs"
vscode "ms-toolsai.jupyter"
vscode "ms-toolsai.jupyter-keymap"
vscode "ms-toolsai.jupyter-renderers"
vscode "ms-toolsai.vscode-jupyter-cell-tags"
vscode "ms-toolsai.vscode-jupyter-powertoys"
vscode "ms-toolsai.vscode-jupyter-slideshow"
vscode "ms-vscode-remote.remote-ssh"
vscode "ms-vscode-remote.remote-ssh-edit"
vscode "ms-vscode-remote.remote-wsl"
vscode "ms-vscode-remote.vscode-remote-extensionpack"
vscode "ms-vscode.cmake-tools"
vscode "ms-vscode.cpp-devtools"
vscode "ms-vscode.cpptools"
vscode "ms-vscode.hexeditor"
vscode "ms-vscode.live-server"
vscode "ms-vscode.powershell"
vscode "ms-vscode.remote-explorer"
vscode "ms-vscode.remote-repositories"
vscode "ms-vscode.remote-server"
vscode "ms-vscode.vscode-chat-customizations-evaluations"
vscode "naumovs.color-highlight"
vscode "oderwat.indent-rainbow"
vscode "pranaygp.vscode-css-peek"
vscode "quarto.quarto"
vscode "redhat.vscode-yaml"
vscode "reditorsupport.r"
vscode "reditorsupport.r-syntax"
vscode "sumneko.lua"
vscode "surfer-project.surfer"
vscode "tecosaur.latex-utilities"
vscode "thekalinga.bootstrap4-vscode"
vscode "unifiedjs.vscode-mdx"
vscode "vira.vsc-vira-theme"
vscode "vitaliymaz.vscode-svg-previewer"
vscode "xyc.vscode-mdx-preview"
vscode "yzhang.markdown-all-in-one"
vscode "zignd.html-css-class-completion"
go "golang.org/x/tools/gopls"
cargo "vhdl_ls"
uv "debugpy"
uv "graphifyy"
uv "skillspector", source: "git+https://github.com/NVIDIA/skillspector.git"
npm "@mdx-js/language-server"
npm "intelephense"
npm "netlistsvg"
