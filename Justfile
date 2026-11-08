set shell := ["zsh", "-eu", "-c"]
rebuild := `command -v darwin-rebuild >/dev/null 2>&1 && echo darwin-rebuild || echo "nix run nix-darwin --"`

default:
    @just --list

# Configure dotfiles git hooks
hooks-install:
    git config core.hooksPath .githooks
    chmod +x .githooks/pre-commit

# Sync with dotfiles config
sync profile: _git-add _brew-update
    sudo USER="$(id -un)" HOME="$HOME" {{rebuild}} switch --flake .#{{profile}} --impure

# Update nixpkgs (or another flake input) and verify the profile builds, without switching
update profile input="nixpkgs": _git-add
    nix flake update {{input}}
    nix build '.#darwinConfigurations.{{profile}}.system' --impure --no-link
    @echo "Build OK. Review with 'git diff flake.lock', then 'just sync {{profile}}' and commit flake.lock."

[private]
_brew-update:
    [ ! -x /opt/homebrew/bin/brew ] || /opt/homebrew/bin/brew update

# Reload SketchyBar config without a rebuild
bar:
    sketchybar --reload

[private]
_git-add:
    git add -u && git add -N .

# Check flake evaluates and no undeclared Homebrew packages
audit:
    ./nix-helpers.sh audit

# Check if any new macOS preference keys have been added since the last check
preference-audit:
    ./nix-helpers.sh macos-check

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

