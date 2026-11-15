{ config, lib, pkgs, ... }:
let
  aiCfg = config.services.aiServer;
  cfg = aiCfg.omlx;
  user = config.system.primaryUser;
  xcodeDir = "/Applications/Xcode.app/Contents/Developer";

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

  omlxPython = "/opt/homebrew/opt/omlx/libexec/bin/python";

  omlxServeArgs =
    [
      "serve"
      "--host" aiCfg.host
      "--port" (toString cfg.port)
      "--headless"
      "--model-dir" modelsDir
      "--paged-ssd-cache-dir" kvCacheDir
      "--paged-ssd-cache-max-size" "${toString cfg.ssdCacheGb}GB"
      "--hot-cache-max-size" (if cfg.hotCacheGb > 0 then "${toString cfg.hotCacheGb}GB" else "0")
    ]
    ++ lib.optional (cfg.hotCacheGb > 0) "--hot-cache-write-through"
    ++ [
      "--initial-cache-blocks" (toString cfg.initialCacheBlocks)
      "--max-concurrent-requests" (toString cfg.maxConcurrentRequests)
    ]
    ++ (if cfg.memoryGuardGb != null
        then [ "--memory-guard-gb" (toString cfg.memoryGuardGb) ]
        else [ "--memory-guard" cfg.memoryGuard ]);

  # macOS never grants removable-volume access to system binaries such as /bin/sh and ls, so the
  # first process that touches the drive must be the oMLX Python itself (which holds the grant).
  omlxStart = pkgs.writeText "omlx-start.py" ''
    import json, os, sys, time

    storage, models, kv, key_path = sys.argv[1:5]
    args = json.loads(sys.argv[5])

    while True:
        try:
            if os.path.isdir(storage):
                os.makedirs(models, exist_ok=True)
                os.listdir(models)
                break
            reason = "not mounted"
        except OSError as e:
            reason = f"not readable: {e}"
        print(f"[omlx] {models} {reason}; waiting...", file=sys.stderr, flush=True)
        time.sleep(10)

    os.makedirs(kv, exist_ok=True)
    with open(key_path) as f:
        key = f.read().strip()
    os.execv("/opt/homebrew/bin/omlx", ["omlx", *args, "--api-key", key])
  '';

  defaultSettings = {
    version = "1.0";
    server = {
      burst_decode_mode = "aggressive";
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
      soft_threshold = 0.95;
      hard_threshold = 0.98;
      prefill_safe_zone_ratio = 0.95;
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
      hot_cache_max_size = if cfg.hotCacheGb > 0 then "${toString cfg.hotCacheGb}GB" else "0";
      hot_cache_write_through = cfg.hotCacheGb > 0;
      initial_cache_blocks = cfg.initialCacheBlocks;
    };
    sampling = {
      max_context_window = 32768;
      max_context_window_policy = null;
      max_tokens = 32768;
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
      mtp_adaptive_max_depth = 5;
      max_context_window = cfg.maxContextWindow;
      max_tool_result_tokens = cfg.maxToolResultTokens;
      thinking_budget_enabled = cfg.thinkingBudgetTokens != null;
      thinking_budget_tokens = cfg.thinkingBudgetTokens;
      a8_prefill_enabled = false;
      turboquant_kv_enabled = true;
      turboquant_kv_scheme = "affine8";
      turboquant_kv_bits = 8.0;
      turboquant_skip_last = true;
    }
  );

  mergedModelSettings = {
    version = 2;
    models = pinnedModelRecords;
  };
