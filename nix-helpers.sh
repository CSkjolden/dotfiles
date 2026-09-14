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

top_level_keys() {
	awk '
		depth == 1 && match($0, /^[[:space:]]*"?[A-Za-z0-9_.]+"?[[:space:]]*=/) {
			key = $0
			sub(/^[[:space:]]*"?/, "", key)
			sub(/"?[[:space:]]*=.*/, "", key)
			print key
		}
		{ depth += gsub(/{/, "{") - gsub(/}/, "}") }
	'
}

macos_snapshot_dir() {
	local dir="${XDG_CACHE_HOME:-$HOME/.cache}/nix-helpers/macos-keys"
	mkdir -p "$dir"
	echo "$dir"
}

run_macos_check() {
	command -v defaults >/dev/null 2>&1 || {
		echo "[nix-helpers] defaults not available, skipping." >&2
		return 0
	}

	local state_dir domain safe_name snapshot_file current added new=0 changed=0
	state_dir="$(macos_snapshot_dir)"

	for domain in $(defaults domains 2>/dev/null | tr ',' ' '); do
		safe_name="${domain//\//_}"
		snapshot_file="$state_dir/$safe_name.keys"
		current="$(defaults read "$domain" 2>/dev/null | top_level_keys | sort -u || true)"

		if [[ -f "$snapshot_file" ]]; then
			added="$(comm -23 <(echo "$current") "$snapshot_file")"
			if [[ -n "$added" ]]; then
				echo "[nix-helpers] $domain: new preference keys since last check:" >&2
				echo "$added" | sed 's/^/  + /' >&2
				((changed += 1))
			fi
		else
			((new += 1))
		fi
		echo "$current" >"$snapshot_file"
	done

	if ((changed > 0)); then
		echo "[nix-helpers] Review the new keys above and add anything intentional to darwin/macos.nix." >&2
	elif ((new > 0)); then
		echo "[nix-helpers] Baseline saved for $new domain(s). Run this again later to see what changed." >&2
	else
		echo "[nix-helpers] No new preference keys since the last check." >&2
	fi
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
macos-check)
	run_macos_check
	;;
*)
	echo "Usage: $0 [audit|macos-check]" >&2
	exit 1
	;;
esac
