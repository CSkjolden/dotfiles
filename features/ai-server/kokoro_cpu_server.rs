//! Native Rust CPU + AMX Kokoro ONNX TTS Server (:8002)

use std::collections::HashMap;
use std::ffi::CString;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::os::raw::{c_char, c_float, c_int};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::{env, fs, thread};

extern "C" {
    fn kokoro_init(onnx: *const c_char, espeak: *const c_char, threads: c_int) -> c_int;
    fn kokoro_phonemize_span(text: *const c_char, brit: c_int, out: *mut c_char, cap: usize) -> c_int;
    fn kokoro_ort_infer(tok: *const i64, n: usize, style: *const c_float, spd: c_float, pcm: *mut *mut c_float, len: *mut usize) -> c_int;
    fn kokoro_free_samples(ptr: *mut c_float);
}

const SR: usize = 24000;
const ROMANS: &[&str] = &["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX", "XXI"];
const TITLES: &[&str] = &["King", "Queen", "Pope", "Emperor", "Empress", "Tsar", "Czar", "Prince", "Princess", "Duke", "Sultan", "Pharaoh"];
const E2M: &[(&str, &str)] = &[
    ("ʔˌn\u{0329}", "ʔn"), ("ʔn\u{0329}", "ʔn"), ("a^ɪ", "I"), ("a^ʊ", "W"), ("d^ʒ", "ʤ"), ("e^ɪ", "A"),
    ("e", "A"), ("t^ʃ", "ʧ"), ("ɔ^ɪ", "Y"), ("ə^l", "ᵊl"), ("ʲo", "jo"), ("ʲə", "jə"), ("ʲ", ""),
    ("ɚ", "əɹ"), ("r", "ɹ"), ("x", "k"), ("ç", "k"), ("ɐ", "ə"), ("ɬ", "l"), ("\u{0303}", ""),
];

struct State {
    dir: String,
    voice: String,
    speed: f32,
    vocab: HashMap<char, i64>,
    voices: Mutex<HashMap<String, Vec<f32>>>,
    lock: Mutex<()>,
    abort: AtomicBool,
}

fn unescape(s: &str) -> String {
    let (mut out, mut it) = (String::with_capacity(s.len()), s.chars());
    while let Some(c) = it.next() {
        if c != '\\' { out.push(c); continue; }
        match it.next() {
            Some('n') => out.push('\n'), Some('r') => out.push('\r'), Some('t') => out.push('\t'),
            Some('u') => {
                let hex: String = it.by_ref().take(4).collect();
                if let Some(ch) = u32::from_str_radix(&hex, 16).ok().and_then(char::from_u32) { out.push(ch); }
            }
            Some(o) => out.push(o), None => break,
        }
    }
    out
}

fn parse_vocab(raw: &str) -> HashMap<char, i64> {
    let mut map = HashMap::new();
    let Some(s) = raw.find("\"vocab\"").and_then(|p| raw[p..].find('{').map(|b| p + b + 1)) else { return map };
    for entry in raw[s..].split('}').next().unwrap_or("").split(',') {
        let Some((k, v)) = entry.split_once(':') else { continue };
        let k = unescape(k.trim().trim_matches('"'));
        if let (Some(ch), None, Ok(id)) = (k.chars().next(), k.chars().nth(1), v.trim().parse::<i64>()) {
            map.insert(ch, id);
        }
    }
    map
}

fn json_str(body: &str, key: &str) -> Option<String> {
    let rest = body.split(&format!("\"{}\"", key)).nth(1)?.split_once(':')?.1.trim_start();
    if !rest.starts_with('"') { return None; }
    let (mut i, b) = (1, rest.as_bytes());
    while i < b.len() {
        if b[i] == b'\\' { i += 2; } else if b[i] == b'"' { return Some(unescape(&rest[1..i])); } else { i += 1; }
    }
    None
}

fn json_f32(body: &str, key: &str) -> Option<f32> {
    let s = body.split(&format!("\"{}\"", key)).nth(1)?.split_once(':')?.1.trim_start();
    s[..s.find(|c: char| !c.is_ascii_digit() && c != '.' && c != '-').unwrap_or(s.len())].parse().ok()
}

