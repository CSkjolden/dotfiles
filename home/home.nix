{ pkgs, ... }:
{
  home.packages = [ 
    pkgs.just # A better make command
    pkgs.devenv # Create development environments
     ];
  imports = [ ./git.nix ];

  home.username = builtins.getEnv "USER";
  home.homeDirectory = "/Users/${builtins.getEnv "USER"}";
  home.stateVersion = "24.11";

  programs.home-manager.enable = true;
  programs.vscode = {
    enable = true;
    # Homebrew owns the app; wrap its CLI so Nix can still regen extensions.json
    package = pkgs.writeShellScriptBin "code" ''exec /opt/homebrew/bin/code "$@"'';
    profiles.default.extensions = with pkgs.nix-vscode-extensions.vscode-marketplace; [
      dnicolson.binary-plist # Easily edit plist files
      skellock.just # Justfile support for VS Code
      bbenoist.nix # Nix language support for VS Code
    ];
  };
}
