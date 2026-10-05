{ ... }:
{
  homebrew.casks = [
    "visual-studio-code" # Visual Studio Code
  ];

  home-manager.sharedModules = [
    ({ pkgs, ... }: {
      programs.vscode = {
        enable = true;
        # Homebrew owns the app; wrap its CLI so Nix can still regen extensions.json
        package = pkgs.writeShellScriptBin "code" ''exec /opt/homebrew/bin/code "$@"'';
        profiles.default.userSettings = {
          "files.autoSave" = "afterDelay";
          "terminal.external.osxExec" = "Ghostty.app";
          "terminal.integrated.initialHint" = false;
          "terminal.integrated.fontFamily" = "JetBrainsMono Nerd Font";
          "terminal.integrated.macOptionIsMeta" = true;
          "terminal.integrated.enableVisualBell" = true;
          "accessibility.signals.terminalBell" = { sound = "off"; };
        };
        profiles.default.extensions = with pkgs.nix-vscode-extensions.vscode-marketplace; [
          dnicolson.binary-plist # Easily edit plist files
          skellock.just # Justfile support for VS Code
          bbenoist.nix # Nix language support for VS Code
        ];
      };
    })
  ];
}
