{ pkgs, ... }:
{
  home.packages = [ 
    pkgs.just # A better make command
    pkgs.devenv # Create development environments
    pkgs.gitleaks # Secret scanning in the pre-commit hook
     ];
  imports = [ ./git.nix ./shell.nix ];

  home.stateVersion = "24.11";

  programs.home-manager.enable = true;
}