fn normalize(input: &str) -> String {
    let (mut clean, mut in_tag) = (String::with_capacity(input.len()), false);
    for ch in input.chars() {
        if ch == '<' { in_tag = true; clean.push(' '); }
        else if ch == '>' { in_tag = false; }
        else if !in_tag && !matches!(ch, '*' | '_' | '`' | '#' | '~') && (ch as u32) < 0x1F300 { clean.push(ch); }
    }
    let words: Vec<&str> = clean.split_whitespace().collect();
    words.iter().enumerate().map(|(i, &w)| {
        let core = w.trim_end_matches(|c: char| c.is_ascii_punctuation());
        let punct = &w[core.len()..];
        if i > 0 {
            let prev = words[i - 1].trim_matches(|c: char| c.is_ascii_punctuation());
            let is_name = prev.chars().next().map_or(false, |c| c.is_uppercase()) && prev.len() >= 2;
            let titled = i >= 2 && TITLES.contains(&words[i - 2].trim_matches(|c: char| c.is_ascii_punctuation()));
            if is_name && (core != "I" || titled) {
                if let Some(idx) = ROMANS.iter().position(|&r| r == core) {
                    let n = idx + 1;
                    let suf = match (n % 10, n % 100) { (1, 11) | (2, 12) | (3, 13) => "th", (1, _) => "st", (2, _) => "nd", (3, _) => "rd", _ => "th" };
                    return format!("the {}{}{}", n, suf, punct);
                }
            }
        }
        w.to_string()
    }).collect::<Vec<_>>().join(" ")
}

fn is_punct(c: char) -> bool { matches!(c, '.' | ',' | ';' | ':' | '!' | '?' | '-' | '—' | '…' | '"' | '“' | '”') }

fn phonemize(text: &str, brit: bool) -> String {
    let (mut out, mut span, mut buf) = (String::new(), String::new(), vec![0u8; 4096]);
    let flush = |span: &mut String, out: &mut String, buf: &mut [u8]| {
        if let Ok(cs) = CString::new(span.trim()) {
            if !cs.as_bytes().is_empty() {
                let n = unsafe { kokoro_phonemize_span(cs.as_ptr(), brit as c_int, buf.as_mut_ptr() as *mut c_char, buf.len()) };
                if n > 0 {
                    let mut s = String::from_utf8_lossy(&buf[..n as usize]).into_owned();
                    for &(k, v) in E2M { s = s.replace(k, v); }
                    s = s.replace('\u{0329}', "");
                    s = if brit { s.replace("e^ə", "ɛː").replace("iə", "ɪə").replace("ə^ʊ", "Q") }
                        else { s.replace("o^ʊ", "O").replace("ɜːɹ", "ɜɹ").replace("ɜː", "ɜɹ").replace("ɪə", "iə").replace("ː", "") };
                    s = s.replace('o', "ɔ").replace('ɾ', "T").replace('ʔ', "t").replace('^', "");
                    if !out.is_empty() && !out.ends_with(' ') { out.push(' '); }
                    out.push_str(s.trim());
                }
            }
        }
        span.clear();
    };
    for ch in text.chars() {
        if is_punct(ch) { flush(&mut span, &mut out, &mut buf); out.push(ch); }
        else { if out.ends_with(is_punct) && ch.is_whitespace() { out.push(' '); } span.push(ch); }
    }
    flush(&mut span, &mut out, &mut buf);
    out
}

