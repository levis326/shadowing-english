import 'dart:io';

import 'package:flutter/services.dart';

String createPlayerMediaUri(String source) {
  if (source.startsWith('http://') || source.startsWith('https://')) {
    return source;
  }
  if (_isLocalFilePath(source)) {
    return Uri.file(source).toString();
  }
  return 'asset:///$source';
}

bool playerMediaAvailable(String source) {
  if (source.startsWith('http://') || source.startsWith('https://')) {
    return true;
  }
  if (source.startsWith('assets/')) {
    return true;
  }
  return File(source).existsSync();
}

Future<String> loadPlayerTextSource(String source) async {
  if (_isLocalFilePath(source)) {
    return File(source).readAsString();
  }
  return rootBundle.loadString(source);
}

bool _isLocalFilePath(String source) {
  if (source.isEmpty) {
    return false;
  }
  return File(source).existsSync();
}
