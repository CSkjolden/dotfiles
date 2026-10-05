{ ... }:
{
  services.sketchybar = {
    enable = true;

    # Thin wrapper (nix makes it executable) that sources the live file in this repo, so edits apply on `sketchybar --reload` without a rebuild.
    config = ''
      #!/bin/sh
      . "$HOME/dotfiles/features/sketchybar/sketchybarrc"
    '';
  };

  # SketchyBar replaces the native menu bar.
  system.defaults.NSGlobalDomain._HIHideMenuBar = true;
}
