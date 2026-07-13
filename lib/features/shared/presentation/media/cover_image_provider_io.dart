import 'dart:io';

import 'package:flutter/widgets.dart';

ImageProvider<Object>? coverImageProviderForPath(String path) {
  if (path.isEmpty) {
    return null;
  }
  return FileImage(File(path));
}
