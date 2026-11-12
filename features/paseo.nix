{ ... }:
let
  # Merged into ~/.paseo/config.json; Paseo and its CLI also write that file
  # (password, relay, paired devices), so it must stay writable.
  paseoSettings = {
    agents = {
      # Pi starts MCP servers, extension packages and the model endpoint before
      # answering RPCs; the 60s default is tight on a cold local model.
      providers.pi.options.rpcTimeoutMs = 120000;
      # Catalog refresh covers Pi's package and extension loading.
      catalogRefreshTimeoutMs = 180000;
    };
  };
in
{
  homebrew.casks = [
    "paseo" # Self-hosted daemon for AI coding agents
  ];

  home-manager.sharedModules = [
    ({ pkgs, lib, config, ... }: {
      home.activation.paseoConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        config="${config.home.homeDirectory}/.paseo/config.json"
        mkdir -p "$(dirname "$config")"
        [ -f "$config" ] || echo '{ "version": 1 }' > "$config"
        ${pkgs.jq}/bin/jq --argjson s '${builtins.toJSON paseoSettings}' '. * $s' "$config" > "$config.tmp" \
          && chmod 600 "$config.tmp" && mv "$config.tmp" "$config"
      '';
    })
  ];
}
