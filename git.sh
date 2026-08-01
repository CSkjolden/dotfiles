#!/usr/bin/env zsh
set -euo pipefail

log() {
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

require_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		log "ERROR: $1 is required. Run ./start.sh first."
		exit 1
	fi
}

ensure_gh_login() {
	if gh auth status --hostname github.com >/dev/null 2>&1; then
		return 0
	fi
	log "Logging into GitHub CLI..."
	gh auth login
	gh auth status --hostname github.com >/dev/null 2>&1
}

require_cmd git
require_cmd gh

ensure_gh_login

git_name="$(gh api user --jq '.name // .login // empty')"
git_email="$(gh api user/emails --jq 'map(select(.primary and .verified)) | .[0].email // empty' 2>/dev/null || true)"

git_config_file="$HOME/.gitconfig.local"
mkdir -p "$(dirname "$git_config_file")"

if [[ -z "$git_name" ]]; then
	log "ERROR: Could not determine your GitHub name from gh."
	exit 1
fi

if [[ -z "$git_email" ]]; then
	log "GitHub email was not available from gh; enter the email to use for git commits."
	read -r "git_email?Git email: "
fi

git config --file "$git_config_file" user.name "$git_name"
git config --file "$git_config_file" user.email "$git_email"

gh auth setup-git

log "Git configuration written to $git_config_file"