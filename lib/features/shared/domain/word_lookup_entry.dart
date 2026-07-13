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

  final String word;
  final String phonetic;
  final String type;
  final String definitionEn;
  final String usageEn;
  final String exampleSentenceEn;
  final String definitionCn;
  final String sourceLabel;
  final String? contextMeaningCn;
}
