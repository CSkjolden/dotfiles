{ ... }:
{
  home-manager.sharedModules = [
    ({ pkgs, ... }: {
      home.packages = [ pkgs.powershell ]; # Cross-platform shell and scripting language
    })
  ];
}