impl State {
    fn voice_pack(&self, name: &str) -> Vec<f32> {
        let mut cache = self.voices.lock().unwrap();
        if let Some(v) = cache.get(name) { return v.clone(); }
        let p = format!("{}/voices/{}.bin", self.dir, name);
        let bytes = fs::read(&p).or_else(|_| fs::read(format!("{}/voices/{}.bin", self.dir, self.voice))).unwrap_or_default();
        let v: Vec<f32> = bytes.chunks_exact(4).map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]])).collect();
        if cache.len() >= 2 { cache.clear(); }
        cache.insert(name.to_string(), v.clone());
        v
    }

    fn synth(&self, text: &str, voice: &str, speed: f32, pause_ms: f32) -> Vec<u8> {
        let _g = self.lock.lock().unwrap();
        let ipa = phonemize(text, voice.starts_with('b'));
        let mut tok = vec![0i64];
        tok.extend(ipa.chars().filter_map(|c| self.vocab.get(&c).copied()).take(510));
        if tok.len() <= 1 { return Vec::new(); }
        tok.push(0);

        let pack = self.voice_pack(voice);
        if pack.len() < 256 { return Vec::new(); }
        let style_idx = (tok.len() - 2).min(pack.len() / 256 - 1) * 256;
        let (mut ptr, mut len) = (std::ptr::null_mut(), 0usize);
        if unsafe { kokoro_ort_infer(tok.as_ptr(), tok.len(), pack[style_idx..].as_ptr(), speed, &mut ptr, &mut len) } != 0 || ptr.is_null() {
            return Vec::new();
        }
        let raw = unsafe { std::slice::from_raw_parts(ptr, len) };
        let mut pcm = Vec::new();
        if let (Some(f), Some(l)) = (raw.iter().position(|&x| x.abs() > 0.0025), raw.iter().rposition(|&x| x.abs() > 0.0025)) {
            let (s, e, tail) = (f.saturating_sub(SR * 25 / 1000), (l + SR * 30 / 1000).min(raw.len()), (SR as f32 * pause_ms / 1000.0) as usize);
            pcm.reserve((e - s + tail) * 2);
            for &x in &raw[s..e] { pcm.extend_from_slice(&((x.clamp(-1.0, 1.0) * 32767.0) as i16).to_le_bytes()); }
            pcm.resize(pcm.len() + tail * 2, 0);
        }
        unsafe { kokoro_free_samples(ptr) };
        pcm
    }
}

fn split_sentences(text: &str) -> Vec<String> {
    let (mut out, mut cur, mut it) = (Vec::new(), String::new(), text.chars().peekable());
    while let Some(c) = it.next() {
        cur.push(c);
        if matches!(c, '.' | ';' | ':' | '!' | '?' | '\n' | '—') {
            while it.peek().map_or(false, |&n| matches!(n, '.' | ';' | ':' | '!' | '?' | '\n' | '—')) { cur.push(it.next().unwrap()); }
            if it.peek().map_or(true, |ch| ch.is_whitespace()) && !cur.trim().is_empty() { out.push(cur.trim().to_string()); cur.clear(); }
        }
    }
    if !cur.trim().is_empty() { out.push(cur.trim().to_string()); }
    out
}

fn send(s: &mut TcpStream, code: &str, ct: &str, body: &[u8]) {
    let _ = write!(s, "HTTP/1.1 {code}\r\nContent-Type: {ct}\r\nContent-Length: {}\r\nConnection: keep-alive\r\n\r\n", body.len());
    let _ = s.write_all(body);
}

