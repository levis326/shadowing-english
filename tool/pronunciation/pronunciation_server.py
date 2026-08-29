"""Local pronunciation evaluation server (bundled as a self-contained binary).

Mirrors the whisper-server / nllb-server pattern: the app starts this process
once and talks to it over HTTP. It uses the prebuilt CPU PyTorch/TorchAudio
wheels and the wav2vec2-base-960h model to force-align a transcript to the
user's recorded speech, returning an overall score plus per-word scores.

Endpoints:
  GET  /health     -> 200 {"status":"ok"}
  POST /evaluate   -> {"audio": "<base64 wav>", "text": "sentence",
                       "sample_rate": 16000}
                      -> {"score": 0.8, "words": [{"word":"THE","score":0.9}, ...]}

Character-level CTC alignment is used because wav2vec2-base-960h predicts
characters (with '|' as the word boundary token).
"""

import argparse
import base64
import io
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import soundfile as sf
import torch
import torchaudio

BLANK = 0
WORD_BOUNDARY = 1


def text_to_tokens(text, dictionary):
    tokens = []
    for word in text.upper().split():
        for ch in word:
            if ch in dictionary:
                tokens.append(dictionary[ch])
        tokens.append(dictionary["|"])
    if tokens and tokens[-1] == dictionary["|"]:
        tokens.pop()
    return tokens


def score_path(path, log_scores, labels):
    """Convert a forced-alignment path into an overall + per-word score."""
    probs = log_scores.exp()

    # Collapse consecutive CTC repeats, keeping the peak probability of each
    # character (blanks separate genuine repeats and are skipped).
    collapsed = []
    for i in range(path.numel()):
        token = int(path[i])
        if token == BLANK:
            continue
        p = float(probs[i])
        if collapsed and collapsed[-1][0] == token:
            collapsed[-1] = (token, max(collapsed[-1][1], p))
        else:
            collapsed.append((token, p))

    words = []
    chars = []
    char_probs = []
    for token, p in collapsed:
        if token == WORD_BOUNDARY:
            if chars:
                words.append(
                    {
                        "word": "".join(chars),
                        "score": sum(char_probs) / len(char_probs),
                    }
                )
                chars.clear()
                char_probs.clear()
            continue
        chars.append(labels[token])
        char_probs.append(p)
    if chars:
        words.append(
            {"word": "".join(chars), "score": sum(char_probs) / len(char_probs)}
        )

    overall = sum(w["score"] for w in words) / len(words) if words else 0.0
    return {"score": overall, "words": words}


class PronunciationHandler(BaseHTTPRequestHandler):
    model: torch.nn.Module = None
    labels = None
    dictionary = None

    def do_GET(self):
        if self.path == "/health":
            self._write_json(200, {"status": "ok"})
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path != "/evaluate":
            self.send_response(404)
            self.end_headers()
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length) or b"{}")
        except (ValueError, json.JSONDecodeError):
            self._write_json(400, {"error": "invalid-json"})
            return

        text = (body.get("text") or "").strip()
        audio_b64 = body.get("audio") or ""
        sample_rate = body.get("sample_rate") or 16000
        if not text or not audio_b64:
            self._write_json(400, {"error": "missing text or audio"})
            return
        try:
            audio_bytes = base64.b64decode(audio_b64)
        except (ValueError, TypeError):
            self._write_json(400, {"error": "invalid audio base64"})
            return

        try:
            result = self._evaluate(audio_bytes, text, int(sample_rate))
        except Exception as error:  # noqa: BLE001
            self._write_json(500, {"error": str(error)})
            return
        self._write_json(200, result)

    def _evaluate(self, audio_bytes, text, sample_rate):
        data, sr = sf.read(io.BytesIO(audio_bytes), dtype="float32")
        waveform = torch.from_numpy(data.T.copy())
        if waveform.dim() == 1:
            waveform = waveform.unsqueeze(0)
        if sr != 16000:
            waveform = torchaudio.functional.resample(waveform, sr, 16000)

        tokens = text_to_tokens(text, self.dictionary)
        if not tokens:
            return {"score": 0.0, "words": []}

        with torch.inference_mode():
            emission, _ = self.model(waveform)
            emission = torch.log_softmax(emission, dim=-1)
            path, log_scores = torchaudio.functional.forced_align(
                emission,
                torch.tensor([tokens]),
                torch.tensor([emission.shape[1]]),
                torch.tensor([len(tokens)]),
            )
        return score_path(path[0], log_scores[0], self.labels)

    def _write_json(self, status, payload):
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


def main():
    parser = argparse.ArgumentParser(description="Local pronunciation server")
    parser.add_argument(
        "--model-dir",
        required=True,
        help="Directory holding the cached wav2vec2 model "
        "(hub/checkpoints/wav2vec2_fairseq_base_ls960_asr_ls960.pth)",
    )
    parser.add_argument("--port", type=int, default=8082)
    args = parser.parse_args()

    # The bundled model is the torchaudio-cached checkpoint; point TORCH_HOME at
    # it so bundle.get_model() loads locally instead of downloading.
    os.environ["TORCH_HOME"] = args.model_dir
    bundle = torchaudio.pipelines.WAV2VEC2_ASR_BASE_960H
    PronunciationHandler.model = bundle.get_model()
    PronunciationHandler.labels = list(bundle.get_labels())
    PronunciationHandler.dictionary = {
        c: i for i, c in enumerate(PronunciationHandler.labels)
    }

    server = ThreadingHTTPServer(("127.0.0.1", args.port), PronunciationHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()
