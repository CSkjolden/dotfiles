{ config, lib, pkgs, ... }:
let
  aiCfg = config.services.aiServer;
  cfg = aiCfg.omlx;
  user = config.system.primaryUser;

  modelsDir = "${aiCfg.storageDir}/models";
  kvCacheDir = "${aiCfg.storageDir}/omlx_kv_cache";
  apiKeyPath = "/var/lib/omlx/api_key";
  daemonPath = "/opt/homebrew/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";

  tokenScript = pkgs.writeShellScriptBin "omlx-token" ''
    set -euo pipefail
    if [ -f "${apiKeyPath}" ]; then
      cat "${apiKeyPath}"
    else
      echo "API key not generated yet. The daemon will create it upon start." >&2
      exit 1
    fi
  '';

  defaultSettings = {
    version = "1.0";
    server = {
      burst_decode_mode = "balanced";
      preserve_mid_system_cache = true;
      gpu_keep_warm_interval = 0.5;
    };
    model = {
      model_dirs = [ modelsDir ];
      model_dir = modelsDir;
    };
    memory = {
      prefill_memory_guard = true;
      memory_guard_tier = if cfg.memoryGuardGb != null then "custom" else cfg.memoryGuard;
      memory_guard_custom_ceiling_gb = if cfg.memoryGuardGb != null then cfg.memoryGuardGb else 0.0;
      soft_threshold = 0.92;
      hard_threshold = 0.97;
      prefill_safe_zone_ratio = 0.92;
      prefill_min_chunk_tokens = 32;
    };
    scheduler = {
      max_concurrent_requests = cfg.maxConcurrentRequests;
      chunked_prefill = true;
      decode_fairness = true;
      prefill_priority = "context";
    };
    cache = {
      enabled = true;
      ssd_cache_dir = kvCacheDir;
      ssd_cache_max_size = "${toString cfg.ssdCacheGb}GB";
      hot_cache_max_size = "${toString cfg.hotCacheGb}GB";
      hot_cache_write_through = true;
      initial_cache_blocks = cfg.initialCacheBlocks;
    };
    auth = {
      allow_unauthenticated_inference = cfg.allowUnauthenticatedInference;
    };
    idle_timeout = {
      idle_timeout_seconds = 0;
    };
    integrations = {
      markitdown_enabled = true;
      markitdown_max_file_size_mb = 25;
      markitdown_max_files_per_request = 5;
      markitdown_pdf_processing_engine = "markitdown";
      web_search_provider = "ddgs";
      web_search_max_results = 3;
      web_search_content_mode = "snippet";
      splash_kv_format = "int8";
      splash_ane_prefill = false;
    };
  };

  mergedSettings = lib.recursiveUpdate defaultSettings cfg.settings;

  defaultModelName = if cfg.defaultModel != null then builtins.baseNameOf cfg.defaultModel else null;
  pinnedNames = map builtins.baseNameOf cfg.pinnedModels;
  allModelNames = lib.unique ((map builtins.baseNameOf cfg.models) ++ pinnedNames);

  pinnedModelRecords = lib.genAttrs allModelNames (name:
    { is_pinned = builtins.elem name pinnedNames; }
    // lib.optionalAttrs (name == defaultModelName) {
      is_default = true;
      mtp_enabled = true;
      turboquant_kv_enabled = true;
      turboquant_kv_scheme = "affine8";
      turboquant_kv_bits = 8;
      turboquant_skip_last = true;
    }
  );

  mergedModelSettings = {
    version = 1;
    models = pinnedModelRecords;
  };