fn handle(mut s: TcpStream, st: Arc<State>) {
    let mut buf = [0u8; 8192];
    loop {
        let (mut req, mut h_end) = (Vec::new(), None);
        while h_end.is_none() {
            let Ok(n) = s.read(&mut buf) else { return };
            if n == 0 { return; }
            req.extend_from_slice(&buf[..n]);
            h_end = req.windows(4).position(|w| w == b"\r\n\r\n").map(|p| p + 4);
        }
        let he = h_end.unwrap();
        let hdr = String::from_utf8_lossy(&req[..he]).into_owned();
        let mut parts = hdr.lines().next().unwrap_or("").split_whitespace();
        let (method, path) = (parts.next().unwrap_or(""), parts.next().unwrap_or(""));
        let clen: usize = hdr.lines().filter_map(|l| l.split_once(':')).find(|(k, _)| k.trim().eq_ignore_ascii_case("content-length")).and_then(|(_, v)| v.trim().parse().ok()).unwrap_or(0);
        while req.len() < he + clen {
            let Ok(n) = s.read(&mut buf) else { return };
            if n == 0 { return; }
            req.extend_from_slice(&buf[..n]);
        }
        match (method, path) {
            ("GET", "/health") => send(&mut s, "200 OK", "application/json", br#"{"status":"ok","device":"Rust Native CPU + AMX","model":"Kokoro-82M-v1.0-ONNX"}"#),
            ("GET", "/v1/models") => send(&mut s, "200 OK", "application/json", br#"{"object":"list","data":[{"id":"Kokoro-82M-v1.0-ONNX","object":"model","device":"cpu"}]}"#),
            ("POST", "/abort" | "/v1/audio/abort") => { st.abort.store(true, Ordering::SeqCst); send(&mut s, "200 OK", "application/json", br#"{"status":"aborted"}"#); }
            ("POST", "/v1/audio/speech") => {
                let body = String::from_utf8_lossy(&req[he..he + clen]);
                let text = normalize(&json_str(&body, "input").unwrap_or_default());
                if text.is_empty() { send(&mut s, "400 Bad Request", "application/json", br#"{"error":"empty input"}"#); continue; }
                st.abort.store(false, Ordering::SeqCst);
                let voice = json_str(&body, "voice").unwrap_or_else(|| st.voice.clone());
                let speed = json_f32(&body, "speed").unwrap_or(st.speed);
                let pause = json_f32(&body, "pause_ms").unwrap_or(100.0);
                let mut pcm = Vec::new();
                for cl in split_sentences(&text) {
                    if st.abort.load(Ordering::SeqCst) { break; }
                    pcm.extend_from_slice(&st.synth(&cl, &voice, speed, pause));
                }
                if json_str(&body, "response_format").unwrap_or_default().eq_ignore_ascii_case("pcm") {
                    send(&mut s, "200 OK", "audio/pcm", &pcm);
                } else {
                    let (dl, fl) = (pcm.len() as u32, 36 + pcm.len() as u32);
                    let mut wav = Vec::with_capacity(44 + pcm.len());
                    wav.extend_from_slice(b"RIFF"); wav.extend_from_slice(&fl.to_le_bytes());
                    wav.extend_from_slice(b"WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\xc0\x5d\x00\x00\x80\xbb\x00\x00\x02\x00\x10\x00data");
                    wav.extend_from_slice(&dl.to_le_bytes()); wav.extend_from_slice(&pcm);
                    send(&mut s, "200 OK", "audio/wav", &wav);
                }
            }
            _ => send(&mut s, "404 Not Found", "application/json", br#"{"error":"not found"}"#),
        }
    }
}

fn main() {
    let dir = env::var("KOKORO_MODEL_PATH").unwrap_or_else(|_| "/Volumes/StudioStorage/tts_models/Kokoro-82M-v1.0-ONNX".into());
    let host = env::var("KOKORO_HOST").unwrap_or_else(|_| "0.0.0.0".into());
    let port: u16 = env::var("KOKORO_PORT").ok().and_then(|s| s.parse().ok()).unwrap_or(8002);
    let voice = env::var("KOKORO_DEFAULT_VOICE").unwrap_or_else(|_| "bf_emma".into());
    let speed: f32 = env::var("KOKORO_DEFAULT_SPEED").ok().and_then(|s| s.parse().ok()).unwrap_or(1.0);
    let onnx = CString::new(format!("{dir}/onnx/model_quantized.onnx")).unwrap();
    let espeak = CString::new(env::var("ESPEAK_DATA_PATH").unwrap_or_default()).unwrap();
    assert!(unsafe { kokoro_init(onnx.as_ptr(), espeak.as_ptr(), 8) } == 0, "ORT/espeak init failed");

    let vocab = parse_vocab(&fs::read_to_string(format!("{dir}/tokenizer.json")).expect("missing tokenizer.json"));
    let st = Arc::new(State { dir, voice: voice.clone(), speed, vocab, voices: Mutex::new(HashMap::new()), lock: Mutex::new(()), abort: AtomicBool::new(false) });
    let _ = st.synth("Warmup.", &voice, speed, 100.0);

    let listener = TcpListener::bind((host.as_str(), port)).expect("bind failed");
    for stream in listener.incoming().flatten() {
        let st = Arc::clone(&st);
        thread::spawn(move || handle(stream, st));
    }
}
