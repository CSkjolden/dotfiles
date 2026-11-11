{ config, lib, pkgs, ... }:
let
  aiCfg = config.services.aiServer;
  cfg = aiCfg.tts;
  user = config.system.primaryUser;
  ttsModelPath = "${aiCfg.storageDir}/tts_models/${builtins.baseNameOf cfg.model}";

  kokoroCpuServer = pkgs.writeShellScriptBin "kokoro-cpu-server" ''
    exec /opt/homebrew/opt/omlx/libexec/bin/python3 ${./kokoro_cpu_server.py} "$@"
  '';
in
{
  options.services.aiServer.tts = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Kokoro ONNX TTS server pinned to CPU + AMX coprocessor.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8002;
      description = "Port for the CPU TTS server (/v1/audio/speech).";
    };
    model = lib.mkOption {
      type = lib.types.str;
      default = "onnx-community/Kokoro-82M-v1.0-ONNX";
      description = "Hugging Face repository for Kokoro ONNX TTS model.";
    };
    defaultVoice = lib.mkOption {
      type = lib.types.str;
      default = "bf_emma";
      description = "Default Kokoro speaker voice (e.g. af_heart, af_bella, am_fenrir, bf_emma, bm_george).";
    };
    defaultSpeed = lib.mkOption {
      type = lib.types.float;
      default = 1.0;
      description = "Default Kokoro speech speed multiplier (0.5 to 2.0).";
    };
  };

  config = lib.mkIf (aiCfg.enable && cfg.enable) {
    environment.systemPackages = [
      kokoroCpuServer
    ];

    # 24/7 CPU + AMX Coprocessor Text-to-Speech server (:8002)
    launchd.daemons.kokoro-tts = {
      serviceConfig = {
        Label = "ai.kokoro.tts";
        UserName = user;
        ProgramArguments = [
          "/bin/sh"
          "-c"
          ''
            set -euo pipefail

            if [ ! -f "${ttsModelPath}/onnx/model_quantized.onnx" ]; then
              echo "[kokoro-tts] Kokoro ONNX weights not yet downloaded at ${ttsModelPath}. Waiting for sync..." >&2
              sleep 10
              exit 1
            fi

            exec ${kokoroCpuServer}/bin/kokoro-cpu-server
          ''
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/var/log/kokoro-tts.log";
        StandardErrorPath = "/var/log/kokoro-tts.log";
        EnvironmentVariables = {
          KOKORO_MODEL_PATH = ttsModelPath;
          KOKORO_HOST = aiCfg.host;
          KOKORO_PORT = toString cfg.port;
          KOKORO_DEFAULT_VOICE = cfg.defaultVoice;
          KOKORO_DEFAULT_SPEED = toString cfg.defaultSpeed;
          MLX_DEFAULT_DEVICE = "cpu";
          HOME = "/Users/${user}";
          PATH = "/opt/homebrew/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        };
      };
    };

    system.activationScripts.postActivation.text = ''
      touch /var/log/kokoro-tts.log
      chown ${user}:staff /var/log/kokoro-tts.log
      /bin/launchctl kickstart -k system/ai.kokoro.tts || true
    '';
  };
}
