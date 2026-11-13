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
          '.packages = ((.packages // []) + $pkgs | unique)
           | .defaultProvider = (.defaultProvider // "omlx")
           | .defaultModel = (.defaultModel // "Qwen3.6-35B-A3B-oQ4e-mtp")
           | .defaultThinkingLevel = (.defaultThinkingLevel // "medium")
           | del(.defaultTools)
           | .thinkingBudgets = ({ minimal: 512, low: 1024, medium: 2048, high: 8192 } * (.thinkingBudgets // {}))' \
          "$settings" > "$settings.tmp" \
          && mv "$settings.tmp" "$settings"
      '';

      # Global user-level instructions (~85 tokens) loaded into every Pi session.
      home.file.".pi/agent/AGENTS.md".text = ''
        - Search with `rg -n` before reading large files; use `read` with `offset` and `limit` instead of reading whole files over 200 lines.
        - Use unescaped `|` for alternation in `rg` (`rg -n "foo|bar"`), never `\|`.
        - For `edit`, always pass `path` as a top-level parameter (`{"path": "...", "edits": [{"oldText": "...", "newText": "..."}]}`), never inside `edits[]`.
        - Pass quiet flags (`-q` / `--quiet`) to test and build runners, and pipe large command outputs (`git diff`, `git log`) through `rg`, `head`, or `tail`.
        - Never stage, diff, or list generated build or dependency directories.
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
        trackCommands = [ "cargo" "docker" "just" "darwin-rebuild" "git" ];
      };

      home.file.".pi/agent/models.json".source = (pkgs.formats.json { }).generate "pi-models.json" {
        "$schema" = "https://pi.dev/schemas/models.schema.json";
        providers.omlx = {
          name = "oMLX (Mac Studio)";
          baseUrl = "http://skjolds-mac-studio:8000/v1";
          api = "openai-completions";
          apiKey = "omlx"; # dummy key; local server ignores it
          models = [
            {
              id = "Qwen3.6-35B-A3B-oQ4e-mtp";
              name = "Qwen 3.6 35B-A3B (Mac Studio)";
              reasoning = true;
              input = [ "text" "image" ];
              contextWindow = 122880; # 120 Ki tokens (60 x 2048-token blocks; leaves ~95k working room above Paseo's ~25k base prompt while compacting well below oMLX's 150k cap)
              maxTokens = 32768;
              compat = {
                thinkingFormat = "chat-template";
                chatTemplateKwargs = {
                  enable_thinking = { "$var" = "thinking.enabled"; };
                };
                thinkingTokenBudgetField = "thinking_budget";
              };
            }
          ];
        };
      };
    })
  ];
}
