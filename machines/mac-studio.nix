{ ... }:
{
  imports = [
    ../darwin/mac-studio.nix

    ../profiles/core.nix
    ../profiles/server.nix
    ../features/ai-server
  ];

  services.aiServer = {
    enable = true;
    storageDir = "/Volumes/StudioStorage";

    omlx = {
      enable = true;
      port = 8000; # Metal GPU: Qwen 3.6 35B-A3B + d3-nano
      maxConcurrentRequests = 4;
      defaultModel = "Jundot/Qwen3.6-35B-A3B-oQ4e-mtp";
      models = [
        "Jundot/d3-nano-oQ8e"
        "Jundot/Qwen3.6-35B-A3B-oQ4e-mtp"
      ];
      pinnedModels = [
        "Jundot/d3-nano-oQ8e"
        "Jundot/Qwen3.6-35B-A3B-oQ4e-mtp"
      ];
    };

    stt = {
      enable = true;
      port = 8001; # Apple Neural Engine (CoreML): Whisper Large v3 Turbo (632MB palettized ANE)
      modelVariant = "openai_whisper-large-v3-v20240930_turbo_632MB";
    };

    tts = {
      enable = true;
      port = 8002; # CPU + AMX Coprocessor: Kokoro-82M ONNX (CPUExecutionProvider)
      model = "onnx-community/Kokoro-82M-v1.0-ONNX";
      defaultVoice = "bf_emma";
      defaultSpeed = 1.2;
    };
  };
}
