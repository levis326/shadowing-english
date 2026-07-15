class WordLookupEntry {
  const WordLookupEntry({
    required this.word,
    required this.phonetic,
    required this.type,
    required this.definitionEn,
    required this.usageEn,
    required this.exampleSentenceEn,
    required this.definitionCn,
    required this.sourceLabel,
    this.contextMeaningCn,
  });

  factory WordLookupEntry.fromJson(Map<dynamic, dynamic> json) {
    return WordLookupEntry(
      word: json['word'] as String? ?? '',
      phonetic: json['phonetic'] as String? ?? '',
      type: json['type'] as String? ?? '',
      definitionEn: json['definitionEn'] as String? ?? '',
      usageEn: json['usageEn'] as String? ?? '',
      exampleSentenceEn: json['exampleSentenceEn'] as String? ?? '',
      definitionCn: json['definitionCn'] as String? ?? '',
      sourceLabel: json['sourceLabel'] as String? ?? '',
      contextMeaningCn: json['contextMeaningCn'] as String?,
    );
  }

  final String word;
  final String phonetic;
  final String type;
  final String definitionEn;
  final String usageEn;
  final String exampleSentenceEn;
  final String definitionCn;
  final String sourceLabel;
  final String? contextMeaningCn;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'word': word,
    'phonetic': phonetic,
    'type': type,
    'definitionEn': definitionEn,
    'usageEn': usageEn,
    'exampleSentenceEn': exampleSentenceEn,
    'definitionCn': definitionCn,
    'sourceLabel': sourceLabel,
    'contextMeaningCn': contextMeaningCn,
  };
}
