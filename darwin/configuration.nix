{ ... }:
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
  home-manager.users.${user} = import ../home/home.nix;

  # Lets determinate Nix manage the Nix install/daemon/nix.conf
  nix.enable = false;

  # vscode itself is unfree; needed since programs.vscode installs it as a package
  nixpkgs.config.allowUnfree = true;

  system.primaryUser = user;
  system.stateVersion = 7;

  users.users.${user}.home = "/Users/${user}";

  # Adds Touch ID sudo
  security.pam.services.sudo_local.touchIdAuth = true;
}
