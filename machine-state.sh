#!/usr/bin/env zsh
set -euo pipefail

DEFAULT_VAULT_NAME="${PROTON_PASS_VAULT_NAME:-MachineState}"

log() {
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

die() {
	log "ERROR: $1"
	exit 1
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "$1 is required. Run ./start.sh first."
}

json_escape() {
	local value="$1"
	value=${value//\\/\\\\}
	value=${value//\"/\\\"}
	value=${value//$'\b'/\\b}
	value=${value//$'\f'/\\f}
	value=${value//$'\n'/\\n}
	value=${value//$'\r'/\\r}
	value=${value//$'\t'/\\t}
	printf '%s' "$value"
}

ensure_login() {
	if pass-cli test >/dev/null 2>&1; then
		return 0
	fi
	if [[ -n "${PROTON_PASS_PERSONAL_ACCESS_TOKEN:-}" ]]; then
		log "Logging into Proton Pass CLI with the provided personal access token..."
		pass-cli login --personal-access-token "$PROTON_PASS_PERSONAL_ACCESS_TOKEN"
	else
		log "Logging into Proton Pass CLI..."
		pass-cli login
	fi
	pass-cli test >/dev/null 2>&1 || die "Proton Pass CLI login failed."
}

vault_name_or_default() {
	local vault_name="${1:-$DEFAULT_VAULT_NAME}"
	[[ -n "$vault_name" ]] || die "Vault name cannot be empty."
	printf '%s' "$vault_name"
}

vault_exists() {
	local vault_name="$1"
	pass-cli vault list --output human | grep -Fq "$vault_name"
}

ensure_vault() {
	local vault_name="$1"
	if vault_exists "$vault_name"; then
		return 0
	fi
	log "Creating vault '$vault_name'..."
	pass-cli vault create --name "$vault_name"
}

item_exists() {
	local vault_name="$1"
	local title="$2"
	pass-cli item view --vault-name "$vault_name" --item-title "$title" >/dev/null 2>&1
}

create_empty_custom_item() {
	local vault_name="$1"
	local title="$2"
	cat <<EOF | pass-cli item create custom --vault-name "$vault_name" --from-template -
{
	"title": "$(json_escape "$title")",
	"note": "",
	"sections": [
		{
			"section_name": "Fields",
			"fields": []
		}
	]
}
EOF
}

update_custom_fields() {
	local vault_name="$1"
	local title="$2"
	shift 2
	local -a fields=("$@")
	local -a args=(pass-cli item update --vault-name "$vault_name" --item-title "$title")
	local field

	for field in "${fields[@]}"; do
		[[ -n "$field" ]] || continue
		args+=(--field "$field")
	done

	(( ${#args[@]} > 6 )) || return 0
	"${args[@]}"
}

upsert_custom_item() {
	local vault_name="$1"
	local title="$2"
	shift 2
	local -a fields=("$@")

	if item_exists "$vault_name" "$title"; then
		log "Updating '$title' in '$vault_name'..."
	else
		log "Creating '$title' in '$vault_name'..."
		create_empty_custom_item "$vault_name" "$title"
	fi

	update_custom_fields "$vault_name" "$title" "${fields[@]}"
}

print_help() {
	cat <<'EOF'
MachineState helper for modular values in Proton Pass.

This tool uses custom items and fields only. Each record is a reusable custom
item, and the values live in fields that you choose.

Usage:
  ./machine-state.sh vault ensure [--name NAME]
  ./machine-state.sh vault list
  ./machine-state.sh item list [--name NAME]
  ./machine-state.sh item upsert custom --title TITLE [--name NAME] [--field KEY=VALUE ...]
  ./machine-state.sh item show --title TITLE [--name NAME]
  ./machine-state.sh item get --title TITLE [--field FIELD] [--name NAME]

Conventions:
  value           Use this as the primary field for single-value records.
  any KEY=VALUE   Add more fields for extra machine-specific context.

Examples:
  ./machine-state.sh vault ensure
  ./machine-state.sh item upsert custom --title GitHub Token --field value=ghp_xxx --field kind=github-token
  ./machine-state.sh item upsert custom --title Machine Profile --field value=my-macbook --field hostname=my-macbook.local
  ./machine-state.sh item show --title GitHub Token
  ./machine-state.sh item get --title GitHub Token
  ./machine-state.sh item get --title Machine Profile --field hostname
EOF
}

require_cmd pass-cli
ensure_login

case "${1:-}" in
	vault)
		case "${2:-}" in
			ensure)
				shift 2 || true
				vault_name="$DEFAULT_VAULT_NAME"
				while [[ $# -gt 0 ]]; do
					case "$1" in
						--name)
							vault_name="$(vault_name_or_default "${2:-}")"
							shift 2
							;;
						*)
							die "Unknown option: $1"
							;;
					esac
				done
				ensure_vault "$vault_name"
				;;
			list)
				pass-cli vault list
				;;
			*)
				print_help
				exit 1
				;;
		esac
		;;
	item)
		case "${2:-}" in
			list)
				shift 2 || true
				vault_name="$DEFAULT_VAULT_NAME"
				while [[ $# -gt 0 ]]; do
					case "$1" in
						--name)
							vault_name="$(vault_name_or_default "${2:-}")"
							shift 2
							;;
						*)
							print_help
							exit 1
							;;
					esac
				done
				pass-cli item list --vault-name "$vault_name"
				;;
			upsert)
				[[ "${3:-}" == "custom" ]] || die "Only custom items are supported by this helper."
				shift 3 || true
				vault_name="$DEFAULT_VAULT_NAME"
				title=""
				fields=()
				while [[ $# -gt 0 ]]; do
					case "$1" in
						--name)
							vault_name="$(vault_name_or_default "${2:-}")"
							shift 2
							;;
						--title)
							title="${2:-}"
							shift 2
							;;
						--field)
							fields+=("${2:-}")
							shift 2
							;;
						--help|-h)
							print_help
							exit 0
							;;
						*)
							die "Unknown option: $1"
							;;
					esac
				done
				[[ -n "$title" ]] || die "--title is required."
				ensure_vault "$vault_name"
				upsert_custom_item "$vault_name" "$title" "${fields[@]}"
				;;
			show)
				shift 2 || true
				vault_name="$DEFAULT_VAULT_NAME"
				title=""
				while [[ $# -gt 0 ]]; do
					case "$1" in
						--name)
							vault_name="$(vault_name_or_default "${2:-}")"
							shift 2
							;;
						--title)
							title="${2:-}"
							shift 2
							;;
						*)
							die "Unknown option: $1"
							;;
					esac
				done
				[[ -n "$title" ]] || die "--title is required."
				pass-cli item view --vault-name "$vault_name" --item-title "$title"
				;;
			get)
				shift 2 || true
				vault_name="$DEFAULT_VAULT_NAME"
				title=""
				field="value"
				while [[ $# -gt 0 ]]; do
					case "$1" in
						--name)
							vault_name="$(vault_name_or_default "${2:-}")"
							shift 2
							;;
						--title)
							title="${2:-}"
							shift 2
							;;
						--field)
							field="${2:-}"
							shift 2
							;;
						*)
							die "Unknown option: $1"
							;;
					esac
				done
				[[ -n "$title" ]] || die "--title is required."
				pass-cli item view "pass://$vault_name/$title/$field"
				;;
			*)
				print_help
				exit 1
				;;
		esac
		;;
	-h|--help|help|"")
		print_help
		;;
	*)
		print_help
		exit 1
		;;
esac