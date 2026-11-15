{ ... }:
{
  imports = [
    ../darwin/macos.nix
    ../darwin/keybinds.nix

    ../profiles/core.nix
    ../profiles/desktop.nix
    ../profiles/development.nix
    ../profiles/vm.nix

    ../profiles/work-tools.nix
    ../profiles/dotnet.nix
  ];
}
