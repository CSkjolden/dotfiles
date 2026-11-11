{
  description = "dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-darwin = { url = "github:nix-darwin/nix-darwin"; inputs.nixpkgs.follows = "nixpkgs"; };
    home-manager = { url = "github:nix-community/home-manager"; inputs.nixpkgs.follows = "nixpkgs"; };
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    nix-vscode-extensions = { url = "github:nix-community/nix-vscode-extensions"; inputs.nixpkgs.follows = "nixpkgs"; };
    iris = { url = "github:versenilvis/iris"; inputs.nixpkgs.follows = "nixpkgs"; };
  };

  outputs = { nix-darwin, home-manager, nix-homebrew, nix-vscode-extensions, iris, ... }:
    let
      darwinSystem = "aarch64-darwin";

      baseDarwinModules = [
        nix-homebrew.darwinModules.nix-homebrew
        home-manager.darwinModules.home-manager
        {
          nixpkgs.overlays = [
            nix-vscode-extensions.overlays.default
            (final: prev: { iris = iris.packages.${darwinSystem}.default; })
          ];
        }
        ./darwin/configuration.nix
      ];

      mkDarwinConfig = extraModules: nix-darwin.lib.darwinSystem {
        system = darwinSystem;
        modules = baseDarwinModules ++ extraModules;
      };
    in
    {
      darwinConfigurations = {
        personal = mkDarwinConfig [ ./machines/personal.nix ];
        work = mkDarwinConfig [ ./machines/work.nix ];
        mac-studio = mkDarwinConfig [ ./machines/mac-studio.nix ];
      };
    };
}