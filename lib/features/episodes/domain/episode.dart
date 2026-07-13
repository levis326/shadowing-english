class EpisodeSubtitleTrack {
  const EpisodeSubtitleTrack({
    required this.languageCode,
    required this.languageLabel,
    required this.path,
  });

  final String languageCode;
  final String languageLabel;
  final String path;
}

class Episode {
  const Episode({
    required this.id,
    required this.title,
    required this.videoAsset,
    required this.enSubtitleAsset,
    this.subtitleTracks = const <EpisodeSubtitleTrack>[],
  });

  factory Episode.fromJson(Map<String, Object?> json) {
    return Episode(
      id: json['id']! as String,
      title: json['title']! as String,
      videoAsset: json['videoAsset']! as String,
      enSubtitleAsset: json['enSubtitleAsset']! as String,
      subtitleTracks: ((json['subtitleTracks'] as List<Object?>?) ?? const <Object?>[])
          .cast<Map<String, Object?>>()
          .map(
            (Map<String, Object?> item) => EpisodeSubtitleTrack(
              languageCode: item['languageCode']! as String,
              languageLabel: item['languageLabel']! as String,
              path: item['path']! as String,
            ),
          )
          .toList(growable: false),
    );
  }

  final String id;
  final String title;
  final String videoAsset;
  final String enSubtitleAsset;
  final List<EpisodeSubtitleTrack> subtitleTracks;
}
