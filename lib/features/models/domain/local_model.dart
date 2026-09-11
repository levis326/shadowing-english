import 'dart:io';

/// 本地模型类别。
enum LocalModelKind { whisper, translation, pronunciation }

/// Hugging Face 镜像（主下载源）与官方源（回退）。
const String hfMirrorBaseUrl = 'https://hf-mirror.com';
const String hfBaseUrl = 'https://huggingface.co';

/// 单个模型文件：从哪里下载、校验值、保存位置。
class LocalModelFile {
  const LocalModelFile({
    required this.fileName,
    required this.repoPath,
    required this.sha256,
    required this.sizeBytes,
    this.subPath = '',
    this.absoluteUrl,
  });

  /// 保存到模型目录时的文件名。
  final String fileName;

  /// Hugging Face 仓库内路径（形如 `owner/repo/resolve/main/file.bin`）。
  final String repoPath;

  /// 期望的 SHA-256（小写十六进制）。
  final String sha256;

  /// 文件字节数，用于展示与「已下载」判断。
  final int sizeBytes;

  /// 相对模型目录的子目录（发音模型需要 `hub/checkpoints`）。
  final String subPath;

  /// 不在 Hugging Face 上托管时的完整地址（发音模型使用）。
  final String? absoluteUrl;

  String get mirrorUrl => absoluteUrl ?? '$hfMirrorBaseUrl/$repoPath';

  String get fallbackUrl => absoluteUrl ?? '$hfBaseUrl/$repoPath';
}

/// 一个可下载的本地模型（可能包含多个文件）。
class LocalModelInfo {
  const LocalModelInfo({
    required this.id,
    required this.kind,
    required this.name,
    required this.description,
    required this.files,
    this.recommended = false,
    this.sourceNote = 'Hugging Face 镜像（hf-mirror.com）',
  });

  final String id;
  final LocalModelKind kind;
  final String name;
  final String description;
  final List<LocalModelFile> files;

  /// 是否为该类别推荐使用的模型。
  final bool recommended;

  /// 下载源说明（发音模型来自 PyTorch 官方 CDN）。
  final String sourceNote;

  int get totalBytes =>
      files.fold<int>(0, (int sum, LocalModelFile file) => sum + file.sizeBytes);

  String get sizeLabel => formatModelSize(totalBytes);

  /// 主要用于展示：单文件模型显示文件名，多文件模型显示主文件。
  String get mainFileName => files.first.fileName;
}

/// 把字节数格式化成易读文本。
String formatModelSize(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    final double gb = bytes / (1024 * 1024 * 1024);
    return '约 ${gb.toStringAsFixed(gb >= 10 ? 0 : 1)} GB';
  }
  final double mb = bytes / (1024 * 1024);
  return '约 ${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
}

const String _whisperRepo = 'ggerganov/whisper.cpp/resolve/main';

