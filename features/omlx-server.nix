{ config, lib, pkgs, ... }:
let
  cfg = config.services.omlx;
  user = config.system.primaryUser;

  modelsDir = "${cfg.storageDir}/models";
  sttModelsDir = "${cfg.storageDir}/stt_models";
  ttsModelsDir = "${cfg.storageDir}/tts_models";
  kvCacheDir = "${cfg.storageDir}/omlx_kv_cache";
  apiKeyPath = "/var/lib/omlx/api_key";

  sttModelPath = "${sttModelsDir}/${cfg.stt.modelVariant}";
  ttsModelPath = "${ttsModelsDir}/${builtins.baseNameOf cfg.tts.model}";

  kokoroCpuServer = pkgs.writeScriptBin "kokoro-cpu-server" ''
    #!/opt/homebrew/opt/omlx/libexec/bin/python3
    import io
    import json
    import os
    import re
    import threading

    import numpy as np
    import onnxruntime as ort
    import soundfile as sf
    import uvicorn
    from fastapi import FastAPI, HTTPException
    from fastapi.responses import Response, StreamingResponse
    from misaki import en, espeak
    from pydantic import BaseModel

    MODEL_PATH = "${ttsModelPath}"
    ONNX_FILE = os.path.join(MODEL_PATH, "onnx", "model_quantized.onnx")
    TOKENIZER_FILE = os.path.join(MODEL_PATH, "tokenizer.json")
    VOICES_DIR = os.path.join(MODEL_PATH, "voices")
    DEFAULT_VOICE = "${cfg.tts.defaultVoice}"
    DEFAULT_SPEED = ${toString cfg.tts.defaultSpeed}
    DEFAULT_SPLIT_PATTERN = r"(?<=[.;:!?\n—])\s+"
    SAMPLE_RATE = 24000

    app = FastAPI(title="Kokoro ONNX CPU TTS Server")
    _lock = threading.Lock()
    _abort_event = threading.Event()
    _sess = None
    _in_names = []
    _vocab = {}
    _voices = {}
    _g2p_us = None
    _g2p_gb = None

    class SpeechRequest(BaseModel):
        model: str = "Kokoro-82M-ONNX"
        input: str
        voice: str = DEFAULT_VOICE
        response_format: str = "wav"
        speed: float = DEFAULT_SPEED
        pause_ms: float = 100.0
        split_pattern: str | None = DEFAULT_SPLIT_PATTERN
        stream: bool = False

    def _load_voice(voice_name: str) -> np.ndarray:
        if voice_name in _voices:
            return _voices[voice_name]
        vpath = os.path.join(VOICES_DIR, f"{voice_name}.bin")
        if not os.path.isfile(vpath):
            vpath = os.path.join(VOICES_DIR, f"{DEFAULT_VOICE}.bin")
        pack = np.fromfile(vpath, dtype=np.float32).reshape(-1, 1, 256)
        _voices[voice_name] = pack
        return pack

    _EMOJI_RE = re.compile(
        "["
        "\U0001F300-\U0001F9FF"
        "\U00002600-\U000027BF"
        "\U0001FA00-\U0001FAFF"
        "]+",
        flags=re.UNICODE,
    )
    _SSML_RE = re.compile(r"<[^>]+>")
    _EMOTION_TAG_RE = re.compile(
        r"\[(?:happy|sad|excited|whisper|angry|laugh|laughing|sigh|pause|music|applause|clears throat|gasp)[^\]]*\]",
        flags=re.IGNORECASE,
    )
    _ONES = ["", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
    _TENS = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
    _ORDINALS = {
        1: "first", 2: "second", 3: "third", 4: "fourth", 5: "fifth", 6: "sixth",
        7: "seventh", 8: "eighth", 9: "ninth", 10: "tenth", 11: "eleventh", 12: "twelfth",
        13: "thirteenth", 14: "fourteenth", 15: "fifteenth", 16: "sixteenth",
        17: "seventeenth", 18: "eighteenth", 19: "nineteenth", 20: "twentieth",
        21: "twenty-first", 22: "twenty-second", 23: "twenty-third", 24: "twenty-fourth",
        25: "twenty-fifth", 26: "twenty-sixth", 27: "twenty-seventh", 28: "twenty-eighth",
        29: "twenty-ninth", 30: "thirtieth", 31: "thirty-first",
    }
    _ROMAN_TO_INT = {
        "I": 1, "II": 2, "III": 3, "IV": 4, "V": 5, "VI": 6, "VII": 7, "VIII": 8,
        "IX": 9, "X": 10, "XI": 11, "XII": 12, "XIII": 13, "XIV": 14, "XV": 15,
        "XVI": 16, "XVII": 17, "XVIII": 18, "XIX": 19, "XX": 20, "XXI": 21,
    }
    _CARDINAL_ROMAN_RE = re.compile(
        r"\b(War|Part|Chapter|Book|Volume|Vol|Act|Scene|Phase|Stage|Type|Mark|Tier|Level|Section|Article)\s+"
        r"(XXI|XX|XIX|XVIII|XVII|XVI|XV|XIV|XIII|XII|XI|X|IX|VIII|VII|VI|V|IV|III|II|I)\b"
    )
    _TITLED_ROMAN_RE = re.compile(
        r"\b((?:King|Queen|Pope|Emperor|Empress|Tsar|Czar|Prince|Princess|Duke|Archduke|Sultan|Pharaoh)\s+"
        r"[A-ZÀ-ÖØ-Þ][a-zA-ZÀ-ÿ\-]+(?:\s+[A-ZÀ-ÖØ-Þ][a-zA-ZÀ-ÿ\-]+)?)\s+"
        r"(XXI|XX|XIX|XVIII|XVII|XVI|XV|XIV|XIII|XII|XI|X|IX|VIII|VII|VI|V|IV|III|II|I)\b"
    )
    _NAME_ROMAN_RE = re.compile(
        r"\b([A-ZÀ-ÖØ-Þ][a-zÀ-ÿ\-]{2,})\s+"
        r"(XXI|XX|XIX|XVIII|XVII|XVI|XV|XIV|XIII|XII|XI|X|IX|VIII|VII|VI|V|IV|III|II)\b"
    )
    _NUMERIC_ORDINAL_RE = re.compile(r"\b([12]?\d|3[01])(?:st|nd|rd|th)\b", flags=re.IGNORECASE)

    def _two_digit_words(n: int) -> str:
        if n < 20:
            return _ONES[n]
        t, o = divmod(n, 10)
        return f"{_TENS[t]}-{_ONES[o]}" if o else _TENS[t]

    def _expand_year(match: re.Match) -> str:
        yr = int(match.group(0))
        hi, lo = divmod(yr, 100)
        if yr == 2000:
            return "two thousand"
        if 2001 <= yr <= 2009:
            return f"two thousand {_ONES[lo]}"
        if lo == 0:
            return f"{_two_digit_words(hi)} hundred"
        if lo < 10:
            return f"{_two_digit_words(hi)} oh {_ONES[lo]}"
        return f"{_two_digit_words(hi)} {_two_digit_words(lo)}"

    def _normalize_for_kokoro(text: str) -> str:
        text = _SSML_RE.sub(" ", text)
        text = _EMOTION_TAG_RE.sub(" ", text)
        text = _EMOJI_RE.sub(" ", text)
        text = re.sub(r"[*_`#~]+", "", text)
        text = re.sub(r"!{2,}", "!", text)
        text = re.sub(r"\?{2,}", "?", text)
        text = re.sub(r"\.{4,}", "...", text)
        text = _CARDINAL_ROMAN_RE.sub(
            lambda m: f"{m.group(1)} {_two_digit_words(_ROMAN_TO_INT[m.group(2)])}", text
        )
        text = _TITLED_ROMAN_RE.sub(
            lambda m: f"{m.group(1)} the {_ORDINALS[_ROMAN_TO_INT[m.group(2)]]}", text
        )
        text = _NAME_ROMAN_RE.sub(
            lambda m: f"{m.group(1)} the {_ORDINALS[_ROMAN_TO_INT[m.group(2)]]}", text
        )
        text = _NUMERIC_ORDINAL_RE.sub(
            lambda m: _ORDINALS.get(int(m.group(1)), m.group(0)), text
        )
        text = re.sub(r"\b(1[89]\d\d|20\d\d)\b", _expand_year, text)
        return re.sub(r"\s+", " ", text).strip()

    def _split_clauses(text: str, split_pattern: str | None = DEFAULT_SPLIT_PATTERN) -> list[str]:
        cleaned = _normalize_for_kokoro(text)
        if not cleaned or not split_pattern:
            return [cleaned] if cleaned else []
        raw_parts = [p.strip() for p in re.split(split_pattern, cleaned) if p and p.strip()]
        # Keep chunks under 500 chars so Kokoro prosody never degrades on long passages
        chunks: list[str] = []
        for part in raw_parts:
            while len(part) > 480:
                cut = part.rfind(", ", 0, 480)
                if cut == -1:
                    cut = part.rfind(" ", 0, 480)
                if cut == -1:
                    cut = 480
                chunks.append(part[: cut + 1].strip())
                part = part[cut + 1 :].strip()
            if part:
                chunks.append(part)
        return chunks if chunks else [cleaned]

    def _trim_outer_silence(audio: np.ndarray, pause_ms: float = 100.0, thresh: float = 0.0025) -> np.ndarray:
        """
        Trims only the dead silence at the very start (~320ms) and end (~470ms) of the clip
        using a low threshold (0.0025) and 25ms lead-in pad so unvoiced consonants are never clipped,
        while preserving 100% of Kokoro's internal punctuation pauses (',', '...', '-', ';', ':').
        """
        if audio.size == 0:
            return audio
        idx = np.where(np.abs(audio) > thresh)[0]
        if idx.size == 0:
            return np.zeros(0, dtype=np.float32)
        lead_pad = int(SAMPLE_RATE * 0.025)
        start = max(0, int(idx[0]) - lead_pad)
        end = min(len(audio), int(idx[-1]) + int(SAMPLE_RATE * 0.030))
        trimmed = audio[start:end]
        tail = np.zeros(int(SAMPLE_RATE * (pause_ms / 1000.0)), dtype=np.float32)
        return np.concatenate([trimmed, tail], axis=0)

    def _synthesize_clause(text: str, voice: str, speed: float, pause_ms: float = 100.0) -> np.ndarray:
        g2p = _g2p_gb if (voice and voice.startswith("b")) else _g2p_us
        phonemes, _ = g2p(text)
        tokens = [_vocab[c] for c in phonemes if c in _vocab]
        if not tokens:
            return np.zeros(0, dtype=np.float32)
        tokens = tokens[:510]
        input_ids = np.array([[0, *tokens, 0]], dtype=np.int64)
        pack = _load_voice(voice)
        style = pack[min(len(tokens), len(pack) - 1)]
        spd = np.array([speed], dtype=np.float32)
        with _lock:
            out = _sess.run(None, {_in_names[0]: input_ids, _in_names[1]: style, _in_names[2]: spd})[0]
        raw = np.asarray(out, dtype=np.float32).flatten()
        return _trim_outer_silence(raw, pause_ms=pause_ms)

    @app.on_event("startup")
    def startup_event():
        global _sess, _in_names, _vocab, _g2p_us, _g2p_gb
        if not os.path.isfile(ONNX_FILE):
            raise RuntimeError(f"ONNX model {ONNX_FILE} not found.")
        with open(TOKENIZER_FILE, encoding="utf-8") as f:
            _vocab = json.load(f)["model"]["vocab"]
        _g2p_us = en.G2P(trf=False, british=False, fallback=espeak.EspeakFallback(british=False))
        _g2p_gb = en.G2P(trf=False, british=True, fallback=espeak.EspeakFallback(british=True))
        sess_opts = ort.SessionOptions()
        sess_opts.intra_op_num_threads = 10
        sess_opts.inter_op_num_threads = 1
        sess_opts.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
        sess_opts.enable_cpu_mem_arena = True
        sess_opts.enable_mem_pattern = True
        sess_opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        _sess = ort.InferenceSession(ONNX_FILE, sess_options=sess_opts, providers=["CPUExecutionProvider"])
        _in_names = [i.name for i in _sess.get_inputs()]
        _synthesize_clause("Warmup.", DEFAULT_VOICE, 1.0)

    @app.get("/health")
    def health():
        return {
            "status": "ok" if _sess is not None else "loading",
            "device": "CPUExecutionProvider (10 P-cores / Accelerate AMX)",
            "model": os.path.basename(MODEL_PATH),
        }

    @app.post("/abort")
    @app.post("/v1/audio/abort")
    def abort_speech():
        _abort_event.set()
        return {"status": "aborted"}

    @app.get("/v1/models")
    def list_models():
        return {
            "object": "list",
            "data": [
                {
                    "id": os.path.basename(MODEL_PATH),
                    "object": "model",
                    "owned_by": "kokoro-onnx-cpu",
                    "device": "CPUExecutionProvider",
                }
            ],
        }

    @app.post("/v1/audio/speech")
    def create_speech(req: SpeechRequest):
        if _sess is None:
            raise HTTPException(status_code=503, detail="TTS model not loaded")
        if not req.input.strip():
            raise HTTPException(status_code=400, detail="input text must not be empty")

        _abort_event.clear()
        voice = req.voice or DEFAULT_VOICE
        clauses = _split_clauses(req.input, req.split_pattern)
        fmt = (req.response_format or "wav").lower()

        # Clause-pipelined PCM streaming for ultra-low TTFA (~35ms first chunk)
        if req.stream or fmt == "pcm":
            def _stream_pcm():
                for clause in clauses:
                    if _abort_event.is_set():
                        break
                    chunk = _synthesize_clause(clause, voice, req.speed, req.pause_ms)
                    if chunk.size > 0 and not _abort_event.is_set():
                        yield (np.clip(chunk, -1.0, 1.0) * 32767.0).astype(np.int16).tobytes()
            if req.stream:
                return StreamingResponse(_stream_pcm(), media_type="audio/pcm")

        chunks = []
        for clause in clauses:
            if _abort_event.is_set():
                break
            chunk = _synthesize_clause(clause, voice, req.speed, req.pause_ms)
            if chunk.size > 0:
                chunks.append(chunk)

        if not chunks:
            raise HTTPException(status_code=500, detail="TTS produced no audio")

        waveform = np.clip(np.concatenate(chunks, axis=0), -1.0, 1.0)

        if fmt == "pcm":
            pcm_bytes = (waveform * 32767.0).astype(np.int16).tobytes()
            return Response(content=pcm_bytes, media_type="audio/pcm")

        media_types = {
            "wav": ("WAV", "audio/wav"),
            "flac": ("FLAC", "audio/flac"),
            "mp3": ("MP3", "audio/mpeg"),
            "opus": ("OGG", "audio/ogg"),
        }
        sf_fmt, mime = media_types.get(fmt, ("WAV", "audio/wav"))
        buf = io.BytesIO()
        sf.write(buf, waveform, SAMPLE_RATE, format=sf_fmt)
        return Response(content=buf.getvalue(), media_type=mime)

    if __name__ == "__main__":
        uvicorn.run(app, host="${cfg.host}", port=${toString cfg.tts.port}, log_level="info")
  '';

  syncScript = pkgs.writeShellScriptBin "sync-ai-models" ''
    set -euo pipefail

    STORAGE_DIR="${cfg.storageDir}"
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

    TARGET_MODELS=(
      ${builtins.concatStringsSep "\n      " (map (m: ''"${m}"'') cfg.models)}
    )

    if [ $# -gt 0 ]; then
      TARGET_MODELS=("$@")
    else
      # Prune undeclared GPU LLM model directories from external storage
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
    echo "--- [1/3] Syncing Metal GPU Models (oMLX :${toString cfg.port}) ---"
    for repo in "''${TARGET_MODELS[@]}"; do
      model_name="$(basename "$repo")"
      dest_dir="$MODELS_DIR/$model_name"
      echo ">>> Syncing $repo -> $dest_dir ..."
      ${pkgs.uv}/bin/uvx --from "huggingface_hub" hf download \
        "$repo" \
        --local-dir "$dest_dir"
      echo ">>> Verified $repo."
    done

    ${lib.optionalString cfg.stt.enable ''
      echo ""
      echo "--- [2/3] Syncing Apple Neural Engine STT Model (WhisperKit :${toString cfg.stt.port}) ---"
      echo ">>> Syncing CoreML bundle ${cfg.stt.repo}/${cfg.stt.modelVariant} -> $STT_DIR ..."
      ${pkgs.uv}/bin/uvx --from "huggingface_hub" hf download \
        "${cfg.stt.repo}" \
        --include "${cfg.stt.modelVariant}/*" \
        --local-dir "$STT_DIR"
      echo ">>> Syncing bundled Whisper tokenizer (${cfg.stt.tokenizerRepo}) -> ${sttModelPath} ..."
      ${pkgs.uv}/bin/uvx --from "huggingface_hub" hf download \
        "${cfg.stt.tokenizerRepo}" \
        --include "*.json" \
        --include "*.txt" \
        --local-dir "${sttModelPath}"
      echo ">>> Verified ANE STT model."
    ''}

    ${lib.optionalString cfg.tts.enable ''
      echo ""
      echo "--- [3/3] Syncing CPU TTS Model (Kokoro ONNX :${toString cfg.tts.port}) ---"
      echo ">>> Syncing ${cfg.tts.model} -> ${ttsModelPath} ..."
      ${pkgs.uv}/bin/uvx --from "huggingface_hub" hf download \
        "${cfg.tts.model}" \
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
    echo "=== Mac Studio Tri-Silicon AI Status ==="
    echo ""
    echo "[1] Metal GPU Engine (oMLX — ${cfg.host}:${toString cfg.port})"
    if curl -s -f -o /dev/null "http://127.0.0.1:${toString cfg.port}/health" 2>/dev/null; then
      echo "    Status: ONLINE"
      MODELS="$(curl -s "http://127.0.0.1:${toString cfg.port}/v1/models" | ${pkgs.jq}/bin/jq -r '.data[].id' 2>/dev/null | sed 's/^/      - /' || true)"
      [ -n "$MODELS" ] && echo "$MODELS" || echo "      (no models registered)"
    else
      echo "    Status: STOPPED (check /var/log/omlx.err.log)"
    fi

    echo ""
    echo "[2] Apple Neural Engine STT (WhisperKit CoreML — ${cfg.host}:${toString cfg.stt.port})"
    if curl -s -f -o /dev/null "http://127.0.0.1:${toString cfg.stt.port}/health" 2>/dev/null; then
      echo "    Status: ONLINE (Compute: cpuAndNeuralEngine)"
      echo "      - ${cfg.stt.modelVariant} (/v1/audio/transcriptions)"
    else
      echo "    Status: STOPPED / LOADING (check /var/log/whisperkit-stt.log)"
    fi

    echo ""
    echo "[3] CPU + AMX Engine TTS (Kokoro — ${cfg.host}:${toString cfg.tts.port})"
    if curl -s -f -o /dev/null "http://127.0.0.1:${toString cfg.tts.port}/health" 2>/dev/null; then
      DEVICE="$(curl -s "http://127.0.0.1:${toString cfg.tts.port}/health" | ${pkgs.jq}/bin/jq -r '.device' 2>/dev/null || echo "cpu")"
      echo "    Status: ONLINE (Compute: $DEVICE)"
      echo "      - ${builtins.baseNameOf cfg.tts.model} (/v1/audio/speech)"
    else
      echo "    Status: STOPPED / LOADING (check /var/log/kokoro-tts.log)"
    fi
  '';

  mergedSettings = lib.recursiveUpdate {
    version = "1.0";
    server = {
      burst_decode_mode = "balanced";
      preserve_mid_system_cache = true;
      gpu_keep_warm_interval = 0.5;
    };
    scheduler = {
      max_concurrent_requests = cfg.maxConcurrentRequests;
      chunked_prefill = true;
      decode_fairness = true;
      prefill_priority = "speed";
    };
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

  pinnedModelRecords = lib.genAttrs (map (m: builtins.baseNameOf m) cfg.pinnedModels) (name: {
    is_pinned = true;
  } // lib.optionalAttrs (lib.hasInfix "Qwen" name) {
    is_default = true;
    mtp_enabled = true;
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
        "Jundot/d3-nano-oQ8e"
        "Jundot/Qwen3.6-35B-A3B-oQ4e-mtp"
      ];
      description = "Models to pre-load on boot and pin permanently in unified memory (never evicted).";
    };

    hotCacheGb = lib.mkOption {
      type = lib.types.int;
      default = 4;
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
      default = "aggressive";
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

    stt = {
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

    tts = {
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
        default = "af_heart";
        description = "Default Kokoro speaker voice (e.g. af_heart, af_bella, am_fenrir, bf_emma, bm_george).";
      };
      defaultSpeed = lib.mkOption {
        type = lib.types.float;
        default = 1.0;
        description = "Default Kokoro speech speed multiplier (0.5 to 2.0).";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    homebrew.brews = lib.mkIf cfg.stt.enable [
      "whisperkit-cli" # Swift native CoreML/ANE Whisper server for Apple Silicon
    ];

    environment.systemPackages = [
      syncScript
      tokenScript
      statusScript
      kokoroCpuServer
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

    # 24/7 Apple Neural Engine (CoreML) Speech-to-Text server (:8001)
    launchd.daemons.whisperkit-stt = lib.mkIf cfg.stt.enable {
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
              --host "${cfg.host}" \
              --port "${toString cfg.stt.port}" \
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

    # 24/7 CPU + AMX Coprocessor Text-to-Speech server (:8002)
    launchd.daemons.kokoro-tts = lib.mkIf cfg.tts.enable {
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
          MLX_DEFAULT_DEVICE = "cpu";
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

      touch /var/log/omlx.log /var/log/omlx.err.log /var/log/omlx-sync.log /var/log/whisperkit-stt.log /var/log/kokoro-tts.log
      chown ${user}:staff /var/log/omlx.log /var/log/omlx.err.log /var/log/omlx-sync.log /var/log/whisperkit-stt.log /var/log/kokoro-tts.log

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
      /bin/launchctl kickstart -k system/ai.whisperkit.stt || true
      /bin/launchctl kickstart -k system/ai.kokoro.tts || true
      /bin/launchctl kickstart -k system/ai.omlx.models-sync || true
    '';
  };
}
