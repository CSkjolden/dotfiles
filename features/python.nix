{ ... }:
{
  home-manager.sharedModules = [
    ({ pkgs, ... }: {
      home.packages = [ pkgs.uv ]; # Python environment manager
    })
  ];
}