in
{
  imports = [
    ../xcode.nix # Xcode via the App Store, license, and xcode-select, needed to compile oMLX's Metal kernels
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
      default = 0;
      description = "RAM cache size in GB for hot prefix KV blocks (0 disables in-process RAM cache and relies on NVMe SSD + macOS page cache).";
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
      default = 1;
      description = "Maximum concurrent inference requests (1 serializes large-context requests for full MTP speed and prevents multi-sequence KV OOMs).";
    };

    maxContextWindow = lib.mkOption {
      type = lib.types.int;
      default = 153600;
      description = "Maximum context window in tokens (153600 = 150 Ki tokens = 75 x 2048-token paged KV cache blocks).";
    };

    thinkingBudgetTokens = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = 2048;
      description = "Maximum thinking/reasoning tokens per turn before forcing </think> (null disables cap).";
    };

    maxToolResultTokens = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = 8192;
      description = "Maximum tokens per individual tool result before line-boundary truncation (null disables cap).";
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
    homebrew.taps = [
      {
        name = "jundot/omlx";
        clone_target = "https://github.com/jundot/omlx";
        trusted = true;
      }
    ];

    # Server-only: native Metal kernels (Qwen3.5/3.6 fall back to slow generic paths without them).
    # Needs full Xcode with the Metal toolchain; the workstation's plain install in features/omlx.nix does not.
    homebrew.brews = [
      {
        name = "jundot/omlx/omlx";
        args = [ "with-custom-kernel" ];
      }
    ];

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
            set -eu

            if [ ! -d "${aiCfg.storageDir}" ]; then
              /usr/sbin/diskutil mount "${builtins.baseNameOf aiCfg.storageDir}" >/dev/null 2>&1 || true
              sleep 2
            fi

            mkdir -p /var/lib/omlx
            if [ ! -f "${apiKeyPath}" ]; then
              /usr/bin/openssl rand -hex 24 > "${apiKeyPath}"
              chmod 600 "${apiKeyPath}"
            fi

            exec ${omlxPython} ${omlxStart} "${aiCfg.storageDir}" "${modelsDir}" "${kvCacheDir}" "${apiKeyPath}" '${builtins.toJSON omlxServeArgs}'
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

    # mas finds installed apps through Spotlight, which the headless sweep disables, so a masApps entry
    # would reinstall Xcode on every sync. Install it once here instead.
    homebrew.masApps = lib.mkForce { };

    # Metal toolchain is a separate download since Xcode 26; the oMLX formula aborts without it.
    system.activationScripts.extraActivation.text = ''
      if [ ! -d /Applications/Xcode.app ]; then
        echo >&2 "Installing Xcode from the App Store (needs an App Store sign-in)..."
        sudo -u ${user} -H ${pkgs.mas}/bin/mas install 497799835 || echo >&2 "warning: Xcode install failed; sign in to the App Store and sync again"
      fi
      if [ -d /Applications/Xcode.app ] && ! sudo -u ${user} -H env DEVELOPER_DIR=${xcodeDir} /usr/bin/xcrun metal --version >/dev/null 2>&1; then
        echo >&2 "Downloading the Xcode Metal toolchain for oMLX custom kernels..."
        DEVELOPER_DIR=${xcodeDir} /usr/bin/xcodebuild -license accept || true
        DEVELOPER_DIR=${xcodeDir} /usr/bin/xcodebuild -downloadComponent MetalToolchain || echo >&2 "warning: Metal toolchain download failed"
      fi
    '';

    system.activationScripts.postActivation.text = ''
      # One-time rebuild: brew bundle never rebuilds an already installed formula, so an oMLX
      # installed without the kernels is reinstalled once the Metal compiler is available.
      rm -f "$(/usr/bin/getconf DARWIN_USER_TEMP_DIR 2>/dev/null)xcrun_db" /private/var/tmp/xcrun_db 2>/dev/null || true
      if [ -d /Applications/Xcode.app ] && sudo -u ${user} -H env DEVELOPER_DIR=${xcodeDir} /usr/bin/xcrun metal --version >/dev/null 2>&1 \
        && [ -f /opt/homebrew/opt/omlx/INSTALL_RECEIPT.json ] \
        && ! ${pkgs.jq}/bin/jq -e '.used_options | index("--with-custom-kernel")' /opt/homebrew/opt/omlx/INSTALL_RECEIPT.json >/dev/null 2>&1; then
        echo >&2 "Rebuilding oMLX with native custom kernels (takes a few minutes)..."
        sudo -u ${user} -H env DEVELOPER_DIR=${xcodeDir} HOMEBREW_NO_AUTO_UPDATE=1 /opt/homebrew/bin/brew reinstall jundot/omlx/omlx --with-custom-kernel \
          || echo >&2 "warning: oMLX custom-kernel rebuild failed; keeping the existing install"
      else
        echo >&2 "oMLX custom-kernel rebuild skipped (Xcode/Metal compiler missing, or kernels already built)"
      fi
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
