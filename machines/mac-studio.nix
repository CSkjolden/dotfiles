{ ... }:
{
  imports = [
    ../darwin/mac-studio.nix

    ../profiles/core.nix
    ../profiles/server.nix
    ../features/omlx-server.nix
  ];

  services.omlx = {
    enable = true;
    storageDir = "/Volumes/StudioStorage";
    maxConcurrentRequests = 4;
    models = [
      "Jundot/d3-nano-oQ8e"
      "Jundot/Qwen3.6-35B-A3B-oQ4e-mtp"
    ];
  };
}
