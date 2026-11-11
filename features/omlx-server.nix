{ config, lib, pkgs, ... }:
let
  cfg = config.services.omlx;
  user = config.system.primaryUser;

  modelsDir = "${cfg.storageDir}/models";
  kvCacheDir = "${cfg.storageDir}/omlx_kv_cache";
  apiKeyPath = "/var/lib/omlx/api_key";

  syncScript = pkgs.writeShellScriptBin "sync-ai-models" ''
    set -euo pipefail

    STORAGE_DIR="${cfg.storageDir}"
    MODELS_DIR="${modelsDir}"
    KV_DIR="${kvCacheDir}"

    echo "=== oMLX AI Model Synchronizer ==="

    if [ ! -d "$STORAGE_DIR" ]; then
      echo "ERROR: Storage directory '$STORAGE_DIR' is not mounted!" >&2
      echo "Please attach the external SSD before running sync-ai-models." >&2
      exit 1
    fi

    mkdir -p "$MODELS_DIR" "$KV_DIR"

    TARGET_MODELS=(
      ${builtins.concatStringsSep "\n      " (map (m: ''"${m}"'') cfg.models)}
    )

    if [ $# -gt 0 ]; then
      TARGET_MODELS=("$@")
    fi

    for repo in "''${TARGET_MODELS[@]}"; do
      model_name="$(basename "$repo")"
      dest_dir="$MODELS_DIR/$model_name"
      if [ -f "$dest_dir/config.json" ]; then
        echo ">>> Model $repo is already present at $dest_dir (verifying integrity...)"
      else
        echo ""
        echo ">>> Downloading $repo into $dest_dir ..."
      fi

      ${pkgs.uv}/bin/uvx --from "huggingface_hub" hf download \
        "$repo" \
        --local-dir "$dest_dir"
      echo ">>> Verified $repo."
    done

    echo ""
    echo "=== Model sync complete! ==="
    echo "Current models in $MODELS_DIR:"
    ls -1 "$MODELS_DIR"

    echo ""
    echo "Reloading oMLX server to register newly downloaded models..."
    /bin/launchctl kickstart -k system/ai.omlx.server 2>/dev/null || true
  '';

  tokenScript = pkgs.writeShellScriptBin "omlx-token" ''
    set -euo pipefail
    if [ -f "${apiKeyPath}" ]; then
      cat "${apiKeyPath}"
    else
      echo "API key not generated yet. The daemon will create it upon start." >&2
      exit 1
    fi
  '';

  statusScript = pkgs.writeShellScriptBin "omlx-status" ''
    set -euo pipefail
    echo "=== oMLX Server Status ==="
    if ! curl -s -f -o /dev/null "http://127.0.0.1:${toString cfg.port}/health" 2>/dev/null; then
      echo "Status: STOPPED (http://127.0.0.1:${toString cfg.port} is not responding)"
      echo "Check logs: tail -n 20 /var/log/omlx.err.log"
      exit 1
    fi

    echo "Status: ONLINE"
    echo "Host:   ${cfg.host}:${toString cfg.port}"
    echo ""
    echo "--- Available Models ---"
    MODELS="$(curl -s "http://127.0.0.1:${toString cfg.port}/v1/models" | ${pkgs.jq}/bin/jq -r '.data[].id' 2>/dev/null || true)"
    if [ -n "$MODELS" ]; then
      echo "$MODELS"
    else
      echo "No models registered yet. Try restarting the server to rescan: sudo launchctl kickstart -k system/ai.omlx.server"
    fi
  '';

  mergedSettings = lib.recursiveUpdate {
    version = "1.0";
    auth = {
      allow_unauthenticated_inference = cfg.auth.allowUnauthenticatedInference;
    };
    idle_timeout = {
      idle_timeout_seconds = 0; # Never unload models due to inactivity on dedicated server
    };
    integrations = {
      markitdown_enabled = cfg.integrations.markitdown.enable;
      markitdown_max_file_size_mb = cfg.integrations.markitdown.maxFileSizeMb;
      markitdown_max_files_per_request = cfg.integrations.markitdown.maxFilesPerRequest;
      markitdown_pdf_processing_engine = cfg.integrations.markitdown.pdfEngine;
      web_search_provider = cfg.integrations.webSearch.provider;
      web_search_max_results = cfg.integrations.webSearch.maxResults;
      web_search_content_mode = cfg.integrations.webSearch.contentMode;
      splash_kv_format = cfg.integrations.splash.kvPrecision;
      splash_ane_prefill = cfg.integrations.splash.neuralEnginePrefill;
    };
  } cfg.extraSettings;

  pinnedModelRecords = lib.genAttrs (map (m: builtins.baseNameOf m) cfg.pinnedModels) (_: {
    is_pinned = true;
  });

  mergedModelSettings = {
    version = 1;
    models = pinnedModelRecords;
  };
in
{
  imports = [
    ./omlx.nix
  ];

  options.services.omlx = {
    enable = lib.mkEnableOption "oMLX headless neural compute server";

    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Network interface to bind (0.0.0.0 for all interfaces).";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      description = "Port to listen on for OpenAI-compatible inference.";
    };

    storageDir = lib.mkOption {
      type = lib.types.str;
      default = "/Volumes/StudioStorage";
      description = "Path to the dedicated external storage mount.";
    };

    models = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "Jundot/d3-nano-oQ8e"
        "Jundot/Qwen3.6-35B-A3B-oQ4e-mtp"
      ];
      description = "Hugging Face model repositories to declaratively maintain on the external storage.";
    };

    pinnedModels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "Jundot/Qwen3.6-35B-A3B-oQ4e-mtp"
      ];
      description = "Models to pre-load on boot and pin permanently in unified memory (never evicted).";
    };

    hotCacheGb = lib.mkOption {
      type = lib.types.int;
      default = 8;
      description = "RAM cache size in GB for hot prefix KV blocks on Apple Silicon.";
    };

    ssdCacheGb = lib.mkOption {
      type = lib.types.int;
      default = 250;
      description = "Max SSD tiered KV cache size in GB allocated on the external storage.";
    };

    initialCacheBlocks = lib.mkOption {
      type = lib.types.int;
      default = 512;
      description = "Pre-allocated Metal cache blocks at startup for deep context stability.";
    };

    maxConcurrentRequests = lib.mkOption {
      type = lib.types.int;
      default = 4;
      description = "Maximum concurrent inference requests.";
    };

    memoryGuard = lib.mkOption {
      type = lib.types.enum [ "off" "safe" "balanced" "aggressive" ];
      default = "balanced";
      description = "Memory guard tier for macOS unified memory pressure management.";
    };

    auth = {
      allowUnauthenticatedInference = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Allow nodes on the local LAN or Tailnet to query inference without API key.";
      };
    };

    integrations = {
      markitdown = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Preprocess supported file attachments before LLM requests.";
        };
        maxFileSizeMb = lib.mkOption {
          type = lib.types.int;
          default = 25;
          description = "Max file size in MB for document attachments.";
        };
        maxFilesPerRequest = lib.mkOption {
          type = lib.types.int;
          default = 5;
          description = "Limit document attachments converted in one request.";
        };
        pdfEngine = lib.mkOption {
          type = lib.types.str;
          default = "markitdown";
          description = "PDF processing engine.";
        };
      };

      webSearch = {
        provider = lib.mkOption {
          type = lib.types.str;
          default = "ddgs";
          description = "Search provider (ddgs = DDGS Total queries all engines without keys).";
        };
        maxResults = lib.mkOption {
          type = lib.types.int;
          default = 3;
          description = "Number of sources web search returns.";
        };
        contentMode = lib.mkOption {
          type = lib.types.enum [ "snippet" "full" ];
          default = "snippet";
          description = "Search result content mode.";
        };
      };

      splash = {
        kvPrecision = lib.mkOption {
          type = lib.types.enum [ "int8" "bf16" ];
          default = "int8";
          description = "KV cache precision for external Splash engine.";
        };
        neuralEnginePrefill = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Let Splash run part of long prompts on the Neural Engine.";
        };
      };
    };

    extraSettings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Arbitrary settings to deep-merge into ~/.omlx/settings.json.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      syncScript
      tokenScript
      statusScript
    ];

    # Background model sync service: runs once on boot or activation without blocking server startup
    launchd.daemons.omlx-sync = {
      serviceConfig = {
        Label = "ai.omlx.models-sync";
        UserName = user;
        ProgramArguments = [
          "/bin/sh"
          "-c"
          ''
            set -euo pipefail

            if [ ! -d "${cfg.storageDir}" ]; then
              echo "[omlx-sync] Storage directory ${cfg.storageDir} is not mounted. Skipping sync." >&2
              exit 0
            fi

            exec ${syncScript}/bin/sync-ai-models
          ''
        ];
        RunAtLoad = true;
        StandardOutPath = "/var/log/omlx-sync.log";
        StandardErrorPath = "/var/log/omlx-sync.log";
        EnvironmentVariables = {
          HOME = "/Users/${user}";
          PATH = "/opt/homebrew/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        };
      };
    };

    # Core 24/7 inference server daemon
    launchd.daemons.omlx = {
      serviceConfig = {
        Label = "ai.omlx.server";
        UserName = user;
        ProgramArguments = [
          "/bin/sh"
          "-c"
          ''
            set -euo pipefail

            # Wait for storage mount
            if [ ! -d "${cfg.storageDir}" ]; then
              echo "[omlx] ${cfg.storageDir} not mounted. Waiting..." >&2
              exit 1
            fi

            mkdir -p /var/lib/omlx "${modelsDir}" "${kvCacheDir}"

            if [ ! -f "${apiKeyPath}" ]; then
              /usr/bin/openssl rand -hex 24 > "${apiKeyPath}"
              chmod 600 "${apiKeyPath}"
            fi

            API_KEY="$(cat "${apiKeyPath}")"

            # Execute oMLX server with Apple Silicon and SSD cache tuning
            exec /opt/homebrew/bin/omlx serve \
              --host "${cfg.host}" \
              --port "${toString cfg.port}" \
              --headless \
              --model-dir "${modelsDir}" \
              --paged-ssd-cache-dir "${kvCacheDir}" \
              --paged-ssd-cache-max-size "${toString cfg.ssdCacheGb}GB" \
              --hot-cache-max-size "${toString cfg.hotCacheGb}GB" \
              --hot-cache-write-through \
              --initial-cache-blocks "${toString cfg.initialCacheBlocks}" \
              --max-concurrent-requests "${toString cfg.maxConcurrentRequests}" \
              --memory-guard "${cfg.memoryGuard}" \
              --api-key "$API_KEY"
          ''
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/var/log/omlx.log";
        StandardErrorPath = "/var/log/omlx.err.log";
        EnvironmentVariables = {
          OMLX_HEADLESS = "1";
          HOME = "/Users/${user}";
          PATH = "/opt/homebrew/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        };
      };
    };

    system.activationScripts.postActivation.text = ''
      # Ensure permissions for non-root execution by primary user
      mkdir -p /var/lib/omlx
      chown -R ${user}:staff /var/lib/omlx
      chmod 700 /var/lib/omlx

      touch /var/log/omlx.log /var/log/omlx.err.log /var/log/omlx-sync.log
      chown ${user}:staff /var/log/omlx.log /var/log/omlx.err.log /var/log/omlx-sync.log

      # Non-destructively deep-merge integrations & auth settings into ~/.omlx/settings.json
      SETTINGS_DIR="/Users/${user}/.omlx"
      SETTINGS_FILE="$SETTINGS_DIR/settings.json"
      mkdir -p "$SETTINGS_DIR"

      NIX_SETTINGS='${builtins.toJSON mergedSettings}'
      if [ -f "$SETTINGS_FILE" ]; then
        ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$SETTINGS_FILE" <(echo "$NIX_SETTINGS") > "$SETTINGS_FILE.tmp"
        mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
      else
        echo "$NIX_SETTINGS" > "$SETTINGS_FILE"
      fi

      # Deep-merge pinned model settings into ~/.omlx/model_settings.json
      MODEL_SETTINGS_FILE="$SETTINGS_DIR/model_settings.json"
      NIX_MODEL_SETTINGS='${builtins.toJSON mergedModelSettings}'
      if [ -f "$MODEL_SETTINGS_FILE" ]; then
        ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$MODEL_SETTINGS_FILE" <(echo "$NIX_MODEL_SETTINGS") > "$MODEL_SETTINGS_FILE.tmp"
        mv "$MODEL_SETTINGS_FILE.tmp" "$MODEL_SETTINGS_FILE"
      else
        echo "$NIX_MODEL_SETTINGS" > "$MODEL_SETTINGS_FILE"
      fi

      chown -R ${user}:staff "$SETTINGS_DIR"
      chmod 600 "$SETTINGS_FILE" "$MODEL_SETTINGS_FILE"

      # Kickstart services immediately after switch
      /bin/launchctl kickstart -k system/ai.omlx.server || true
      /bin/launchctl kickstart -k system/ai.omlx.models-sync || true
    '';
  };
}
