{ pkgs, ... }:
let
  # The only place the user is read from the environment; everything else uses config.system.primaryUser.
  user = builtins.getEnv "USER";
in
{
  imports = [
    ./homebrew.nix
    ./nix.nix
  ];

  launchd.daemons.limit-maxfiles = {
    serviceConfig = {
      Label = "limit.maxfiles";
      ProgramArguments = [ "/bin/launchctl" "limit" "maxfiles" "65536" "524288" ];
      RunAtLoad = true;
    };
  };

  # Must run before nix-homebrew sets up the Intel prefix (enableRosetta).
  system.activationScripts.preActivation.text = ''
    if [ "$(/usr/bin/uname -m)" = "arm64" ] && ! /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
      /usr/sbin/softwareupdate --install-rosetta --agree-to-license
    fi
  '';

  system.activationScripts.postActivation.text = ''
    /bin/launchctl limit maxfiles 65536 524288 || true
  '';

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "backup";
  home-manager.users.${user} = { };

  # vscode itself is unfree; needed since programs.vscode installs it as a package
  nixpkgs.config.allowUnfree = true;

  system.primaryUser = user;
  system.stateVersion = 7;

  users.users.${user}.home = "/Users/${user}";

  fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];

  programs.zsh.enableGlobalCompInit = false;
}
