#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

profile="${1:?Usage: ./start.sh <profile> (e.g. personal, work, mac-studio)}"
os="$(uname -s)"

# macOS preparation
if [ "$os" = "Darwin" ]; then
  if ! xcode-select -p >/dev/null 2>&1; then
    log "Command Line Tools missing. Installing non-interactively..."
    clt_placeholder="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
    touch "$clt_placeholder"

    clt_package=$(softwareupdate -l 2>/dev/null | grep -B 1 -E 'Command Line Tools' | awk -F'*' '/^   \*/ {print $2}' | sed -e 's/^ *Label: //' -e 's/^ *//' | sort -V | tail -n1 || true)
    if [ -n "$clt_package" ]; then
      log "Installing $clt_package via softwareupdate..."
      softwareupdate -i "$clt_package" --verbose
    else
      log "Fallback: installing via xcode-select (may trigger dialog if interactive)..."
      xcode-select --install >/dev/null 2>&1 || true
      until xcode-select -p >/dev/null 2>&1; do sleep 5; done
    fi

    rm -f "$clt_placeholder"
    log "Command Line Tools installed."
  fi
fi

# Nix installation
if command -v nix >/dev/null 2>&1; then
  log "Nix already installed, skipping."
else
  log "Installing Nix via Determinate Systems..."
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm \
    || { log "ERROR: Failed to install Nix."; exit 1; }

  # Fresh install: nix isn't on PATH in this shell yet.
  nix_daemon_script="/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
  [ -f "$nix_daemon_script" ] && . "$nix_daemon_script"
  command -v nix >/dev/null 2>&1 \
    || { log "ERROR: nix installed but not on PATH. Open a new terminal and re-run this script."; exit 1; }
  log "Nix installed successfully."
fi

# Apply system configuration
log "Applying $profile config..."
if [ "$os" = "Darwin" ]; then
  # sudo resets $USER/$HOME to root; flake.nix needs the real values.
  sudo USER="$(id -un)" HOME="$HOME" nix run nix-darwin -- switch --flake ".#$profile" --impure
elif [ "$os" = "Linux" ]; then
  if command -v nixos-rebuild >/dev/null 2>&1; then
    sudo nixos-rebuild switch --flake ".#$profile"
  else
    nix run home-manager -- switch --flake ".#$profile"
  fi
else
  log "ERROR: Unsupported operating system: $os"
  exit 1
fi

log "Done. Run 'just init $profile' next to finish git/gh setup."
