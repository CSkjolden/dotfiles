{ ... }:
let
  user = builtins.getEnv "USER";
in
{
  home-manager.users.${user} = {
    imports = [ ../../home/rust.nix ];
    my.flashspace.variant = "personal";
  };
  imports = [
    ../homebrew/personal.nix
    ../homebrew/ai.nix
    ../homebrew/python.nix
    ../homebrew/flutter.nix
    ../homebrew/uni.nix
    ../homebrew/rust.nix
  ];
}
