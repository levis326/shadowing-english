import 'package:flutter/services.dart';

String createPlayerMediaUri(String source) {
  if (source.startsWith('http://') || source.startsWith('https://')) {
    return source;
  }
  return 'asset:///$source';
}

bool playerMediaAvailable(String source) => source.isNotEmpty;

Future<String> loadPlayerTextSource(String source) {
  return rootBundle.loadString(source);
}
