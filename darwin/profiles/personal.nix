{ pkgs, ... }:
let
  user = builtins.getEnv "USER";
in
{
  home-manager.users.${user} = {
    imports = [ ../../home/rust.nix ];
    my.flashspace.variant = "personal";
    home.packages = [ pkgs.uv ]; # Python environment manager
  };
  imports = [
    ../homebrew/personal.nix
    ../homebrew/ai.nix
    ../homebrew/flutter.nix
    ../homebrew/uni.nix
    ../homebrew/rust.nix
  ];
}
