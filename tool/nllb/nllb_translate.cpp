// Minimal batch translator for the bundled NLLB-200 CTranslate2 int8 model.
//
// Unlike CTranslate2's stock `ct2-translator` client, this binary performs the
// SentencePiece tokenization itself (the stock client only splits on spaces,
// which is wrong for the NLLB/M2M100 SentencePiece tokenizer) and forces the
// NLLB target language prefix.
//
// Usage:
//   nllb-translate --model <model-dir> --tokenizer <spm-model> \
//       [--src-lang eng_Latn] [--tgt-lang zho_Hans] \
//       --input <input-file> --output <output-file>
//
// Each non-empty line of the input file is translated to one output line.

#include <fstream>
#include <iostream>
#include <string>
#include <vector>

#include <ctranslate2/translation.h>
#include <ctranslate2/translator.h>
#include <sentencepiece_processor.h>

namespace {

struct Options {
  bool show_help = false;
  std::string model_dir;
  std::string tokenizer;
  std::string src_lang = "eng_Latn";
  std::string tgt_lang = "zho_Hans";
  std::string input_file;
  std::string output_file;
};

void PrintHelp() {
  std::cout
      << "nllb-translate: offline NLLB-200 translation client\n"
      << "Usage: nllb-translate --model <dir> --tokenizer <spm> "
         "[--src-lang <code>] [--tgt-lang <code>] --input <file> --output <file>\n";
}

bool ParseArgs(int argc, char* argv[], Options* opts) {
  for (int i = 1; i < argc; ++i) {
    const std::string arg = argv[i];
    if (arg == "--help" || arg == "-h") {
      opts->show_help = true;
      return true;
    }
    if (arg == "--model" && i + 1 < argc) {
      opts->model_dir = argv[++i];
      continue;
    }
    if (arg == "--tokenizer" && i + 1 < argc) {
      opts->tokenizer = argv[++i];
      continue;
    }
    if (arg == "--src-lang" && i + 1 < argc) {
      opts->src_lang = argv[++i];
      continue;
    }
    if (arg == "--tgt-lang" && i + 1 < argc) {
      opts->tgt_lang = argv[++i];
      continue;
    }
    if (arg == "--input" && i + 1 < argc) {
      opts->input_file = argv[++i];
      continue;
    }
    if (arg == "--output" && i + 1 < argc) {
      opts->output_file = argv[++i];
      continue;
    }
    std::cerr << "Unknown or missing value for argument: " << arg << "\n";
    return false;
  }
  return true;
}

}  // namespace

int main(int argc, char* argv[]) {
  Options opts;
  if (!ParseArgs(argc, argv, &opts)) {
    PrintHelp();
    return 1;
  }
  if (opts.show_help) {
    PrintHelp();
    return 0;
  }
  if (opts.model_dir.empty() || opts.tokenizer.empty() ||
      opts.input_file.empty() || opts.output_file.empty()) {
    PrintHelp();
    return 1;
  }

  sentencepiece::SentencePieceProcessor sp;
  const auto sp_status = sp.Load(opts.tokenizer);
  if (!sp_status.ok()) {
    std::cerr << "Failed to load tokenizer: " << sp_status.ToString() << "\n";
    return 1;
  }

  try {
    ctranslate2::models::ModelLoader loader(opts.model_dir);
    loader.device = ctranslate2::Device::CPU;
    // int8_float32 keeps the int8 quantized weights but runs the forward pass
    // in float32, which is well supported on plain CPUs (no MKL/oneDNN needed)
    // and gives better translation quality than the fully-quantized int8 path.
    loader.compute_type = ctranslate2::ComputeType::INT8_FLOAT32;
    ctranslate2::Translator translator(loader);

    std::ifstream input(opts.input_file);
    std::ofstream output(opts.output_file);
    if (!input.is_open() || !output.is_open()) {
      std::cerr << "Failed to open input/output files.\n";
      return 1;
    }

    ctranslate2::TranslationOptions options;
    options.beam_size = 4;
    options.length_penalty = 1.0f;
    options.max_decoding_length = 256;
    options.min_decoding_length = 1;

    std::string line;
    while (std::getline(input, line)) {
      if (line.empty()) {
        output << "\n";
        continue;
      }

      // NLLB source tokens: [source language code] + SentencePiece subwords +
      // [</s>]. The target prefix forces generation to start with the target
      // language code.
      std::vector<std::string> source_tokens;
      source_tokens.push_back(opts.src_lang);
      std::vector<std::string> pieces;
      const auto enc_status = sp.Encode(line, &pieces);
      if (!enc_status.ok()) {
        output << "\n";
        continue;
      }
      source_tokens.insert(source_tokens.end(), pieces.begin(), pieces.end());
      source_tokens.push_back("</s>");

      const auto results = translator.translate_batch(
          std::vector<std::vector<std::string>>{source_tokens},
          std::vector<std::vector<std::string>>{{opts.tgt_lang}},
          options);

      if (results.empty() || results[0].hypotheses.empty()) {
        output << "\n";
        continue;
      }

      const std::vector<std::string>& target_tokens = results[0].hypotheses[0];
      std::vector<std::string> decode_tokens;
      for (size_t i = 0; i < target_tokens.size(); ++i) {
        const std::string& token = target_tokens[i];
        if (i == 0 && token == opts.tgt_lang) {
          continue;  // Drop the forced target-language prefix.
        }
        if (token == "</s>") {
          continue;  // Drop the end-of-sequence token.
        }
        decode_tokens.push_back(token);
      }

      std::string translated;
      if (!decode_tokens.empty()) {
        const auto dec_status = sp.Decode(decode_tokens, &translated);
        if (!dec_status.ok()) {
          translated.clear();
        }
      }
      output << translated << "\n";
    }
  } catch (const std::exception& error) {
    std::cerr << "Translation failed: " << error.what() << "\n";
    return 1;
  }

  return 0;
}
