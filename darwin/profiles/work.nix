{ ... }:
let
  user = builtins.getEnv "USER";
in
{
  home-manager.users.${user}.my.flashspace.variant = "work";
  imports = [
    ../homebrew/work.nix
    ../homebrew/dotnet.nix
  ];
}
