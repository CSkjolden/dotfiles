set shell := ["zsh", "-eu", "-c"]

default:
    @just --list

# List dynamic profiles discovered in brewfiles/*.Brewfile
profiles:
    zsh brewfile.sh profiles

# Install selected profiles (defaults to core)
install *selected_profiles='core':
    profiles="{{selected_profiles}}"; HOMEBREW_BUNDLE_PROFILES="${profiles// /,}" zsh brewfile.sh

# Check whether selected profiles are already satisfied
check *selected_profiles='core':
    profiles="{{selected_profiles}}"; HOMEBREW_BUNDLE_PROFILES="${profiles// /,}" zsh brewfile.sh check

# List formulae/casks selected by profiles
list *selected_profiles='core':
    profiles="{{selected_profiles}}"; HOMEBREW_BUNDLE_PROFILES="${profiles// /,}" zsh brewfile.sh list

# List only casks for selected profiles
list-casks *selected_profiles='core':
    profiles="{{selected_profiles}}"; HOMEBREW_BUNDLE_PROFILES="${profiles// /,}" zsh brewfile.sh list --cask

# Audit installed machine state against all discovered profile files
audit:
    zsh brewfile.sh audit

# Configure local git hooks path to use tracked hooks in .githooks
hooks-install:
    git config core.hooksPath .githooks
    chmod +x .githooks/pre-commit

# Configure git identity and GitHub git integration
git-setup:
    zsh git.sh

# Run Rust setup/update workflow (toolchain, components, and cargo utilities)
rust-setup:
    zsh rust.sh

# Dump installed machine state to brewfiles/snapshot.Brewfile
snapshot:
    zsh brewfile.sh dump

# Dump installed machine state to a custom Brewfile path
snapshot-to output_file:
    zsh brewfile.sh dump --file "{{output_file}}"

# Personal computer
personal:
    just install core personal development
    just rust-setup
    just git-setup
