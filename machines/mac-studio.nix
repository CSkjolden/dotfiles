{ ... }:
{
  imports = [
    ../darwin/mac-studio.nix

    ../profiles/core.nix
    ../profiles/server.nix
    ../features/omlx-server.nix
  ];

  services.omlx = {
    enable = true;
    port = 8000; # Metal GPU: Qwen 3.6 35B-A3B + d3-nano
    storageDir = "/Volumes/StudioStorage";
    maxConcurrentRequests = 4;
    models = [
      "Jundot/d3-nano-oQ8e"
      "Jundot/Qwen3.6-35B-A3B-oQ4e-mtp"
    ];
    stt = {
      enable = true;
      port = 8001; # Apple Neural Engine (CoreML): Whisper Large v3 Turbo
      modelVariant = "openai_whisper-large-v3_turbo";
    };
    tts = {
      enable = true;
      port = 8002; # CPU + AMX Coprocessor: Kokoro-82M-bf16
      model = "mlx-community/Kokoro-82M-bf16";
    };
  };
}
