{
  description = "dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-darwin = { url = "github:nix-darwin/nix-darwin"; inputs.nixpkgs.follows = "nixpkgs"; };
    home-manager = { url = "github:nix-community/home-manager"; inputs.nixpkgs.follows = "nixpkgs"; };
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    nix-vscode-extensions = { url = "github:nix-community/nix-vscode-extensions"; inputs.nixpkgs.follows = "nixpkgs"; };
  };

  outputs = { nix-darwin, home-manager, nix-homebrew, nix-vscode-extensions, ... }:
    let
      system = "aarch64-darwin";

      baseModules = [
        nix-homebrew.darwinModules.nix-homebrew
        home-manager.darwinModules.home-manager
        { nixpkgs.overlays = [ nix-vscode-extensions.overlays.default ]; }
        ./darwin/configuration.nix
      ];

      mkDarwinConfig = extraModules: nix-darwin.lib.darwinSystem {
        inherit system;
        modules = baseModules ++ extraModules;
      };
    in
    {
      darwinConfigurations = {
        personal = mkDarwinConfig [ ./darwin/profiles/personal.nix ];
        work = mkDarwinConfig [ ./darwin/profiles/work.nix ];
      };
    };
}