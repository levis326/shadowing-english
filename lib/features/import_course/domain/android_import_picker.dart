import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidImportDirectorySelection {
  const AndroidImportDirectorySelection({
    required this.folderName,
    required this.label,
    required this.files,
    required this.sourceUris,
  });

  final String folderName;
  final String label;
  final List<String> files;
  final Map<String, String> sourceUris;
}

const MethodChannel _channel = MethodChannel(
  'com.shadowing.english/import_picker',
);

Future<AndroidImportDirectorySelection?> pickAndroidImportDirectory({
  required String title,
  required List<String> extensions,
  bool copyFiles = true,
}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return null;
  }

  final Map<Object?, Object?>? result = await _channel
      .invokeMapMethod<Object?, Object?>(
        'pickDirectoryFiles',
        <String, Object?>{
          'title': title,
          'extensions': extensions,
          'copyFiles': copyFiles,
        },
      );
  if (result == null) {
    return null;
  }

  final Object? rawFiles = result['files'];
  final List<String> files = rawFiles is List<Object?>
      ? rawFiles.whereType<String>().toList(growable: false)
      : const <String>[];
  final Object? rawSourceUris = result['sourceUris'];
  final Map<String, String> sourceUris = rawSourceUris is Map<Object?, Object?>
      ? rawSourceUris.entries
            .where(
              (MapEntry<Object?, Object?> entry) =>
                  entry.key is String && entry.value is String,
            )
            .fold<Map<String, String>>(<String, String>{}, (
              Map<String, String> map,
              MapEntry<Object?, Object?> entry,
            ) {
              map[entry.key! as String] = entry.value! as String;
              return map;
            })
      : const <String, String>{};

  return AndroidImportDirectorySelection(
    folderName: (result['folderName'] as String?) ?? '',
    label: (result['label'] as String?) ?? '',
    files: files,
    sourceUris: sourceUris,
  );
}

Future<String?> copyPickedAndroidFile({
  required String sourceUri,
  required String destinationName,
}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return null;
  }
  return _channel.invokeMethod<String>(
    'copyPickedFile',
    <String, Object?>{
      'sourceUri': sourceUri,
      'destinationName': destinationName,
    },
  );
}
