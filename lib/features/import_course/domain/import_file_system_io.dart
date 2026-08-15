import 'dart:io';

List<String> listFilesSync(String folderPath, Set<String> allowedExtensions) {
  final Directory directory = Directory(folderPath);
  if (!directory.existsSync()) {
    return const <String>[];
  }

  return directory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .map((File file) => file.path)
      .where((String path) {
        final String lower = path.toLowerCase();
        return allowedExtensions.any(lower.endsWith);
      })
      .toList(growable: false);
}

String readTextFileSnippetSync(String filePath, {int maxChars = 1200}) {
  final File file = File(filePath);
  if (!file.existsSync()) {
    return '';
  }

  try {
    final String content = file.readAsStringSync();
    if (content.length <= maxChars) {
      return content;
    }
    return content.substring(0, maxChars);
  } catch (_) {
    return '';
  }
}
