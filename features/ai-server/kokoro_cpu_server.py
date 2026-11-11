#!/opt/homebrew/opt/omlx/libexec/bin/python3
"""
Minimal CPU + AMX Kokoro ONNX TTS Server (:8002)
------------------------------------------------
Uses stdlib ThreadingHTTPServer, memory-mapped voice packs, C espeak-ng
phonemization (no spaCy/FastAPI/Uvicorn bloat), and arena-free ONNX Runtime.
"""

from __future__ import annotations

import functools
import io
import json
import os
import re
import threading
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np
import onnxruntime as ort
from misaki.espeak import EspeakFallback

MODEL_PATH = os.environ.get(
    "KOKORO_MODEL_PATH", "/Volumes/StudioStorage/tts_models/Kokoro-82M-v1.0-ONNX"
)
HOST = os.environ.get("KOKORO_HOST", "0.0.0.0")
PORT = int(os.environ.get("KOKORO_PORT", "8002"))
DEFAULT_VOICE = os.environ.get("KOKORO_DEFAULT_VOICE", "bf_emma")
DEFAULT_SPEED = float(os.environ.get("KOKORO_DEFAULT_SPEED", "1.0"))
DEFAULT_SPLIT_PATTERN = r"(?<=[.;:!?\n—])\s+"
SAMPLE_RATE = 24000

ONNX_FILE = os.path.join(MODEL_PATH, "onnx", "model_quantized.onnx")
TOKENIZER_FILE = os.path.join(MODEL_PATH, "tokenizer.json")
VOICES_DIR = os.path.join(MODEL_PATH, "voices")

_ROMAN = {
    "I": 1, "II": 2, "III": 3, "IV": 4, "V": 5, "VI": 6, "VII": 7, "VIII": 8,
    "IX": 9, "X": 10, "XI": 11, "XII": 12, "XIII": 13, "XIV": 14, "XV": 15,
    "XVI": 16, "XVII": 17, "XVIII": 18, "XIX": 19, "XX": 20, "XXI": 21,
}
_ROMAN_PAT = "|".join(sorted(_ROMAN, key=len, reverse=True))
_TITLED_ROMAN_RE = re.compile(
    rf"\b((?:King|Queen|Pope|Emperor|Empress|Tsar|Czar|Prince|Princess|Duke|Sultan|Pharaoh)\s+"
    rf"[A-ZÀ-ÖØ-Þ][a-zA-ZÀ-ÿ\-]+(?:\s+[A-ZÀ-ÖØ-Þ][a-zA-ZÀ-ÿ\-]+)?)\s+({_ROMAN_PAT})\b"
)
_NAME_ROMAN_RE = re.compile(rf"\b([A-ZÀ-ÖØ-Þ][a-zÀ-ÿ\-]{{2,}})\s+({_ROMAN_PAT[:-2]})\b")
_CLEAN_RE = re.compile(r"<[^>]+>|\[(?:happy|sad|excited|whisper|angry|laugh|sigh|pause)[^\]]*\]|[*_`#~]+|[\U0001F300-\U0001FAFF\U00002600-\U000027BF]+", re.I)

_lock = threading.Lock()
_abort = threading.Event()
_Token = type("_Token", (), {})


def _ordinal_suffix(n: int) -> str:
    return f"{n}{'tsnrhtdd'[(n // 10 % 10 != 1) * (n % 10 < 4) * n % 10 :: 4]}"


def _normalize(text: str) -> str:
    text = _CLEAN_RE.sub(" ", text)
    text = re.sub(r"!{2,}", "!", re.sub(r"\?{2,}", "?", re.sub(r"\.{4,}", "...", text)))
    text = _TITLED_ROMAN_RE.sub(lambda m: f"{m.group(1)} the {_ordinal_suffix(_ROMAN[m.group(2)])}", text)
    text = _NAME_ROMAN_RE.sub(lambda m: f"{m.group(1)} the {_ordinal_suffix(_ROMAN[m.group(2)])}", text)
    return re.sub(r"\s+", " ", text).strip()


@functools.lru_cache(maxsize=2)
def _get_g2p(british: bool) -> EspeakFallback:
    return EspeakFallback(british=british)


@functools.lru_cache(maxsize=2)
def _load_voice(voice_name: str) -> np.ndarray:
    vpath = os.path.join(VOICES_DIR, f"{voice_name}.bin")
    if not os.path.isfile(vpath):
        vpath = os.path.join(VOICES_DIR, f"{DEFAULT_VOICE}.bin")
    return np.memmap(vpath, dtype=np.float32, mode="r").reshape(-1, 1, 256)


