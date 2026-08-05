#!/usr/bin/env zsh
set -euo pipefail

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "Installing Homebrew..."
if ! command -v brew &> /dev/null; then
  if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
    log "Homebrew installed successfully."
  else
    log "ERROR: Failed to install Homebrew."
    exit 1
  fi
  # Fresh install: brew isn't on PATH in this shell yet, so locate it directly.
  BREW_BIN="/opt/homebrew/bin/brew"
  [[ -x "$BREW_BIN" ]] || BREW_BIN="/usr/local/bin/brew"
  eval "$("$BREW_BIN" shellenv)"
else
  log "Homebrew already installed, skipping."
fi


log "Configuring Homebrew in Zsh..."
BREW_PREFIX="$(brew --prefix)"
BREW_SHELLENV_LINE="eval \"\$(${BREW_PREFIX}/bin/brew shellenv)\""
if ! grep -Fqx "$BREW_SHELLENV_LINE" ~/.zprofile 2>/dev/null; then
  echo "$BREW_SHELLENV_LINE" >> ~/.zprofile
fi
eval "$("${BREW_PREFIX}/bin/brew" shellenv)"

log "Installing Just..."
if brew install just; then
  log "Just installed successfully."
else
  log "ERROR: Failed to install Just."
  exit 1
fi

just hooks-install
softwareupdate --install-rosetta --agree-to-license
zsh .macos
cat <<'GUIDE'

Bootstrap complete. Use Just to install and configure the rest:

  just profiles
  just install core personal
  just install core work
  just check core work
  just audit
  just git-setup

Tip: add or remove profile names after `just install` as needed.
GUIDE
