#!/usr/bin/env zsh
set -euo pipefail
cd "$(dirname "$0")"

check_flake() {
	echo "[nix-helpers] Checking flake evaluates..."
	nix flake show >/dev/null
}

check_homebrew_drift() {
	command -v brew >/dev/null 2>&1 || return 0

	echo "[nix-helpers] Checking for undeclared Homebrew packages..."
	local declared installed undeclared
	declared="$(grep -ohE '"[a-zA-Z0-9@._-]+"' darwin/homebrew/*.nix | tr -d '"' | sort -u)"
	installed="$( { brew leaves; brew list --cask; } 2>/dev/null | sort -u)"
	undeclared="$(comm -23 <(echo "$installed") <(echo "$declared"))"

	if [[ -n "$undeclared" ]]; then
		echo "[nix-helpers] ERROR: installed via Homebrew but not declared in darwin/homebrew/*.nix:" >&2
		echo "$undeclared" | sed 's/^/  - /' >&2
		return 1
	fi
	echo "[nix-helpers] No Homebrew drift found."
}

run_audit() {
	if ! command -v nix >/dev/null 2>&1; then
		echo "[nix-helpers] ERROR: nix is required. Run start.sh first." >&2
		exit 1
	fi
	check_flake
	check_homebrew_drift
}

case "${1:-audit}" in
audit)
	run_audit
	;;
*)
	echo "Usage: $0 [audit]" >&2
	exit 1
	;;
esac
