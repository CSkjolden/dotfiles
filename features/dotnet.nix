{ ... }:
{
  home-manager.sharedModules = [
    ({ pkgs, ... }: {
      home.packages = [ pkgs.dotnet-sdk_10 ]; # .NET SDK
    })
  ];

  homebrew.casks = [
    "rider" # JetBrains IDE for dotnet
  ];
}
