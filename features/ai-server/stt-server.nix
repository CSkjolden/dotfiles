{ config, lib, ... }:
let
  aiCfg = config.services.aiServer;
  cfg = aiCfg.stt;
  user = config.system.primaryUser;
  sttModelPath = "${aiCfg.storageDir}/stt_models/${cfg.modelVariant}";
in
{
  options.services.aiServer.stt = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable WhisperKit CoreML STT server on the Apple Neural Engine.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8001;
      description = "Port for the Apple Neural Engine STT server (/v1/audio/transcriptions).";
    };
    repo = lib.mkOption {
      type = lib.types.str;
      default = "argmaxinc/whisperkit-coreml";
      description = "Hugging Face repository hosting CoreML .mlmodelc Whisper bundles.";
    };
    modelVariant = lib.mkOption {
      type = lib.types.str;
      default = "openai_whisper-large-v3-v20240930_turbo_632MB";
      description = "CoreML Whisper model subfolder in argmaxinc/whisperkit-coreml (632MB LUT-palettized for ANE SRAM).";
    };
    tokenizerRepo = lib.mkOption {
      type = lib.types.str;
      default = "openai/whisper-large-v3-turbo";
      description = "Hugging Face repository for bundled Whisper tokenizer files.";
    };
  };

  config = lib.mkIf (aiCfg.enable && cfg.enable) {
    homebrew.brews = [
      "whisperkit-cli" # Swift native CoreML/ANE Whisper server for Apple Silicon
    ];

    # 24/7 Apple Neural Engine (CoreML) Speech-to-Text server (:8001)
    launchd.daemons.whisperkit-stt = {
      serviceConfig = {
        Label = "ai.whisperkit.stt";
        UserName = user;
        ProgramArguments = [
          "/bin/sh"
          "-c"
          ''
            set -euo pipefail

            if [ ! -f "${sttModelPath}/TextDecoder.mlmodelc/weights/weight.bin" ] || [ ! -f "${sttModelPath}/tokenizer.json" ]; then
              echo "[whisperkit-stt] CoreML bundle not yet fully downloaded at ${sttModelPath}. Waiting for sync..." >&2
              sleep 10
              exit 1
            fi

            exec /opt/homebrew/bin/whisperkit-cli serve \
              --host "${aiCfg.host}" \
              --port "${toString cfg.port}" \
              --model-path "${sttModelPath}" \
              --audio-encoder-compute-units cpuAndNeuralEngine \
              --text-decoder-compute-units cpuAndNeuralEngine \
              --use-prefill-prompt \
              --temperature-fallback-count 0 \
              --best-of 1 \
              --without-timestamps \
              --skip-special-tokens \
              --chunking-strategy vad
          ''
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/var/log/whisperkit-stt.log";
        StandardErrorPath = "/var/log/whisperkit-stt.log";
        EnvironmentVariables = {
          HOME = "/Users/${user}";
          PATH = "/opt/homebrew/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        };
      };
    };

    system.activationScripts.postActivation.text = ''
      touch /var/log/whisperkit-stt.log
      chown ${user}:staff /var/log/whisperkit-stt.log
      /bin/launchctl kickstart -k system/ai.whisperkit.stt || true
    '';
  };
}
