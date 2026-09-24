{ pkgs, lib, ... }:
let
  stableComponents = [ 
    "clippy" # Lint for common mistakes in Rust code
    "rustfmt" # Rust code formatter
    "rust-src" # Rust source code
    "rust-analyzer" # Language server for Rust
  ];
  stableTargets = [ "aarch64-apple-darwin" "x86_64-apple-darwin" "wasm32-unknown-unknown" ];

  nightlyComponents = [ "rust-src" ];
  nightlyTargets = [ "wasm32-unknown-unknown" ];

  cargoPackages = [  ];

  mkFlags = flag: values: lib.concatStringsSep " " (map (v: "${flag} ${v}") values);
in
{
  home.packages = with pkgs; [
    rustup # Rust toolchain manager

    pkgconf # Package configuration tool
    openssl # SSL/TLS library
    wasm-bindgen-cli # WebAssembly bindings for Rust
    flutter_rust_bridge_codegen # Code generator for Flutter Rust Bridge
    wasm-pack # Build and publish Rust-generated WebAssembly
    typos # Lint for common spelling mistakes in Rust code
    cargo-llvm-cov # Code coverage for Rust projects
    bacon # Build automation tool for Rust
    twiggy # WebAssembly size profiler
    sccache # Shared compilation cache for Rust
    cargo-deny # Check for security vulnerabilities and licensing issues
    cargo-machete # Manage multiple Rust crates in a workspace
    binaryen # wasm-opt
  ];

  home.sessionVariables = {
    OPENSSL_DIR = "${pkgs.openssl.dev}";
    PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
  };

  # rustup's cargo/rustc proxies and `cargo install`ed binaries land here.
  home.sessionPath = [ "$HOME/.cargo/bin" ];

  home.activation.rustupToolchains = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    rustupToolchains() {
      local rustup="${pkgs.rustup}/bin/rustup"
      $DRY_RUN_CMD "$rustup" toolchain install stable ${mkFlags "-c" stableComponents} ${mkFlags "-t" stableTargets}
      $DRY_RUN_CMD "$rustup" toolchain install nightly ${mkFlags "-c" nightlyComponents} ${mkFlags "-t" nightlyTargets}
      $DRY_RUN_CMD "$rustup" default stable

      local cargo="$HOME/.cargo/bin/cargo"
      for pkg in ${lib.concatStringsSep " " cargoPackages}; do
        "$cargo" install --list | grep -q "^$pkg v" || $DRY_RUN_CMD "$cargo" install --locked "$pkg"
      done
    }
    rustupToolchains || echo "rustupToolchains: failed (offline?) - run 'rustup toolchain install stable' manually" >&2
  '';
}