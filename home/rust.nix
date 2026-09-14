{ pkgs, ... }:
{
  home.packages = with pkgs; [
    (rust-bin.stable.latest.default.override {
      extensions = [ "clippy" "rustfmt" "rust-src" "rust-analyzer" ];
    })

    pkgconf
    openssl
  ];

  home.sessionVariables = {
    OPENSSL_DIR = "${pkgs.openssl.dev}";
    PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
  };
}