with open(TOKENIZER_FILE, encoding="utf-8") as _f:
    _VOCAB: dict[str, int] = json.load(_f)["model"]["vocab"]

_opts = ort.SessionOptions()
_opts.intra_op_num_threads = 8
_opts.inter_op_num_threads = 1
_opts.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
_opts.enable_cpu_mem_arena = False
_opts.enable_mem_pattern = False
_opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
_SESS = ort.InferenceSession(ONNX_FILE, sess_options=_opts, providers=["CPUExecutionProvider"])
_IN_NAMES = [i.name for i in _SESS.get_inputs()]


def _synthesize_clause(text: str, voice: str, speed: float, pause_ms: float = 100.0) -> bytes:
    tok = _Token()
    tok.text = text
    phonemes, _ = _get_g2p(bool(voice and voice.startswith("b")))(tok)
    if not phonemes:
        return b""
    tokens = [_VOCAB[c] for c in phonemes if c in _VOCAB][:510]
    if not tokens:
        return b""

    pack = _load_voice(voice)
    inputs = {
        _IN_NAMES[0]: np.array([[0, *tokens, 0]], dtype=np.int64),
        _IN_NAMES[1]: np.array(pack[min(len(tokens), len(pack) - 1)], dtype=np.float32),
        _IN_NAMES[2]: np.array([speed], dtype=np.float32),
    }
    with _lock:
        raw = np.asarray(_SESS.run(None, inputs)[0], dtype=np.float32).flatten()

    idx = np.where(np.abs(raw) > 0.0025)[0]
    if idx.size == 0:
        return b""
    start = max(0, int(idx[0]) - int(SAMPLE_RATE * 0.025))
    end = min(len(raw), int(idx[-1]) + int(SAMPLE_RATE * 0.030))
    tail = np.zeros(int(SAMPLE_RATE * (pause_ms / 1000.0)), dtype=np.float32)
    pcm = np.clip(np.concatenate([raw[start:end], tail]), -1.0, 1.0)
    return (pcm * 32767.0).astype(np.int16).tobytes()


class TTSHandler(BaseHTTPRequestHandler):
    def log_message(self, format: str, *args) -> None:
        pass

    def _send_json(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if self.path == "/health":
            self._send_json(200, {"status": "ok", "device": "CPUExecutionProvider (lite)", "model": os.path.basename(MODEL_PATH)})
        elif self.path == "/v1/models":
            self._send_json(200, {"object": "list", "data": [{"id": os.path.basename(MODEL_PATH), "object": "model", "device": "cpu"}]})
        else:
            self._send_json(404, {"error": "Not found"})

    def do_POST(self) -> None:
        if self.path in ("/abort", "/v1/audio/abort"):
            _abort.set()
            self._send_json(200, {"status": "aborted"})
            return
        if self.path != "/v1/audio/speech":
            self._send_json(404, {"error": "Not found"})
            return

        length = int(self.headers.get("Content-Length", "0"))
        req = json.loads(self.rfile.read(length) or b"{}")
        text = _normalize(str(req.get("input", "")))
        if not text:
            self._send_json(400, {"error": "input text must not be empty"})
            return

        _abort.clear()
        voice = str(req.get("voice") or DEFAULT_VOICE)
        speed = float(req.get("speed") or DEFAULT_SPEED)
        pause_ms = float(req.get("pause_ms", 100.0))
        split_pat = req.get("split_pattern", DEFAULT_SPLIT_PATTERN)
        fmt = str(req.get("response_format", "wav")).lower()

        clauses = [p.strip() for p in re.split(split_pat, text) if p and p.strip()] if split_pat else [text]
        pcm_parts = []
        for clause in clauses:
            if _abort.is_set():
                break
            chunk = _synthesize_clause(clause, voice, speed, pause_ms)
            if chunk:
                pcm_parts.append(chunk)

        pcm_bytes = b"".join(pcm_parts)
        if fmt == "pcm":
            self.send_response(200)
            self.send_header("Content-Type", "audio/pcm")
            self.send_header("Content-Length", str(len(pcm_bytes)))
            self.end_headers()
            self.wfile.write(pcm_bytes)
            return

        buf = io.BytesIO()
        with wave.open(buf, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(SAMPLE_RATE)
            wf.writeframes(pcm_bytes)
        wav_bytes = buf.getvalue()
        self.send_response(200)
        self.send_header("Content-Type", "audio/wav")
        self.send_header("Content-Length", str(len(wav_bytes)))
        self.end_headers()
        self.wfile.write(wav_bytes)


if __name__ == "__main__":
    _synthesize_clause("Warmup.", DEFAULT_VOICE, DEFAULT_SPEED)
    ThreadingHTTPServer((HOST, PORT), TTSHandler).serve_forever()
