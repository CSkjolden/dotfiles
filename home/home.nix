{ pkgs, ... }:
{
  home.packages = [ pkgs.just ];
  imports = [ ./git.nix ];

  home.username = builtins.getEnv "USER";
  home.homeDirectory = "/Users/${builtins.getEnv "USER"}";
  home.stateVersion = "24.11";

  programs.home-manager.enable = true;
}
