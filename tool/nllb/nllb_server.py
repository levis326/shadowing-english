"""Local NLLB-200 translation server (bundled as a self-contained binary).

Mirrors the whisper-server pattern: the app starts this process once and talks
to it over HTTP. It uses the prebuilt `ctranslate2` wheel for inference and the
prebuilt `sentencepiece` wheel for tokenization, so nothing is compiled from
source.

Endpoints:
  GET  /health     -> 200 {"status":"ok"}
  POST /translate  -> {"sentences":[...], "src_lang":"eng_Latn",
                       "tgt_lang":"zho_Hans"}
                      -> {"translations":[...]}
"""

import argparse
import json
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import ctranslate2
import sentencepiece


class TranslateHandler(BaseHTTPRequestHandler):
    translator: ctranslate2.Translator = None
    sp: sentencepiece.SentencePieceProcessor = None
    default_src_lang = "eng_Latn"
    default_tgt_lang = "zho_Hans"

    def do_GET(self):
        if self.path == "/health":
            self._write_json(200, {"status": "ok"})
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path != "/translate":
            self.send_response(404)
            self.end_headers()
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length) or b"{}")
        except (ValueError, json.JSONDecodeError):
            self._write_json(400, {"error": "invalid-json"})
            return
        sentences = body.get("sentences", [])
        src_lang = body.get("src_lang") or self.default_src_lang
        tgt_lang = body.get("tgt_lang") or self.default_tgt_lang
        translations = [
            self._translate_one(text, src_lang, tgt_lang)
            for text in sentences
        ]
        self._write_json(200, {"translations": translations})

    def _translate_one(self, text, src_lang, tgt_lang):
        text = (text or "").strip()
        if not text:
            return ""
        source_tokens = (
            [src_lang] + self.sp.encode(text, out_type=str) + ["</s>"]
        )
        result = self.translator.translate_batch(
            [source_tokens],
            target_prefix=[[tgt_lang]],
        )
        if not result or not result[0].hypotheses:
            return ""
        out_tokens = result[0].hypotheses[0]
        decode_tokens = [
            token
            for i, token in enumerate(out_tokens)
            if not (i == 0 and token == tgt_lang) and token != "</s>"
        ]
        return sanitize_translation(self.sp.decode(decode_tokens))

    def _write_json(self, status, payload):
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        # Silence the default per-request logging.
        pass


def sanitize_translation(text):
    """Removes unknown-token placeholders the model emits for words it cannot
    translate (`⁇` U+2047 is the NLLB tokenizer's unk surface, `�` U+FFFD is
    the generic replacement char), and tightens the spacing around
    punctuation they leave behind."""
    cleaned = text.replace("\u2047", "").replace("\ufffd", "")
    cleaned = re.sub(r"\s+", " ", cleaned)
    cleaned = re.sub(r"\s+([,.;:!?，。；：！？、])", r"\1", cleaned)
    return cleaned.strip()


def main():
    parser = argparse.ArgumentParser(description="Local NLLB translation server")
    parser.add_argument("--model", required=True, help="CTranslate2 model dir")
    parser.add_argument("--tokenizer", required=True, help="SentencePiece model")
    parser.add_argument("--src-lang", default="eng_Latn")
    parser.add_argument("--tgt-lang", default="zho_Hans")
    parser.add_argument("--port", type=int, default=8081)
    args = parser.parse_args()

    TranslateHandler.translator = ctranslate2.Translator(
        args.model,
        device="cpu",
        compute_type="int8_float32",
    )
    TranslateHandler.sp = sentencepiece.SentencePieceProcessor(
        model_file=args.tokenizer,
    )
    TranslateHandler.default_src_lang = args.src_lang
    TranslateHandler.default_tgt_lang = args.tgt_lang

    server = ThreadingHTTPServer(("127.0.0.1", args.port), TranslateHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()
