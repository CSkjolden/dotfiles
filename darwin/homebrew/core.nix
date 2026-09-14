{ ... }:
{
  homebrew = {
    enable = true;

    casks = [
      "visual-studio-code" # Open-source code editor
      "vorssaint" # Menu bar toolkit with keep-awake, system monitor and volume mixer
      "mos"
      "displaylink"
    ];

    vscode = [
      "dnicolson.binary-plist"
      "skellock.just"
      "bbenoist.nix"
    ];
  };
}
