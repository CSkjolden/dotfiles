#!/usr/bin/env zsh
set -euo pipefail

log() {
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

is_installed() {
	command -v "$1" >/dev/null 2>&1
}

ensure_line_in_file() {
	local line="$1"
	local file="$2"
	if ! grep -Fqx "$line" "$file" 2>/dev/null; then
		echo "$line" >> "$file"
	fi
}

if ! is_installed brew; then
	log "ERROR: Homebrew is required. Run ./start.sh first."
	exit 1
fi

BREW_PREFIX="$(brew --prefix)"
eval "$("${BREW_PREFIX}/bin/brew" shellenv)"

if ! is_installed rustup; then
	log "Installing rustup via official installer..."
	curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
	. "$HOME/.cargo/env"
fi

CARGO_BIN_LINE='export PATH="$HOME/.cargo/bin:$PATH"'
ensure_line_in_file "$CARGO_BIN_LINE" ~/.zprofile
export PATH="$HOME/.cargo/bin:$PATH"

if ! command -v rustup >/dev/null 2>&1; then
	log "ERROR: rustup is still not available in PATH after setup."
	exit 1
fi

rustup toolchain install stable
rustup toolchain install nightly
rustup default stable

if ! command -v cargo >/dev/null 2>&1; then
	log "ERROR: cargo is not available in PATH after rustup bootstrap."
	exit 1
fi

log "Installing native build prerequisites..."
brew install pkgconf openssl@3 sccache rustrover >/dev/null
OPENSSL_PREFIX="$(brew --prefix openssl@3)"
export OPENSSL_DIR="$OPENSSL_PREFIX"
export PKG_CONFIG_PATH="$OPENSSL_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

log "Updating Rust toolchain..."
rustup update stable

log "Installing Rust components..."
rustup component add clippy rustfmt rust-analyzer rust-src llvm-tools-preview

log "Adding WASM compile target..."
rustup target add wasm32-unknown-unknown

log "Installing wasm-pack..."
brew install wasm-pack >/dev/null

install_cargo_crate() {
	local crate="$1"
	local installed_version
	local latest_version

	installed_version="$(cargo install --list | sed -n "s/^${crate} v\([0-9][^:]*\):$/\1/p" | head -n 1)"
	latest_version="$(cargo search "^${crate}$" --limit 1 | sed -n "s/^${crate} = \"\([^\"]*\)\".*/\1/p")"

	if [[ -z "$latest_version" ]]; then
		log "Unable to resolve latest version for ${crate}; skipping."
		return
	fi

	if [[ -z "$installed_version" ]]; then
		log "Installing ${crate} ${latest_version}..."
		cargo install --locked "$crate"
		return
	fi

	if [[ "$installed_version" == "$latest_version" ]]; then
		log "${crate} is up to date (${installed_version})."
		return
	fi

	log "Updating ${crate} ${installed_version} -> ${latest_version}..."
	cargo install --locked --force "$crate"
}

log "Installing Cargo utilities..."
install_cargo_crate cargo-watch
install_cargo_crate cargo-nextest
install_cargo_crate cargo-audit
install_cargo_crate cargo-edit
install_cargo_crate cargo-expand
install_cargo_crate cargo-deny
install_cargo_crate cargo-outdated
install_cargo_crate cargo-machete
install_cargo_crate bacon

if [[ "$(uname -s)" == "Darwin" ]]; then
	install_cargo_crate cargo-llvm-cov
fi

log "Recommended next step: configure sccache + faster linker per project in .cargo/config.toml"

log "Rust setup complete."