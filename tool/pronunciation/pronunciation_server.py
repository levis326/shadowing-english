"""Local pronunciation evaluation server (bundled as a self-contained binary).

Mirrors the whisper-server / nllb-server pattern: the app starts this process
once and talks to it over HTTP. It uses the prebuilt CPU PyTorch/TorchAudio
wheels and the wav2vec2-large-960h model to force-align a transcript to the
user's recorded speech, returning an overall score plus per-word and
per-syllable scores.

Endpoints:
  GET  /health     -> 200 {"status":"ok"}
  POST /evaluate   -> {"audio": "<base64 wav>", "text": "sentence",
                        "sample_rate": 16000}
                       -> {"score": 0.8,
                           "words": [{"word": "WEATHER",
                                      "score": 0.7,
                                      "syllables": [
                                          {"syllable": "WEA", "score": 0.9},
                                          {"syllable": "THER", "score": 0.5},
                                      ]}, ...]}

Character-level CTC alignment is used because wav2vec2-large-960h predicts
characters (with '|' as the word boundary token). Syllable scores are derived
by syllabifying each word's spelling and mapping the per-character CTC
probabilities onto the syllables in order.
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
_VOWELS = "AEIOUY"
# Consonant digraphs that belong together inside one syllable.
_DIGRAPHS = {"CH", "CK", "GH", "NG", "PH", "QU", "SH", "TH", "WH", "WR", "KN", "GN"}


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


def syllabify(word):
    """Splits a word's spelling into syllables with a letter-based heuristic.

    Each syllable contains exactly one vowel nucleus (consecutive vowels form
    a single nucleus, so diphthongs stay together). Consonant clusters between
    nuclei are split with simple onset maximization: one consonant goes to the
    following syllable, two are split one each, and longer clusters keep one
    consonant as the previous syllable's coda.

    Examples: "weather" -> ["WEA", "THER"], "computer" -> ["COM", "PU", "TER"].
    """
    letters = [c for c in word.upper() if c.isalpha()]
    if not letters:
        return []

    nuclei = []  # inclusive letter index ranges of vowel nuclei
    index = 0
    while index < len(letters):
        if letters[index] in _VOWELS:
            start = index
            while index + 1 < len(letters) and letters[index + 1] in _VOWELS:
                index += 1
            nuclei.append((start, index))
        index += 1

    if not nuclei:
        return ["".join(letters)]

    boundaries = []  # letter index where each syllable starts
    boundaries.append(0)
    for nucleus_index in range(1, len(nuclei)):
        previous_end = nuclei[nucleus_index - 1][1]
        next_start = nuclei[nucleus_index][0]
        cluster = letters[previous_end + 1 : next_start]
        if len(cluster) <= 1:
            # Attach the single consonant to the following syllable.
            boundaries.append(previous_end + 1)
        elif len(cluster) == 2 and "".join(cluster) in _DIGRAPHS:
            # Keep consonant digraphs (TH, SH, CH, ...) in one syllable.
            boundaries.append(previous_end + 1)
        else:
            # One consonant stays with the previous syllable (coda), the rest
            # starts the next syllable.
            boundaries.append(previous_end + 2)
    last = len(letters)

    syllables = []
    for position, start in enumerate(boundaries):
        end = boundaries[position + 1] if position + 1 < len(boundaries) else last
        syllables.append("".join(letters[start:end]))
    return syllables


def map_chars_to_syllables(observed_chars, char_probs, syllables):
    """Maps ordered per-character CTC probabilities onto syllable spellings.

    Forced alignment runs every transcript character through at least one
    frame, so `observed_chars` matches the word's letters in order — except
    that consecutive identical characters may have collapsed into one (e.g.
    "ll", "ee"). Such doubled letters reuse the previous letter's probability.
    """
    observed = [c for c in observed_chars if c.isalpha()]
    result = []
    observed_index = 0
    for syllable in syllables:
        syllable_scores = []
        for letter in syllable:
            if (
                observed_index < len(observed)
                and observed_index < len(char_probs)
                and observed[observed_index] == letter
            ):
                syllable_scores.append(char_probs[observed_index])
                observed_index += 1
            else:
                # Collapsed doubled letter or a minor mismatch: reuse the
                # probability of the previously seen character.
                if observed_index > 0:
                    syllable_scores.append(char_probs[observed_index - 1])
                elif char_probs:
                    syllable_scores.append(char_probs[0])
                else:
                    syllable_scores.append(0.0)
        result.append(
            {
                "syllable": syllable,
                "score": sum(syllable_scores) / len(syllable_scores),
            }
        )
    return result


def build_word_result(spelling, observed_chars, char_probs):
    """Builds the per-word score plus per-syllable scores for one word.

    `spelling` is the word's true spelling from the transcript; syllable
    boundaries are derived from it. `observed_chars` are the letters actually
    emitted by CTC (consecutive repeats collapsed), with `char_probs` aligned
    to them.
    """
    display_word = "".join(c for c in spelling.upper() if c.isalpha())
    syllables = syllabify(display_word)
    mapped = (
        map_chars_to_syllables(observed_chars, char_probs, syllables)
        if syllables
        else []
    )
    score = (
        sum(item["score"] for item in mapped) / len(mapped)
        if mapped
        else (sum(char_probs) / len(char_probs) if char_probs else 0.0)
    )
    return {"word": display_word, "score": score, "syllables": mapped}


def score_path(path, log_scores, labels, transcript_words):
    """Convert a forced-alignment path into overall + per-word + per-syllable
    scores."""
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
    word_index = 0
    for token, p in collapsed:
        if token == WORD_BOUNDARY:
            if chars:
                spelling = (
                    transcript_words[word_index]
                    if word_index < len(transcript_words)
                    else "".join(chars)
                )
                words.append(build_word_result(spelling, "".join(chars), char_probs))
                chars.clear()
                char_probs.clear()
                word_index += 1
            continue
        chars.append(labels[token])
        char_probs.append(p)
    if chars:
        spelling = (
            transcript_words[word_index]
            if word_index < len(transcript_words)
            else "".join(chars)
        )
        words.append(build_word_result(spelling, "".join(chars), char_probs))

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
        transcript_words = [word for word in text.upper().split()]
        return score_path(path[0], log_scores[0], self.labels, transcript_words)

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
        "(hub/checkpoints/wav2vec2_fairseq_large_ls960_asr_ls960.pth)",
    )
    parser.add_argument("--port", type=int, default=8082)
    args = parser.parse_args()

    # The bundled model is the torchaudio-cached checkpoint; point TORCH_HOME at
    # it so bundle.get_model() loads locally instead of downloading.
    os.environ["TORCH_HOME"] = args.model_dir
    bundle = torchaudio.pipelines.WAV2VEC2_ASR_LARGE_960H
    PronunciationHandler.model = bundle.get_model()
    PronunciationHandler.labels = list(bundle.get_labels())
    PronunciationHandler.dictionary = {
        c: i for i, c in enumerate(PronunciationHandler.labels)
    }

    server = ThreadingHTTPServer(("127.0.0.1", args.port), PronunciationHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()
