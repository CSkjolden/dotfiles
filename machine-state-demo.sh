#!/usr/bin/env zsh
set -euo pipefail

log() {
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || {
		log "ERROR: $1 is required. Run ./start.sh first."
		exit 1
	}
}

print_help() {
	cat <<'EOF'
Demo seeding script for MachineState.

Usage:
  ./machine-state-demo.sh

What it does:
  Creates a few example custom items with fields so you can see the modular
  storage pattern in practice.

Examples:
  ./machine-state-demo.sh
EOF
}

root_dir="$(cd "$(dirname "$0")" && pwd)"
vault_name="${PROTON_PASS_VAULT_NAME:-MachineState}"

case "${1:-}" in
	-h|--help|help)
		print_help
		exit 0
		;;
	"")
		;;
	*)
		print_help
		exit 1
		;;
esac

require_cmd zsh
require_cmd uuidgen

log "Seeding demo values in '$vault_name'..."
zsh "$root_dir/machine-state.sh" vault ensure --name "$vault_name"

zsh "$root_dir/machine-state.sh" item upsert custom \
	--name "$vault_name" \
	--title "GitHub Token" \
	--field "value=ghp_example_token_value" \
	--field "kind=github-token" \
	--field "provider=github"

zsh "$root_dir/machine-state.sh" item upsert custom \
	--name "$vault_name" \
	--title "Machine Profile" \
	--field "value=$USER@$(hostname -s 2>/dev/null || hostname)" \
	--field "hostname=$(hostname)" \
	--field "short_hostname=$(hostname -s 2>/dev/null || hostname)"

zsh "$root_dir/machine-state.sh" item upsert custom \
	--name "$vault_name" \
	--title "Demo UUID" \
	--field "value=$(uuidgen)"

log "Demo values created. Use ./machine-state.sh item list --name '$vault_name' to inspect them."