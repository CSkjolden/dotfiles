{ ... }:
{
  imports = [
    ../features/python.nix
    ../features/tailscale-daemon.nix
  ];

  home-manager.sharedModules = [
    ({ pkgs, ... }: {
      home.packages = with pkgs; [
        curl
        ffmpeg
        htop
      ];
    })
  ];
}
