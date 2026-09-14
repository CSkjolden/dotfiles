{
  description = "dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-darwin = { url = "github:nix-darwin/nix-darwin"; inputs.nixpkgs.follows = "nixpkgs"; };
    home-manager = { url = "github:nix-community/home-manager"; inputs.nixpkgs.follows = "nixpkgs"; };
    rust-overlay = { url = "github:oxalica/rust-overlay"; inputs.nixpkgs.follows = "nixpkgs"; };
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
  };

  outputs = { nix-darwin, home-manager, rust-overlay, nix-homebrew, ... }:
    let
      system = "aarch64-darwin";

      baseModules = [
        nix-homebrew.darwinModules.nix-homebrew
        home-manager.darwinModules.home-manager
        ./darwin/configuration.nix
      ];

      mkDarwinConfig = extraModules: nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = { inherit rust-overlay; };
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