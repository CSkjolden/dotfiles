{ pkgs, ... }:
let
  # The only place the user is read from the environment; everything else uses config.system.primaryUser.
  user = builtins.getEnv "USER";
in
{
  imports = [
    ./homebrew.nix
    ./macos.nix
    ./keybinds.nix
    ./nix.nix
  ];

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