/// 可下载的本地模型清单。
///
/// 每类模型的顺序即为界面展示顺序，`recommended: true` 的模型带「推荐」标记，
/// 并在用户未手动选择时优先使用。
const List<LocalModelInfo> localModels = <LocalModelInfo>[
  // ---------------- 语音识别（AI 字幕） ----------------
  LocalModelInfo(
    id: 'whisper-small',
    kind: LocalModelKind.whisper,
    name: 'Whisper small（多语言）',
    description: '速度与准确率平衡最好，适合大多数电脑；中英混读识别稳定。',
    recommended: true,
    files: <LocalModelFile>[
      LocalModelFile(
        fileName: 'ggml-small.bin',
        repoPath: '$_whisperRepo/ggml-small.bin',
        sha256: '1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b',
        sizeBytes: 487601967,
      ),
    ],
  ),
  LocalModelInfo(
    id: 'whisper-base',
    kind: LocalModelKind.whisper,
    name: 'Whisper base（轻量）',
    description: '体积小、速度最快，准确率一般，适合低配电脑或快速试听。',
    files: <LocalModelFile>[
      LocalModelFile(
        fileName: 'ggml-base.bin',
        repoPath: '$_whisperRepo/ggml-base.bin',
        sha256: '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe',
        sizeBytes: 147951465,
      ),
    ],
  ),
  LocalModelInfo(
    id: 'whisper-tiny',
    kind: LocalModelKind.whisper,
    name: 'Whisper tiny（极速）',
    description: '最小最快，准确率最低，仅建议在很慢的电脑上应急使用。',
    files: <LocalModelFile>[
      LocalModelFile(
        fileName: 'ggml-tiny.bin',
        repoPath: '$_whisperRepo/ggml-tiny.bin',
        sha256: 'be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21',
        sizeBytes: 77691713,
      ),
    ],
  ),
  LocalModelInfo(
    id: 'whisper-medium',
    kind: LocalModelKind.whisper,
    name: 'Whisper medium（更准）',
    description: '识别更准，速度明显变慢，建议 8 核以上 CPU 使用。',
    files: <LocalModelFile>[
      LocalModelFile(
        fileName: 'ggml-medium.bin',
        repoPath: '$_whisperRepo/ggml-medium.bin',
        sha256: '6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208',
        sizeBytes: 1533763059,
      ),
    ],
  ),
  LocalModelInfo(
    id: 'whisper-large-v3-turbo',
    kind: LocalModelKind.whisper,
    name: 'Whisper large-v3 turbo（高精度）',
    description: '接近 large 的准确率、速度更快；需要较多内存与磁盘空间。',
    files: <LocalModelFile>[
      LocalModelFile(
        fileName: 'ggml-large-v3-turbo.bin',
        repoPath: '$_whisperRepo/ggml-large-v3-turbo.bin',
        sha256: '1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69',
        sizeBytes: 1624555275,
      ),
    ],
  ),
  LocalModelInfo(
    id: 'whisper-large-v3',
    kind: LocalModelKind.whisper,
    name: 'Whisper large-v3（最准）',
    description: '准确率最高，速度最慢、体积最大，建议高性能电脑使用。',
    files: <LocalModelFile>[
      LocalModelFile(
        fileName: 'ggml-large-v3.bin',
        repoPath: '$_whisperRepo/ggml-large-v3.bin',
        sha256: '64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2',
        sizeBytes: 3095033483,
      ),
    ],
  ),

  // ---------------- 中文翻译（双语字幕） ----------------
  LocalModelInfo(
    id: 'nllb-1.3b',
    kind: LocalModelKind.translation,
    name: 'NLLB-200 1.3B（推荐）',
    description: '译文质量明显优于 600M，长句和口语表达更自然；推荐默认使用。',
    recommended: true,
    files: <LocalModelFile>[
      LocalModelFile(
        fileName: 'model.bin',
        repoPath:
            'Code-Dev/nllb-200-distilled-1.3B-ct2-int8/resolve/main/model.bin',
        sha256: '645d63967bee99a99dfffe78bd4ee1be80bd8adbe64624549774a81ccbad9ec2',
        sizeBytes: 1381827201,
      ),
      LocalModelFile(
        fileName: 'shared_vocabulary.json',
        repoPath:
            'Code-Dev/nllb-200-distilled-1.3B-ct2-int8/resolve/main/shared_vocabulary.json',
        sha256: 'af53bfd0e6f726209e7325e45b87ab3b14e5856f7d42d7b9be91de3287c45267',
        sizeBytes: 5921176,
      ),
      LocalModelFile(
        fileName: 'config.json',
        repoPath:
            'Code-Dev/nllb-200-distilled-1.3B-ct2-int8/resolve/main/config.json',
        sha256: '8f6496adfc930cbfecbe8281112197705c488fab47d34b4829b06d7f478909af',
        sizeBytes: 223,
      ),
      LocalModelFile(
        fileName: 'sentencepiece.bpe.model',
        repoPath:
            'facebook/nllb-200-distilled-1.3B/resolve/main/sentencepiece.bpe.model',
        sha256: '14bb8dfb35c0ffdea7bc01e56cea38b9e3d5efcdcb9c251d6b40538e1aab555a',
        sizeBytes: 4852054,
      ),
    ],
  ),
  LocalModelInfo(
    id: 'nllb-600m',
    kind: LocalModelKind.translation,
    name: 'NLLB-200 600M（更快）',
    description: '体积小、翻译更快，个别生僻词会漏译；适合低配电脑。',
    files: <LocalModelFile>[
      LocalModelFile(
        fileName: 'model.bin',
        repoPath:
            'mijuanlo/nllb-200-distilled-600M-ct2-int8/resolve/main/model.bin',
        sha256: '398726640cc2a02cc6a35277fa3cf2159ce8a1a66b48aa1b6c8837a47e3dd00c',
        sizeBytes: 622596105,
      ),
      LocalModelFile(
        fileName: 'shared_vocabulary.json',
        repoPath:
            'mijuanlo/nllb-200-distilled-600M-ct2-int8/resolve/main/shared_vocabulary.json',
        sha256: 'af53bfd0e6f726209e7325e45b87ab3b14e5856f7d42d7b9be91de3287c45267',
        sizeBytes: 5921176,
      ),
      LocalModelFile(
        fileName: 'config.json',
        repoPath:
            'mijuanlo/nllb-200-distilled-600M-ct2-int8/resolve/main/config.json',
        sha256: 'bf8ade7c3f1683e5f13001bab18b04a1ccd1a6801208efd227ed13b2ff6f15e7',
        sizeBytes: 1065,
      ),
      LocalModelFile(
        fileName: 'sentencepiece.bpe.model',
        repoPath:
            'facebook/nllb-200-distilled-600M/resolve/main/sentencepiece.bpe.model',
        sha256: '14bb8dfb35c0ffdea7bc01e56cea38b9e3d5efcdcb9c251d6b40538e1aab555a',
        sizeBytes: 4852054,
      ),
    ],
  ),

  // ---------------- 发音评测（跟读打分） ----------------
  LocalModelInfo(
    id: 'pronunciation-large-960h',
    kind: LocalModelKind.pronunciation,
    name: 'wav2vec2 large 960h（推荐）',
    description: '跟读打分更准，逐词/音节评分更可靠；推荐默认使用。',
    recommended: true,
    sourceNote: 'PyTorch 官方 CDN（该检查点未托管在 Hugging Face）',
    files: <LocalModelFile>[
      LocalModelFile(
        fileName: 'wav2vec2_fairseq_large_ls960_asr_ls960.pth',
        repoPath: '',
        absoluteUrl:
            'https://download.pytorch.org/torchaudio/models/wav2vec2_fairseq_large_ls960_asr_ls960.pth',
        sha256: 'f45e55ccb71e0f0c7dc52d519c29524213a2d41da7761f71089f11bf3ea40702',
        sizeBytes: 1262000857,
        subPath: 'hub/checkpoints',
      ),
    ],
  ),
  LocalModelInfo(
    id: 'pronunciation-base-960h',
    kind: LocalModelKind.pronunciation,
    name: 'wav2vec2 base 960h（轻量）',
    description: '体积小、启动快，打分精度低于 large 版本。',
    sourceNote: 'PyTorch 官方 CDN（该检查点未托管在 Hugging Face）',
    files: <LocalModelFile>[
      LocalModelFile(
        fileName: 'wav2vec2_fairseq_base_ls960_asr_ls960.pth',
        repoPath: '',
        absoluteUrl:
            'https://download.pytorch.org/torchaudio/models/wav2vec2_fairseq_base_ls960_asr_ls960.pth',
        sha256: '488fd4f16de84438ffc945334278c1b9fb9b7159a806c1080b16111a958c945d',
        sizeBytes: 377664473,
        subPath: 'hub/checkpoints',
      ),
    ],
  ),
];

/// 按类别筛选模型清单。
List<LocalModelInfo> localModelsOfKind(LocalModelKind kind) => localModels
    .where((LocalModelInfo model) => model.kind == kind)
    .toList(growable: false);

/// 按 id 查找模型。
LocalModelInfo? localModelById(String id) {
  for (final LocalModelInfo model in localModels) {
    if (model.id == id) {
      return model;
    }
  }
  return null;
}

/// 类别显示名。
String localModelKindLabel(LocalModelKind kind) {
  switch (kind) {
    case LocalModelKind.whisper:
      return '语音识别（AI 生成字幕）';
    case LocalModelKind.translation:
      return '中文翻译（双语字幕）';
    case LocalModelKind.pronunciation:
      return '发音评测（跟读打分）';
  }
}

/// 文件所在的完整路径。
String localModelFilePath(Directory modelDir, LocalModelFile file) {
  final String base = file.subPath.isEmpty
      ? modelDir.path
      : '${modelDir.path}${Platform.pathSeparator}'
            '${file.subPath.replaceAll('/', Platform.pathSeparator)}';
  return '$base${Platform.pathSeparator}${file.fileName}';
}
