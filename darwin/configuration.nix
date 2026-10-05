{ pkgs, ... }:
let
  user = builtins.getEnv "USER";
in
{
  # All profile imports
  imports = [
    ./homebrew/core.nix
    ./homebrew/development.nix
    ./homebrew/vm.nix
    ./macos.nix
    ./keybinds.nix
    ./mos.nix
    ./nix.nix
  ];

  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    inherit user;
    # Adopt the already-installed /opt/homebrew instead of reinstalling.
    autoMigrate = true;
  };

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "backup";
  home-manager.users.${user} = import ../home/home.nix;

  # vscode itself is unfree; needed since programs.vscode installs it as a package
  nixpkgs.config.allowUnfree = true;

  system.primaryUser = user;
  system.stateVersion = 7;

  users.users.${user}.home = "/Users/${user}";

  fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];

  programs.zsh.enableGlobalCompInit = false;
}
