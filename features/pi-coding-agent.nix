{ ... }:
let
  # Pi package sources, e.g. "npm:@scope/pi-tools@1.0.0" or "git:github.com/user/repo@v1".
  # Pin versions: unpinned sources are re-checked on every start.
  piPackages = [
    "npm:@juicesharp/rpiv-ask-user-question@2.15.0"
    "npm:@juicesharp/rpiv-todo@2.15.0"
    "npm:pi-subagents@0.88.0"
    "npm:@sting8k/pi-vcc@0.11.2"
  ];
in
{
  homebrew.brews = [
    "pi-coding-agent" # Minimal terminal coding agent (pi.dev)
  ];

  # Only models.json is managed: pi rewrites settings.json and auth.json itself
  # (/model, /login), so those must stay writable and out of the nix store.
  home-manager.sharedModules = [
    ({ pkgs, lib, config, ... }: {
      # Merge declared packages into the writable settings.json; pi installs
      # them itself on next start or /reload.
      home.activation.piPackages = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        settings="${config.home.homeDirectory}/.pi/agent/settings.json"
        mkdir -p "$(dirname "$settings")"
        [ -f "$settings" ] || echo '{}' > "$settings"
        ${pkgs.jq}/bin/jq --argjson pkgs '${builtins.toJSON piPackages}' \
          '.packages = ((.packages // []) + $pkgs | unique)' "$settings" > "$settings.tmp" \
          && mv "$settings.tmp" "$settings"
      '';

      # No-LLM compaction: no summarization prompt reaches the model server,
      # so only the unavoidable prefix rewrite at a cut can miss the KV cache.
      home.file.".pi/agent/pi-vcc-config.json".source = (pkgs.formats.json { }).generate "pi-vcc-config.json" {
        overrideDefaultCompaction = true;
        smartKeepTail = true;
        continueAfterThresholdCompact = true;
        debug = false;
        skipForProviders = [ ];
        skipCustomTypes = [ ];
        trackCommands = [ "docker" "just" "darwin-rebuild" "git" ];
      };

      home.file.".pi/agent/models.json".source = (pkgs.formats.json { }).generate "pi-models.json" {
        "$schema" = "https://pi.dev/schemas/models.schema.json";
        providers.omlx = {
          baseUrl = "http://localhost:8000/v1";
          api = "openai-completions";
          apiKey = "omlx"; # dummy key; local server ignores it
        };
      };
    })
  ];
}
