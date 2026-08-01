#!/usr/bin/env zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
profiles_dir="$script_dir/brewfiles"
audit_only_prefix="inventory."
profiles="${HOMEBREW_BUNDLE_PROFILES:-core}"
IFS=, read -rA profile_list <<< "$profiles"

resolve_brewfile_path() {
	local profile="$1"
	echo "$profiles_dir/${profile}.Brewfile"
}

build_bundle_file() {
	local output_file="$1"
	local dedupe_file="$2"
	local mode="$3"
	shift
	shift
	shift
	local selected_profile
	local brewfile_path
	local audit_only_path

	: > "$output_file"
	for selected_profile in "$@"; do
		selected_profile="${selected_profile//[[:space:]]/}"
		[[ -n "$selected_profile" ]] || continue
		if [[ "$mode" == install && "$selected_profile" == ${audit_only_prefix}* ]]; then
			echo "Profile '$selected_profile' is audit-only and cannot be installed." >&2
			return 1
		fi
		brewfile_path="$(resolve_brewfile_path "$selected_profile")"
		[[ -f "$brewfile_path" ]] || {
			audit_only_path="$profiles_dir/${audit_only_prefix}${selected_profile}.Brewfile"
			if [[ "$mode" == install && -f "$audit_only_path" ]]; then
				echo "Profile '$selected_profile' is audit-only. Use your setup script instead (for Rust: just rust-setup)." >&2
				return 1
			fi
			echo "Unknown profile '$selected_profile'" >&2
			return 1
		}
		cat "$brewfile_path" >> "$output_file"
	done

	awk '
		function maybe_print() {
			if (line == "") {
				return
			}

			if (line ~ /^(brew|cask|tap|mas|vscode|go|cargo|uv|flatpak|winget|krew|npm)[[:space:]]+"/) {
				kind = line
				sub(/[[:space:]].*$/, "", kind)
				if (match(line, /"[^"]+"/)) {
					name = substr(line, RSTART + 1, RLENGTH - 2)
					if (kind == "brew") {
						n = split(name, parts, "/")
						name = parts[n]
					}
					key = kind ":" name
					if (seen[key]++) {
						line = ""
						return
					}
				}
			}

			if (!(line in printed_lines)) {
				print line
				printed_lines[line] = 1
			}
			line = ""
		}

		{
			line = $0
			maybe_print()
		}
	' "$output_file" > "$dedupe_file"
	mv "$dedupe_file" "$output_file"
}

discover_install_profiles() {
	local profile_file
	local base_name
	local profile_name
	local -a discovered=()

	for profile_file in "$profiles_dir"/*.Brewfile(N); do
		base_name="${profile_file:t}"
		profile_name="${base_name%.Brewfile}"
		[[ "$profile_name" == snapshot ]] && continue
		[[ "$profile_name" == ${audit_only_prefix}* ]] && continue
		discovered+=("$profile_name")
	done

	printf '%s\n' "${discovered[@]}"
}

discover_audit_profiles() {
	local profile_file
	local base_name
	local profile_name
	local -a discovered=()

	for profile_file in "$profiles_dir"/*.Brewfile(N); do
		base_name="${profile_file:t}"
		profile_name="${base_name%.Brewfile}"
		[[ "$profile_name" == snapshot ]] && continue
		discovered+=("$profile_name")
	done

	printf '%s\n' "${discovered[@]}"
}

run_profile_audit() {
	local installed_snapshot profile_snapshot profile_dedupe_tmp
	local installed_entries profile_entries
	local all_profiles
	local -a all_profiles_array
	local missing_entries
	local exit_code

	installed_snapshot="$(mktemp "${TMPDIR:-/tmp}/brewfile.installed.XXXXXX")"
	profile_snapshot="$(mktemp "${TMPDIR:-/tmp}/brewfile.profiles.XXXXXX")"
	profile_dedupe_tmp="$(mktemp "${TMPDIR:-/tmp}/brewfile.profiles.dedupe.XXXXXX")"
	installed_entries="$(mktemp "${TMPDIR:-/tmp}/brewfile.installed.entries.XXXXXX")"
	profile_entries="$(mktemp "${TMPDIR:-/tmp}/brewfile.profiles.entries.XXXXXX")"

	normalize_entries() {
		local input_file="$1"
		awk '
			/^(brew|cask|tap|mas|vscode|go|uv|flatpak|winget|krew|npm)[[:space:]]+"/ {
				kind = $1
				if (match($0, /"[^"]+"/)) {
					name = substr($0, RSTART + 1, RLENGTH - 2)
					if (kind == "brew") {
						n = split(name, parts, "/")
						print "brew:" parts[n]
					} else {
						print kind ":" name
					}
				}
			}
		' "$input_file" | LC_ALL=C sort -u
	}

	all_profiles="$(discover_audit_profiles)"
	all_profiles_array=("${(@f)all_profiles}")
	build_bundle_file "$profile_snapshot" "$profile_dedupe_tmp" audit "${all_profiles_array[@]}" || {
		exit_code=$?
		rm -f "$installed_snapshot" "$profile_snapshot" "$profile_dedupe_tmp" "$installed_entries" "$profile_entries"
		return "$exit_code"
	}

	brew bundle dump --file "$installed_snapshot" --force --no-describe >/dev/null || {
		exit_code=$?
		rm -f "$installed_snapshot" "$profile_snapshot" "$profile_dedupe_tmp" "$installed_entries" "$profile_entries"
		return "$exit_code"
	}

	normalize_entries "$installed_snapshot" > "$installed_entries"
	normalize_entries "$profile_snapshot" > "$profile_entries"
	missing_entries="$(comm -23 "$installed_entries" "$profile_entries" | grep -Ev '^(brew:rust)$' || true)"

	if [[ -n "$missing_entries" ]]; then
		echo "Installed entries missing from profile files:" >&2
		printf '%s\n' "$missing_entries" >&2
		rm -f "$installed_snapshot" "$profile_snapshot" "$profile_dedupe_tmp" "$installed_entries" "$profile_entries"
		return 2
	fi

	echo "All installed Brew Bundle entries are represented in profiles." >&2
	rm -f "$installed_snapshot" "$profile_snapshot" "$profile_dedupe_tmp" "$installed_entries" "$profile_entries"
}

if [[ "${1:-}" == dump || "${1:-}" == snapshot ]]; then
	shift
	snapshot_file="$profiles_dir/snapshot.Brewfile"
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--file)
				snapshot_file="$2"
				shift 2
				;;
			*)
				break
				;;
		esac
	done

	exec brew bundle dump --file "$snapshot_file" -f "$@"
fi

if [[ "${1:-}" == audit || "${1:-}" == check-profiles ]]; then
	shift
	run_profile_audit "$@"
	exit $?
fi

if [[ "${1:-}" == profiles || "${1:-}" == list-profiles ]]; then
	shift
	discover_install_profiles
	exit 0
fi

tmp_brewfile="$(mktemp "${TMPDIR:-/tmp}/brewfile.XXXXXX")"
tmp_dedupe="$(mktemp "${TMPDIR:-/tmp}/brewfile.dedupe.XXXXXX")"
cleanup() {
	rm -f "$tmp_brewfile" "$tmp_dedupe"
}
trap cleanup EXIT

build_bundle_file "$tmp_brewfile" "$tmp_dedupe" install "${profile_list[@]}"

if [[ $# -eq 0 ]]; then
	set -- install
fi

exec brew bundle --file "$tmp_brewfile" "$@"