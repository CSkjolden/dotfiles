{ ... }:
{
  imports = [
    ../darwin/macos.nix
    ../darwin/keybinds.nix

    ../profiles/core.nix
    ../profiles/desktop.nix
    ../profiles/development.nix
    ../profiles/vm.nix

    ../profiles/everyday.nix
    ../profiles/ai.nix
    ../profiles/uni.nix

    ../profiles/flutter.nix
    ../profiles/rust.nix
    ../profiles/python.nix
  ];
}
