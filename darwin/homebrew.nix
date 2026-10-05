{ config, ... }:
{
  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    user = config.system.primaryUser;
    # Adopt the already-installed /opt/homebrew instead of reinstalling.
    autoMigrate = true;
  };

  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = false;
      upgrade = true;
      extraFlags = [ "--verbose" ];
    };
  };
}
