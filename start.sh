#!/usr/bin/env zsh
set -euo pipefail

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

profile="${1:?Usage: ./start.sh <personal|work>}"

if command -v nix &> /dev/null; then
  log "Nix already installed, skipping."
else
  log "Installing Nix..."
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install \
    || { log "ERROR: Failed to install Nix."; exit 1; }
  # Fresh install: nix isn't on PATH in this shell yet.
  nix_daemon_script="/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
  [[ -f "$nix_daemon_script" ]] && . "$nix_daemon_script"
  command -v nix &> /dev/null \
    || { log "ERROR: nix installed but not on PATH. Open a new terminal and re-run this script."; exit 1; }
  log "Nix installed successfully."
fi

log "Applying $profile config..."
# sudo resets $USER/$HOME to root; flake.nix needs the real values.
sudo USER="$(id -un)" HOME="$HOME" nix run nix-darwin -- switch --flake ".#$profile" --impure

log "Done. Run 'just init $profile' next to finish git/gh setup."
