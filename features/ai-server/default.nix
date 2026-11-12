{ config, lib, pkgs, ... }:
let
  aiCfg = config.services.aiServer;
  omlxCfg = aiCfg.omlx;
  sttCfg = aiCfg.stt;
  ttsCfg = aiCfg.tts;
  user = config.system.primaryUser;

  modelsDir = "${aiCfg.storageDir}/models";
  sttModelsDir = "${aiCfg.storageDir}/stt_models";
  ttsModelsDir = "${aiCfg.storageDir}/tts_models";
  kvCacheDir = "${aiCfg.storageDir}/omlx_kv_cache";

  sttModelPath = "${sttModelsDir}/${sttCfg.modelVariant}";
  ttsModelPath = "${ttsModelsDir}/${builtins.baseNameOf ttsCfg.model}";

  syncScript = pkgs.writeShellScriptBin "sync-ai-models" ''
    set -euo pipefail

    STORAGE_DIR="${aiCfg.storageDir}"
    MODELS_DIR="${modelsDir}"
    STT_DIR="${sttModelsDir}"
    TTS_DIR="${ttsModelsDir}"
    KV_DIR="${kvCacheDir}"

    echo "=== Mac Studio Multi-Silicon AI Model Synchronizer ==="

    if [ ! -d "$STORAGE_DIR" ]; then
      echo "ERROR: Storage directory '$STORAGE_DIR' is not mounted!" >&2
      echo "Please attach the external SSD before running sync-ai-models." >&2
      exit 1
    fi

    mkdir -p "$MODELS_DIR" "$STT_DIR" "$TTS_DIR" "$KV_DIR"

    ${lib.optionalString omlxCfg.enable ''
      TARGET_MODELS=(
        ${builtins.concatStringsSep "\n        " (map (m: ''"${m}"'') omlxCfg.models)}
      )

      if [ $# -gt 0 ]; then
        TARGET_MODELS=("$@")
      else
        for existing in "$MODELS_DIR"/*; do
          [ -d "$existing" ] || continue
          existing_name="$(basename "$existing")"
          keep=0
          for repo in "''${TARGET_MODELS[@]}"; do
            if [ "$(basename "$repo")" = "$existing_name" ]; then
              keep=1
              break
            fi
          done
          if [ "$keep" -eq 0 ]; then
            echo ">>> Pruning undeclared model directory: $existing"
            rm -rf "$existing"
          fi
        done
      fi

      echo ""
      echo "--- [1/3] Syncing Metal GPU Models (oMLX :${toString omlxCfg.port}) ---"
      for repo in "''${TARGET_MODELS[@]}"; do
        model_name="$(basename "$repo")"
        dest_dir="$MODELS_DIR/$model_name"
        echo ">>> Syncing $repo -> $dest_dir ..."
        ${pkgs.uv}/bin/uvx --from "huggingface_hub" hf download \
          "$repo" \
          --local-dir "$dest_dir"
        echo ">>> Verified $repo."
      done
    ''}

    ${lib.optionalString sttCfg.enable ''
      echo ""
      echo "--- [2/3] Syncing Apple Neural Engine STT Model (WhisperKit :${toString sttCfg.port}) ---"
      echo ">>> Syncing CoreML bundle ${sttCfg.repo}/${sttCfg.modelVariant} -> $STT_DIR ..."
      ${pkgs.uv}/bin/uvx --from "huggingface_hub" hf download \
        "${sttCfg.repo}" \
        --include "${sttCfg.modelVariant}/*" \
        --local-dir "$STT_DIR"
      echo ">>> Syncing bundled Whisper tokenizer (${sttCfg.tokenizerRepo}) -> ${sttModelPath} ..."
      ${pkgs.uv}/bin/uvx --from "huggingface_hub" hf download \
        "${sttCfg.tokenizerRepo}" \
        --include "*.json" \
        --include "*.txt" \
        --local-dir "${sttModelPath}"
      echo ">>> Verified ANE STT model."
    ''}

    ${lib.optionalString ttsCfg.enable ''
      echo ""
      echo "--- [3/3] Syncing CPU TTS Model (Kokoro ONNX :${toString ttsCfg.port}) ---"
      echo ">>> Syncing ${ttsCfg.model} -> ${ttsModelPath} ..."
      ${pkgs.uv}/bin/uvx --from "huggingface_hub" hf download \
        "${ttsCfg.model}" \
        --include "onnx/model_quantized.onnx" \
        --include "tokenizer.json" \
        --include "config.json" \
        --include "voices/*" \
        --local-dir "${ttsModelPath}"
      echo ">>> Verified CPU TTS model."
    ''}

    echo ""
    echo "=== Model sync complete! ==="
    echo "Reloading GPU, ANE, and CPU inference daemons..."
    /bin/launchctl kickstart -k system/ai.omlx.server 2>/dev/null || true
    /bin/launchctl kickstart -k system/ai.whisperkit.stt 2>/dev/null || true
    /bin/launchctl kickstart -k system/ai.kokoro.tts 2>/dev/null || true
  '';

  statusScript = pkgs.writeShellScriptBin "ai-status" ''
    set -euo pipefail
    echo "=== Mac Studio Tri-Silicon AI Status ==="

    ${lib.optionalString omlxCfg.enable ''
      echo ""
      echo "[1] Metal GPU Engine (oMLX — ${aiCfg.host}:${toString omlxCfg.port})"
      if curl -s -f -o /dev/null "http://127.0.0.1:${toString omlxCfg.port}/health" 2>/dev/null; then
        echo "    Status: ONLINE"
        MODELS="$(curl -s "http://127.0.0.1:${toString omlxCfg.port}/v1/models" | ${pkgs.jq}/bin/jq -r '.data[].id' 2>/dev/null | sed 's/^/      - /' || true)"
        [ -n "$MODELS" ] && echo "$MODELS" || echo "      (no models registered)"
      else
        echo "    Status: STOPPED (check /var/log/omlx.err.log)"
      fi
    ''}

    ${lib.optionalString sttCfg.enable ''
      echo ""
      echo "[2] Apple Neural Engine STT (WhisperKit CoreML — ${aiCfg.host}:${toString sttCfg.port})"
      if curl -s -f -o /dev/null "http://127.0.0.1:${toString sttCfg.port}/health" 2>/dev/null; then
        echo "    Status: ONLINE (Compute: cpuAndNeuralEngine)"
        echo "      - ${sttCfg.modelVariant} (/v1/audio/transcriptions)"
      else
        echo "    Status: STOPPED / LOADING (check /var/log/whisperkit-stt.log)"
      fi
    ''}

    ${lib.optionalString ttsCfg.enable ''
      echo ""
      echo "[3] CPU + AMX Engine TTS (Kokoro — ${aiCfg.host}:${toString ttsCfg.port})"
      if curl -s -f -o /dev/null "http://127.0.0.1:${toString ttsCfg.port}/health" 2>/dev/null; then
        DEVICE="$(curl -s "http://127.0.0.1:${toString ttsCfg.port}/health" | ${pkgs.jq}/bin/jq -r '.device' 2>/dev/null || echo "cpu")"
        echo "    Status: ONLINE (Compute: $DEVICE)"
        echo "      - ${builtins.baseNameOf ttsCfg.model} (/v1/audio/speech)"
      else
        echo "    Status: STOPPED / LOADING (check /var/log/kokoro-tts.log)"
      fi
    ''}
  '';
in
{
  imports = [
    ./omlx-server.nix
    ./stt-server.nix
    ./tts-server.nix
  ];

  options.services.aiServer = {
    enable = lib.mkEnableOption "Mac Studio tri-silicon AI inference cluster";

    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Network interface to bind across AI services (0.0.0.0 for all interfaces).";
    };

    storageDir = lib.mkOption {
      type = lib.types.str;
      default = "/Volumes/StudioStorage";
      description = "Path to the dedicated external storage mount for models and KV caches.";
    };
  };

  config = lib.mkIf aiCfg.enable {
    environment.systemPackages = [
      syncScript
      statusScript
    ];

    # Root boot daemon to ensure external AI storage volume is mounted even without a GUI login
    launchd.daemons.ai-storage-mount = {
      serviceConfig = {
        Label = "ai.storage.mount";
        ProgramArguments = [
          "/bin/sh"
          "-c"
          ''
            /usr/bin/defaults write /Library/Preferences/SystemConfiguration/autodiskmount AutomountDisksWithoutUserLogin -bool true 2>/dev/null || true
            if [ ! -d "${aiCfg.storageDir}" ]; then
              /usr/sbin/diskutil mount "${builtins.baseNameOf aiCfg.storageDir}" >/dev/null 2>&1 || true
            fi
          ''
        ];
        RunAtLoad = true;
      };
    };

    # Background model sync service: runs once on boot or activation without blocking server startup
    launchd.daemons.ai-models-sync = {
      serviceConfig = {
        Label = "ai.models.sync";
        UserName = user;
        ProgramArguments = [
          "/bin/sh"
          "-c"
          ''
            set -euo pipefail

            if [ ! -d "${aiCfg.storageDir}" ]; then
              echo "[ai-models-sync] Storage directory ${aiCfg.storageDir} is not mounted. Skipping sync." >&2
              exit 0
            fi

            exec ${syncScript}/bin/sync-ai-models
          ''
        ];
        RunAtLoad = true;
        StandardOutPath = "/var/log/ai-models-sync.log";
        StandardErrorPath = "/var/log/ai-models-sync.log";
        EnvironmentVariables = {
          HOME = "/Users/${user}";
          PATH = "/opt/homebrew/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        };
      };
    };

    system.activationScripts.postActivation.text = ''
      /usr/bin/defaults write /Library/Preferences/SystemConfiguration/autodiskmount AutomountDisksWithoutUserLogin -bool true 2>/dev/null || true
      if [ ! -d "${aiCfg.storageDir}" ]; then
        /usr/sbin/diskutil mount "${builtins.baseNameOf aiCfg.storageDir}" >/dev/null 2>&1 || true
      fi

      touch /var/log/ai-models-sync.log
      chown ${user}:staff /var/log/ai-models-sync.log
      /bin/launchctl kickstart -k system/ai.models.sync || true
    '';
  };
}
