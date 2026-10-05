{ pkgs, ... }:
let
  user = builtins.getEnv "USER";
in
{
  home-manager.users.${user} = {
    my.flashspace.variant = "work";
    home.packages = [ pkgs.powershell ];
  };
  imports = [
    ../homebrew/work.nix
    ../homebrew/dotnet.nix
  ];
}
