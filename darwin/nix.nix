{ pkgs, ... }:
{
  # Lets determinate Nix manage the Nix install/daemon/nix.conf
  nix.enable = false;

  # Nixd's managed GC only runs when the disk is nearly full; use a fixed retention instead.
  environment.etc."determinate/config.json".text = builtins.toJSON {
    garbageCollector.strategy = "disabled";
  };

  launchd.daemons.nix-gc = {
    serviceConfig = {
      Label = "nix.gc";
      ProgramArguments = [
        "/bin/sh" "-c"
        "${pkgs.nh}/bin/nh clean all --keep-since 30d --keep 5 && /nix/var/nix/profiles/default/bin/nix store optimise"
      ];
      EnvironmentVariables.PATH = "/nix/var/nix/profiles/default/bin:/usr/bin:/bin";
      StartCalendarInterval = [ { Weekday = 0; Hour = 3; Minute = 0; } ];
      StandardErrorPath = "/var/log/nix-gc.log";
      StandardOutPath = "/var/log/nix-gc.log";
    };
  };
}
