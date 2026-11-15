#include <onnxruntime_c_api.h>
#include <espeak-ng/speak_lib.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>

static const OrtApi *g_ort;
static OrtEnv *g_env;
static OrtSession *g_sess;
static OrtMemoryInfo *g_mem;
static char *g_in[3], *g_out[1];
static int g_brit = -1;

#define TRY(expr) do { OrtStatus *_s = (expr); if (_s) { g_ort->ReleaseStatus(_s); return -1; } } while (0)

int kokoro_init(const char *onnx_path, const char *espeak_data, int threads) {
    if (espeak_Initialize(AUDIO_OUTPUT_SYNCHRONOUS, 0, (espeak_data && *espeak_data) ? espeak_data : NULL, 0) < 0) return -1;
    if (espeak_SetVoiceByName("gmw/en") != 0 && espeak_SetVoiceByName("en") != 0) return -1;

    const OrtApiBase *(ORT_API_CALL *get_base)(void) = OrtGetApiBase;
    const char *custom_ort = getenv("ORT_DYLIB_PATH");
    if (custom_ort && *custom_ort) {
        void *h = dlopen(custom_ort, RTLD_LAZY | RTLD_LOCAL);
        if (h) {
            void *sym = dlsym(h, "OrtGetApiBase");
            if (sym) get_base = (const OrtApiBase *(ORT_API_CALL *)(void))sym;
        }
    }
    if (!(g_ort = get_base()->GetApi(17))) return -1;
    TRY(g_ort->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "kokoro", &g_env));

    OrtSessionOptions *opts = NULL;
    TRY(g_ort->CreateSessionOptions(&opts));
    g_ort->SetIntraOpNumThreads(opts, threads);
    g_ort->SetInterOpNumThreads(opts, 1);
    g_ort->SetSessionExecutionMode(opts, ORT_SEQUENTIAL);
    g_ort->DisableCpuMemArena(opts);
    g_ort->DisableMemPattern(opts);
    g_ort->SetSessionGraphOptimizationLevel(opts, ORT_ENABLE_ALL);
    OrtStatus *st = g_ort->CreateSession(g_env, onnx_path, opts, &g_sess);
    g_ort->ReleaseSessionOptions(opts);
    if (st) { g_ort->ReleaseStatus(st); return -1; }

    TRY(g_ort->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &g_mem));
    OrtAllocator *alloc = NULL;
    g_ort->GetAllocatorWithDefaultOptions(&alloc);
    for (size_t i = 0; i < 3; i++) g_ort->SessionGetInputName(g_sess, i, alloc, &g_in[i]);
    g_ort->SessionGetOutputName(g_sess, 0, alloc, &g_out[0]);
    return 0;
}

int kokoro_phonemize_span(const char *text, int british, char *out, size_t cap) {
    if (!text || !*text || !cap) return 0;
    if (g_brit != british) {
        if (espeak_SetVoiceByName(british ? "gmw/en" : "gmw/en-US") != 0) {
            espeak_SetVoiceByName(british ? "en-gb" : "en-us");
        }
        g_brit = british;
    }
    const void *p = text;
    int mode = 0x02 | 0x80 | ((int)'^' << 8);
    size_t n = 0;
    out[0] = '\0';
    while (p && *(const char *)p) {
        const char *r = espeak_TextToPhonemes(&p, espeakCHARS_UTF8, mode);
        if (r && *r) {
            size_t l = strlen(r);
            if (n > 0 && n + 1 < cap) out[n++] = ' ';
            if (n + l < cap) { memcpy(out + n, r, l); n += l; out[n] = '\0'; }
        }
    }
    return (int)n;
}

int kokoro_ort_infer(const int64_t *tok, size_t n_tok, const float *style, float speed, float **out_pcm, size_t *out_len) {
    *out_pcm = NULL; *out_len = 0;
    int64_t s0[2] = { 1, (int64_t)n_tok }, s1[2] = { 1, 256 }, s2[1] = { 1 };
    float spd[1] = { speed };
    OrtValue *in[3] = { NULL, NULL, NULL }, *out = NULL;

    TRY(g_ort->CreateTensorWithDataAsOrtValue(g_mem, (void *)tok, n_tok * 8, s0, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, &in[0]));
    TRY(g_ort->CreateTensorWithDataAsOrtValue(g_mem, (void *)style, 256 * 4, s1, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &in[1]));
    TRY(g_ort->CreateTensorWithDataAsOrtValue(g_mem, spd, 4, s2, 1, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &in[2]));

    OrtStatus *st = g_ort->Run(g_sess, NULL, (const char *const *)g_in, (const OrtValue *const *)in, 3, (const char *const *)g_out, 1, &out);
    for (int i = 0; i < 3; i++) g_ort->ReleaseValue(in[i]);
    if (st) { g_ort->ReleaseStatus(st); return -1; }

    OrtTensorTypeAndShapeInfo *info = NULL;
    g_ort->GetTensorTypeAndShape(out, &info);
    g_ort->GetTensorShapeElementCount(info, out_len);
    g_ort->ReleaseTensorTypeAndShapeInfo(info);

    float *data = NULL;
    g_ort->GetTensorMutableData(out, (void **)&data);
    if (*out_len > 0 && data && (*out_pcm = malloc(*out_len * 4))) memcpy(*out_pcm, data, *out_len * 4);
    g_ort->ReleaseValue(out);
    return 0;
}

void kokoro_free_samples(float *ptr) { free(ptr); }