in
{
  imports = [
    ../omlx.nix
  ];

  options.services.aiServer.omlx = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable oMLX headless Metal GPU inference server.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      description = "Port for OpenAI-compatible LLM and SystemOne inference.";
    };

    models = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Hugging Face model repositories maintained in the oMLX models directory.";
    };

    pinnedModels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Models pre-loaded on boot and pinned permanently in unified memory.";
    };

    defaultModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Primary LLM marked as default (with native MTP enabled).";
    };

    hotCacheGb = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = "RAM cache size in GB for hot prefix KV blocks.";
    };

    ssdCacheGb = lib.mkOption {
      type = lib.types.int;
      default = 250;
      description = "Max SSD tiered KV cache size in GB on external storage.";
    };

    initialCacheBlocks = lib.mkOption {
      type = lib.types.int;
      default = 64;
      description = "Pre-allocated Metal cache blocks at startup.";
    };

    maxConcurrentRequests = lib.mkOption {
      type = lib.types.int;
      default = 4;
      description = "Maximum concurrent inference requests.";
    };

    memoryGuard = lib.mkOption {
      type = lib.types.enum [ "off" "safe" "balanced" "aggressive" ];
      default = "aggressive";
      description = "Memory guard tier for macOS unified memory pressure management.";
    };

    memoryGuardGb = lib.mkOption {
      type = lib.types.nullOr lib.types.float;
      default = null;
      description = "Explicit custom memory ceiling in GB (sets memory_guard_tier = custom and bypasses conservative vm_stat dynamic double-subtraction on dedicated headless servers).";
    };

    allowUnauthenticatedInference = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Allow LAN/Tailnet clients to query inference endpoints without an API key.";
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional settings deep-merged into ~/.omlx/settings.json.";
    };
  };

  config = lib.mkIf (aiCfg.enable && cfg.enable) {
    environment.systemPackages = [
      tokenScript
    ];

    launchd.daemons.omlx = {
      serviceConfig = {
        Label = "ai.omlx.server";
        UserName = user;
        ProgramArguments = [
          "/bin/sh"
          "-c"
          ''
            set -euo pipefail

            if [ ! -d "${aiCfg.storageDir}" ]; then
              /usr/sbin/diskutil mount "${builtins.baseNameOf aiCfg.storageDir}" >/dev/null 2>&1 || true
              sleep 2
            fi

            if [ ! -d "${aiCfg.storageDir}" ]; then
              echo "[omlx] ${aiCfg.storageDir} not mounted. Waiting..." >&2
              sleep 10
              exit 1
            fi

            mkdir -p /var/lib/omlx "${modelsDir}" "${kvCacheDir}"

            if [ ! -f "${apiKeyPath}" ]; then
              /usr/bin/openssl rand -hex 24 > "${apiKeyPath}"
              chmod 600 "${apiKeyPath}"
            fi

            API_KEY="$(cat "${apiKeyPath}")"

            exec /opt/homebrew/bin/omlx serve \
              --host "${aiCfg.host}" \
              --port "${toString cfg.port}" \
              --headless \
              --model-dir "${modelsDir}" \
              --paged-ssd-cache-dir "${kvCacheDir}" \
              --paged-ssd-cache-max-size "${toString cfg.ssdCacheGb}GB" \
              --hot-cache-max-size "${toString cfg.hotCacheGb}GB" \
              --hot-cache-write-through \
              --initial-cache-blocks "${toString cfg.initialCacheBlocks}" \
              --max-concurrent-requests "${toString cfg.maxConcurrentRequests}" \
              ${if cfg.memoryGuardGb != null then ''--memory-guard-gb "${toString cfg.memoryGuardGb}"'' else ''--memory-guard "${cfg.memoryGuard}"''} \
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
          PATH = daemonPath;
        };
      };
    };

    system.activationScripts.postActivation.text = ''
      mkdir -p /var/lib/omlx
      chown -R ${user}:staff /var/lib/omlx
      chmod 700 /var/lib/omlx

      touch /var/log/omlx.log /var/log/omlx.err.log
      chown ${user}:staff /var/log/omlx.log /var/log/omlx.err.log

      SETTINGS_DIR="/Users/${user}/.omlx"
      SETTINGS_FILE="$SETTINGS_DIR/settings.json"
      MODEL_SETTINGS_FILE="$SETTINGS_DIR/model_settings.json"
      mkdir -p "$SETTINGS_DIR"

      NIX_SETTINGS='${builtins.toJSON mergedSettings}'
      if [ -f "$SETTINGS_FILE" ]; then
        ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$SETTINGS_FILE" <(echo "$NIX_SETTINGS") > "$SETTINGS_FILE.tmp"
        mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
      else
        echo "$NIX_SETTINGS" > "$SETTINGS_FILE"
      fi

      NIX_MODEL_SETTINGS='${builtins.toJSON mergedModelSettings}'
      if [ -f "$MODEL_SETTINGS_FILE" ]; then
        ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$MODEL_SETTINGS_FILE" <(echo "$NIX_MODEL_SETTINGS") > "$MODEL_SETTINGS_FILE.tmp"
        mv "$MODEL_SETTINGS_FILE.tmp" "$MODEL_SETTINGS_FILE"
      else
        echo "$NIX_MODEL_SETTINGS" > "$MODEL_SETTINGS_FILE"
      fi

      chown -R ${user}:staff "$SETTINGS_DIR"
      chmod 600 "$SETTINGS_FILE" "$MODEL_SETTINGS_FILE"

      # Ensure Homebrew's user LaunchAgent never conflicts with system/ai.omlx.server on :8000
      uid=$(id -u "${user}")
      /bin/launchctl bootout "gui/$uid/sh.brew.omlx" 2>/dev/null || true
      /bin/launchctl bootout "user/$uid/sh.brew.omlx" 2>/dev/null || true
      rm -f "/Users/${user}/Library/LaunchAgents/sh.brew.omlx.plist"

      /bin/launchctl kickstart -k system/ai.omlx.server || true
    '';
  };
}
