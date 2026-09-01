"""Smoke test for the upgraded pronunciation server logic + model.

Usage: .venv_pron/bin/python tool/pronunciation/smoke_test_local.py [model-dir]
"""
import io
import json
import os
import sys

import numpy as np
import soundfile as sf
import torch
import torchaudio

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__))))
import pronunciation_server as ps  # noqa: E402

MODEL_DIR = sys.argv[1] if len(sys.argv) > 1 else ".cache_model"

# --- Pure logic checks -----------------------------------------------------
assert ps.syllabify("WEATHER") == ["WEA", "THER"], ps.syllabify("WEATHER")
assert ps.syllabify("COMPUTER") == ["COM", "PU", "TER"], ps.syllabify("COMPUTER")
assert ps.syllabify("STUDENT") == ["STU", "DENT"], ps.syllabify("STUDENT")
assert ps.syllabify("SHADOWING") == ["SHA", "DO", "WING"], ps.syllabify("SHADOWING")
assert ps.syllabify("THE") == ["THE"], ps.syllabify("THE")
assert ps.syllabify("HELLO") == ["HEL", "LO"], ps.syllabify("HELLO")

word = ps.build_word_result(
    "WEATHER", "WEATHER", [0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3]
)
assert word["word"] == "WEATHER"
assert [s["syllable"] for s in word["syllables"]] == ["WEA", "THER"]
assert abs(word["syllables"][0]["score"] - 0.8) < 1e-9
assert abs(word["syllables"][1]["score"] - 0.45) < 1e-9

# Syllable boundaries come from the word's TRUE spelling, while the observed
# letters come from CTC (consecutive repeats collapsed, so "HELLO" arrives as
# "HELO" with one probability per observed letter).
word = ps.build_word_result("HELLO", "HELO", [0.9, 0.8, 0.7, 0.6])
assert word["word"] == "HELLO"
assert [s["syllable"] for s in word["syllables"]] == ["HEL", "LO"]
assert abs(word["syllables"][0]["score"] - (0.9 + 0.8 + 0.7) / 3) < 1e-9
assert abs(word["syllables"][1]["score"] - (0.7 + 0.6) / 2) < 1e-9
print("pure checks OK")

# --- End-to-end check against the real large-960h model --------------------
os.environ["TORCH_HOME"] = MODEL_DIR
bundle = torchaudio.pipelines.WAV2VEC2_ASR_LARGE_960H
model = bundle.get_model()
labels = list(bundle.get_labels())
dictionary = {c: i for i, c in enumerate(labels)}
ps.PronunciationHandler.model = model
ps.PronunciationHandler.labels = labels
ps.PronunciationHandler.dictionary = dictionary

sr = 16000
t = np.linspace(0, 2.0, sr * 2, endpoint=False)
audio = (0.1 * np.sin(2 * np.pi * 220 * t)).astype("float32")
buffer = io.BytesIO()
sf.write(buffer, audio, sr, format="WAV")

handler = ps.PronunciationHandler
result = handler._evaluate(handler, buffer.getvalue(), "hello world", sr)
print(json.dumps(result, ensure_ascii=False, indent=2))
assert result["words"], "expected at least one word"
assert all("syllables" in w for w in result["words"])
assert result["words"][0]["syllables"], "expected syllable scores"
print("SMOKE_OK")
