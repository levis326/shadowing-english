import 'dart:convert';
import 'dart:io';

import 'package:common_learn_english/features/settings/data/local_data_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory supportDir;
  late Directory tempDir;

  setUp(() async {
    supportDir = Directory.systemTemp.createTempSync('cle_support_test_');
    tempDir = Directory.systemTemp.createTempSync('cle_temp_test_');
    Hive.init(supportDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (supportDir.existsSync()) {
      supportDir.deleteSync(recursive: true);
    }
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  LocalDataBackupService buildService() {
    return LocalDataBackupService(
      appSupportDirectory: () async => supportDir,
      temporaryDirectory: () async => tempDir,
    );
  }

  test('backupToLocal 把 Hive prefs 快照写入 backup/<时间戳>/shadowing_backup.json', () async {
    final Box<String> prefs = await Hive.openBox<String>('prefs');
    await prefs.put('word_book_v1', '[{"word":"hello"}]');
    await prefs.put(
      'learning_settings_v1',
      '{"subtitleMode":"双语"}',
    );
    await prefs.put('plain_value', 'not-json');

    final File backup = await buildService().backupToLocal();

    expect(backup.existsSync(), isTrue);
    expect(
      backup.parent.path,
      startsWith('${supportDir.path}${Platform.pathSeparator}backup'),
    );
    expect(backup.parent.parent.path, '${supportDir.path}${Platform.pathSeparator}backup');

    final Map<String, dynamic> decoded =
        jsonDecode(await backup.readAsString()) as Map<String, dynamic>;
    expect(decoded['app'], 'TideSparrow English');
    expect(decoded['schemaVersion'], 1);
    expect(decoded['backedUpAt'], isA<String>());

    final Map<String, dynamic> data = decoded['data'] as Map<String, dynamic>;
    expect(data['word_book_v1'], isA<List<dynamic>>());
    expect((data['word_book_v1'] as List<dynamic>).first, <String, Object>{
      'word': 'hello',
    });
    expect(data['learning_settings_v1'], <String, Object>{
      'subtitleMode': '双语',
    });
    expect(data['plain_value'], 'not-json');
  });

  test('clearCachedFiles 删除 AI 字幕缓存和本应用临时文件', () async {
    final Directory asrCache = Directory(
      '${supportDir.path}${Platform.pathSeparator}asr_subtitles',
    )..createSync(recursive: true);
    File(
      '${asrCache.path}${Platform.pathSeparator}ep1.words.json',
    ).writeAsStringSync('{"lines":[]}');
    File(
      '${asrCache.path}${Platform.pathSeparator}ep1.words.json.meta.json',
    ).writeAsStringSync('{}');
    File(
      '${tempDir.path}${Platform.pathSeparator}pron_reading.wav',
    ).writeAsStringSync('wav');
    File(
      '${tempDir.path}${Platform.pathSeparator}other-app.txt',
    ).writeAsStringSync('keep');

    final int removed = await buildService().clearCachedFiles();

    expect(removed, 3);
    expect(asrCache.existsSync(), isFalse);
    expect(
      File(
        '${tempDir.path}${Platform.pathSeparator}pron_reading.wav',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        '${tempDir.path}${Platform.pathSeparator}other-app.txt',
      ).existsSync(),
      isTrue,
    );
  });

  test('backupToLocal 在没有 prefs 数据时也能生成备份文件', () async {
    final File backup = await buildService().backupToLocal();

    expect(backup.existsSync(), isTrue);
    final Map<String, dynamic> decoded =
        jsonDecode(await backup.readAsString()) as Map<String, dynamic>;
    expect(decoded['data'], isA<Map<String, dynamic>>());
  });
}
