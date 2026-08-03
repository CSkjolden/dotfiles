#!/usr/bin/env zsh
#
# brewfile.sh - manage Homebrew packages from per-profile Brewfiles.
#
# Profiles are files in brewfiles/<name>.Brewfile. Select them with the
# HOMEBREW_BUNDLE_PROFILES env var (comma-separated, default: core).
#
# Usage:
#   brewfile.sh [install|check|list ...]   Act on the selected profiles
#   brewfile.sh profiles                    List installable profiles
#   brewfile.sh audit                       Check installed packages are in a profile
#   brewfile.sh dump [--file PATH]          Snapshot installed packages to a Brewfile
#
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
profiles_dir="$script_dir/brewfiles"
audit_only_prefix="inventory."
profiles="${HOMEBREW_BUNDLE_PROFILES:-core}"
# Split the comma-separated profile names into an array.
profile_list=("${(@s:,:)profiles}")

resolve_brewfile_path() {
	local profile="$1"
	echo "$profiles_dir/${profile}.Brewfile"
}

# Concatenate the chosen profile Brewfiles into one file, dropping duplicates.
build_bundle_file() {
	local output_file="$1"
	local dedupe_file="$2"
	local mode="$3"
	shift 3
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
		# Ensure a trailing newline so profiles without one don't merge with the next.
		cat "$brewfile_path" >> "$output_file"
		printf '\n' >> "$output_file"
	done

	# Remove repeated lines and duplicate packages (same type + name).
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

# List profile names found in brewfiles/*.Brewfile, skipping the snapshot file.
# Scope "install" (default) also skips inventory.* (audit-only) profiles.
discover_profiles() {
	local scope="${1:-install}"
	local profile_file base_name profile_name
	local -a discovered=()

	# (N) = don't error when nothing matches; :t = keep just the file name.
	for profile_file in "$profiles_dir"/*.Brewfile(N); do
		base_name="${profile_file:t}"
		profile_name="${base_name%.Brewfile}"
		[[ "$profile_name" == snapshot ]] && continue
		[[ "$scope" == install && "$profile_name" == ${audit_only_prefix}* ]] && continue
		discovered+=("$profile_name")
	done

	printf '%s\n' "${discovered[@]}"
}

# Warn if any installed package is not represented in the profile Brewfiles.
run_profile_audit() {
	local installed_snapshot profile_snapshot profile_dedupe_tmp
	local installed_entries profile_entries
	local all_profiles missing_entries
	local -a all_profiles_array

	# Reduce a Brewfile to a sorted list of "type:name" entries for comparison.
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

	installed_snapshot="$(mktemp "${TMPDIR:-/tmp}/brewfile.installed.XXXXXX")"
	profile_snapshot="$(mktemp "${TMPDIR:-/tmp}/brewfile.profiles.XXXXXX")"
	profile_dedupe_tmp="$(mktemp "${TMPDIR:-/tmp}/brewfile.profiles.dedupe.XXXXXX")"
	installed_entries="$(mktemp "${TMPDIR:-/tmp}/brewfile.installed.entries.XXXXXX")"
	profile_entries="$(mktemp "${TMPDIR:-/tmp}/brewfile.profiles.entries.XXXXXX")"

	{
		all_profiles="$(discover_profiles audit)"
		# (@f) splits the newline-separated names into an array.
		all_profiles_array=("${(@f)all_profiles}")
		build_bundle_file "$profile_snapshot" "$profile_dedupe_tmp" audit "${all_profiles_array[@]}" || return

		brew bundle dump --file "$installed_snapshot" --force --no-describe >/dev/null || return

		normalize_entries "$installed_snapshot" > "$installed_entries"
		normalize_entries "$profile_snapshot" > "$profile_entries"
		missing_entries="$(comm -23 "$installed_entries" "$profile_entries" | grep -Ev '^(brew:rust)$' || true)"

		if [[ -n "$missing_entries" ]]; then
			echo "Installed entries missing from profile files:" >&2
			printf '%s\n' "$missing_entries" >&2
			return 2
		fi

		echo "All installed Brew Bundle entries are represented in profiles." >&2
	} always {
		rm -f "$installed_snapshot" "$profile_snapshot" "$profile_dedupe_tmp" "$installed_entries" "$profile_entries"
	}
}

# Route to the requested command; anything else installs the selected profiles.
case "${1:-}" in
	dump|snapshot)
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
		;;

	audit|check-profiles)
		run_profile_audit
		exit $?
		;;

	profiles|list-profiles)
		discover_profiles
		;;

	*)
		# Default: build one combined Brewfile and hand it to `brew bundle`.
		tmp_brewfile="$(mktemp "${TMPDIR:-/tmp}/brewfile.XXXXXX")"
		tmp_dedupe="$(mktemp "${TMPDIR:-/tmp}/brewfile.dedupe.XXXXXX")"
		trap 'rm -f "$tmp_brewfile" "$tmp_dedupe"' EXIT

		build_bundle_file "$tmp_brewfile" "$tmp_dedupe" install "${profile_list[@]}"

		[[ $# -gt 0 ]] || set -- install
		exec brew bundle --file "$tmp_brewfile" "$@"
		;;
esac