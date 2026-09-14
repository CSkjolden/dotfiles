{ rust-overlay, ... }:
let
  user = builtins.getEnv "USER";
in
{
  nixpkgs.overlays = [ rust-overlay.overlays.default ];
  home-manager.users.${user}.imports = [ ../../home/rust.nix ];
  imports = [
    ../homebrew/personal.nix
    ../homebrew/ai.nix
    ../homebrew/python.nix
    ../homebrew/flutter.nix
    ../homebrew/uni.nix
    ../homebrew/rust.nix
  ];
}
