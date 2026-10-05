{ ... }:
{
  imports = [
    ../profiles/core.nix
    ../profiles/development.nix
    ../profiles/vm.nix

    ../profiles/work-tools.nix
    ../profiles/dotnet.nix
  ];

  home-manager.sharedModules = [ { my.flashspace.variant = "work"; } ];
}
