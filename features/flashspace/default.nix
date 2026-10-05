{ ... }:
{
  homebrew.casks = [
    "flashspace" # Fast virtual workspace manager for macOS
  ];

  home-manager.sharedModules = [
    ({ config, lib, ... }:
      let
        cfg = config.my.flashspace;
        dir = "${config.home.homeDirectory}/dotfiles/features/flashspace";
        link = path: config.lib.file.mkOutOfStoreSymlink "${dir}/${path}";
      in
      {
        options.my.flashspace.variant = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Subdirectory of features/flashspace holding this machine's profiles.toml.";
        };

        config = lib.mkIf (cfg.variant != null) {
          xdg.configFile = {
            "flashspace/settings.toml".source = link "settings.toml";
            "flashspace/profiles.toml".source = link "${cfg.variant}/profiles.toml";
          };
        };
      })
  ];
}
