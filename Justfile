set shell := ["zsh", "-eu", "-c"]
rebuild := `command -v darwin-rebuild >/dev/null 2>&1 && echo darwin-rebuild || echo "nix run nix-darwin --"`

default:
    @just --list

# Configure dotfiles git hooks
hooks-install:
    git config core.hooksPath .githooks
    chmod +x .githooks/pre-commit

# Sync with dotfiles config
sync profile:
    sudo USER="$(id -un)" HOME="$HOME" {{rebuild}} switch --flake .#{{profile}} --impure

# Check flake evaluates and no undeclared Homebrew packages
audit:
    ./nix-helpers.sh audit

# Log in to github with the scopes gitIdentity needs (adds user:email if missing)
github-login:
    gh auth status --hostname github.com >/dev/null 2>&1 \
        && gh auth refresh -h github.com -s user:email \
        || gh auth login -h github.com -w -c -s user:email

# Initial run on new machine
init profile:
    @just hooks-install
    @just sync {{profile}}
    @just github-login
    @just sync {{profile}}

