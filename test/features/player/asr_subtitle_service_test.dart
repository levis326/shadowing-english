import 'dart:convert';
import 'dart:io';

import 'package:common_learn_english/features/player/presentation/asr_subtitle_service.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/player_subtitle_loader.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'generates internal words json from verbose transcription response',
    () async {
      final File video = File(
        '${Directory.systemTemp.createTempSync('asr-service-test-').path}/lesson.mp4',
      )..writeAsStringSync('demo');
      addTearDown(() => video.parent.deleteSync(recursive: true));

      final AsrSubtitleService service = AsrSubtitleService(
        prepareAudioChunksOverride: (File file) async => <AsrAudioChunk>[
          AsrAudioChunk(file: file, offsetMs: 0),
        ],
        postTranscriptionOverride:
            ({required BaseOptions options, required FormData data}) async {
              expect(options.baseUrl, 'https://api.example.com/v1');
              return Response<dynamic>(
                requestOptions: RequestOptions(path: '/audio/transcriptions'),
                data: <String, dynamic>{
                  'language': 'en',
                  'segments': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'start': 70.0,
                      'end': 73.0,
                      'text': 'I want to learn English.',
                      'words': <Map<String, dynamic>>[
                        <String, dynamic>{
                          'word': 'I',
                          'start': 70.0,
                          'end': 70.28,
                          'probability': 0.98,
                        },
                      ],
                    },
                  ],
                },
              );
            },
      );

      final String raw = await service.generateWordsJson(
        videoPath: video.path,
        settings: LearningSettingsState.defaults().copyWith(
          asrApiKey: 'demo-key',
          asrBaseUrl: 'https://api.example.com/v1',
          asrModel: 'asr-demo',
        ),
      );

      final List<PlayerSubtitleLine> lines = parseSubtitleLines(raw);
      expect(lines, hasLength(1));
      expect(lines.single.startMs, 70000);
      expect(lines.single.words.single.text, 'I');
    },
  );

  test('MiMo token plan uses chat completions audio input', () async {
    final File video = File(
      '${Directory.systemTemp.createTempSync('mimo-asr-service-test-').path}/lesson.mp4',
    )..writeAsStringSync('demo');
    final File extractedAudio = File('${video.parent.path}/lesson.m4a')
      ..writeAsStringSync('audio');
    addTearDown(() => video.parent.deleteSync(recursive: true));

    final AsrSubtitleService service = AsrSubtitleService(
      prepareAudioOverride: (_) async => extractedAudio,
      postChatCompletionOverride:
          ({
            required BaseOptions options,
            required Map<String, Object?> data,
          }) async {
            expect(options.baseUrl, 'https://token-plan-cn.xiaomimimo.com/v1');
            expect(data['model'], 'mimo-v2.5-asr');
            final List<dynamic> messages = data['messages']! as List<dynamic>;
            final Map<String, dynamic> user =
                messages.single as Map<String, dynamic>;
            final List<dynamic> content = user['content']! as List<dynamic>;
            final Map<String, dynamic> textContent = content
                .cast<Map<String, dynamic>>()
                .firstWhere(
                  (Map<String, dynamic> item) => item['type'] == 'text',
                );
            expect(
              textContent['text'],
              contains('Fill chinese with natural Simplified Chinese'),
            );
            final Map<String, dynamic> audioContent = content
                .cast<Map<String, dynamic>>()
                .firstWhere(
                  (Map<String, dynamic> item) => item['type'] == 'input_audio',
                );
            expect(audioContent['type'], 'input_audio');
            expect(data['asr_options'], <String, Object?>{'language': 'auto'});
            final Map<String, dynamic> inputAudio =
                audioContent['input_audio']! as Map<String, dynamic>;
            expect(
              inputAudio['data'],
              'data:audio/mp4;base64,${base64Encode(extractedAudio.readAsBytesSync())}',
            );
            return Response<dynamic>(
              requestOptions: RequestOptions(path: '/chat/completions'),
              data: <String, dynamic>{
                'choices': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'message': <String, dynamic>{
                      'content': '''
{
  "version": 1,
  "language": "en",
  "lines": [
    {
      "startMs": 70000,
      "endMs": 73000,
      "english": "I want to learn English.",
      "chinese": "我想学英语。",
      "words": [
        { "text": "I", "startMs": 70000, "endMs": 70280, "confidence": 0.98 }
      ]
    }
  ]
}
''',
                    },
                  },
                ],
              },
            );
          },
    );

    final String raw = await service.generateWordsJson(
      videoPath: video.path,
      settings: LearningSettingsState.defaults().copyWith(
        asrProvider: 'MiMo Token Plan',
        asrApiKey: 'tp-demo',
        asrBaseUrl: 'https://token-plan-cn.xiaomimimo.com/v1',
        asrModel: 'mimo-v2.5-asr',
        generateBilingualAsrSubtitles: true,
      ),
    );

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(raw);
    expect(lines.single.english, 'I want to learn English.');
    expect(lines.single.words.single.startMs, 70000);
  });

  test('腾讯云 ASR uploads audio and parses word timestamps', () async {
    final File video = File(
      '${Directory.systemTemp.createTempSync('tencent-asr-service-test-').path}/lesson.mp4',
    )..writeAsStringSync('demo');
    final File chunk = File('${video.parent.path}/chunk.wav')
      ..writeAsStringSync('audio-bytes');
    addTearDown(() => video.parent.deleteSync(recursive: true));

    final AsrSubtitleService service = AsrSubtitleService(
      now: () => DateTime.utc(2026, 7, 9, 10),
      prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
        AsrAudioChunk(file: chunk, offsetMs: 60000),
      ],
      postJsonOverride:
          ({
            required BaseOptions options,
            required String path,
            required Map<String, Object?> data,
            required Map<String, String> headers,
          }) async {
            expect(options.baseUrl, 'https://asr.tencentcloudapi.com');
            expect(path, '/');
            expect(data['EngSerViceType'], '16k_en');
            expect(data['VoiceFormat'], 'wav');
            expect(data['SourceType'], 1);
            expect(data['WordInfo'], 2);
            expect(data['Data'], base64Encode(chunk.readAsBytesSync()));
            expect(headers['X-TC-Action'], 'SentenceRecognition');
            expect(headers['X-TC-Version'], '2019-06-14');
            expect(headers['Authorization'], contains('TC3-HMAC-SHA256'));
            return Response<dynamic>(
              requestOptions: RequestOptions(path: path),
              data: <String, dynamic>{
                'Response': <String, dynamic>{
                  'Result':
                      'It is raining today, so Pepper and George cannot play outside.',
                  'WordList': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'Word': 'It',
                      'StartTime': 100,
                      'EndTime': 180,
                    },
                    <String, dynamic>{
                      'Word': 'is',
                      'StartTime': 190,
                      'EndTime': 260,
                    },
                    <String, dynamic>{
                      'Word': 'raining',
                      'StartTime': 300,
                      'EndTime': 520,
                    },
                    <String, dynamic>{
                      'Word': '.',
                      'StartTime': 530,
                      'EndTime': 540,
                    },
                  ],
                },
              },
            );
          },
    );

    final String raw = await service.generateWordsJson(
      videoPath: video.path,
      settings: LearningSettingsState.defaults().copyWith(
        asrProvider: '腾讯云',
        asrApiKey: 'secret-id:secret-key',
        asrBaseUrl: 'https://asr.tencentcloudapi.com',
        asrModel: '16k_en',
      ),
    );

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(raw);
    expect(lines, hasLength(1));
    expect(lines.single.english, 'It is raining.');
    expect(lines.single.startMs, 60100);
    expect(lines.single.endMs, 60540);
    expect(
      lines.single.words.map((PlayerSubtitleWord word) => word.text),
      <String>['It', 'is', 'raining'],
    );
    expect(lines.single.words.first.startMs, 60100);
  });

  test('腾讯云 ASR accepts full-width colon in key', () async {
    final File video = File(
      '${Directory.systemTemp.createTempSync('tencent-asr-key-test-').path}/lesson.mp4',
    )..writeAsStringSync('demo');
    final File chunk = File('${video.parent.path}/chunk.wav')
      ..writeAsStringSync('audio-bytes');
    addTearDown(() => video.parent.deleteSync(recursive: true));

    final AsrSubtitleService service = AsrSubtitleService(
      prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
        AsrAudioChunk(file: chunk, offsetMs: 0),
      ],
      postJsonOverride:
          ({
            required BaseOptions options,
            required String path,
            required Map<String, Object?> data,
            required Map<String, String> headers,
          }) async {
            expect(headers['Authorization'], contains('Credential=secret-id/'));
            return Response<dynamic>(
              requestOptions: RequestOptions(path: path),
              data: <String, dynamic>{
                'Response': <String, dynamic>{
                  'WordList': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'Word': 'Hello',
                      'StartTime': 0,
                      'EndTime': 300,
                    },
                  ],
                },
              },
            );
          },
    );

    final String raw = await service.generateWordsJson(
      videoPath: video.path,
      settings: LearningSettingsState.defaults().copyWith(
        asrProvider: '腾讯云',
        asrApiKey: ' secret-id：secret-key ',
        asrBaseUrl: 'https://asr.tencentcloudapi.com',
        asrModel: '16k_en',
      ),
    );

    expect(parseSubtitleLines(raw).single.words.single.text, 'Hello');
  });

  test('腾讯云 ASR splits long unpunctuated word lists', () async {
    final File video = File(
      '${Directory.systemTemp.createTempSync('tencent-asr-split-test-').path}/lesson.mp4',
    )..writeAsStringSync('demo');
    final File chunk = File('${video.parent.path}/chunk.wav')
      ..writeAsStringSync('audio-bytes');
    addTearDown(() => video.parent.deleteSync(recursive: true));

    final AsrSubtitleService service = AsrSubtitleService(
      prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
        AsrAudioChunk(file: chunk, offsetMs: 0),
      ],
      postJsonOverride:
          ({
            required BaseOptions options,
            required String path,
            required Map<String, Object?> data,
            required Map<String, String> headers,
          }) async => Response<dynamic>(
            requestOptions: RequestOptions(path: path),
            data: <String, dynamic>{
              'Response': <String, dynamic>{
                'WordList': List<Map<String, dynamic>>.generate(
                  13,
                  (int index) => <String, dynamic>{
                    'Word': 'word$index',
                    'StartTime': index * 100,
                    'EndTime': index * 100 + 80,
                  },
                ),
              },
            },
          ),
    );

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(
      await service.generateWordsJson(
        videoPath: video.path,
        settings: LearningSettingsState.defaults().copyWith(
          asrProvider: '腾讯云',
          asrApiKey: 'secret-id:secret-key',
          asrBaseUrl: 'https://asr.tencentcloudapi.com',
          asrModel: '16k_en',
        ),
      ),
    );

    expect(lines, hasLength(2));
    expect(lines.first.words, hasLength(12));
    expect(lines.last.words.single.text, 'word12');
  });

  test('腾讯云 ASR skips empty chunks', () async {
    final File video = File(
      '${Directory.systemTemp.createTempSync('tencent-asr-empty-test-').path}/lesson.mp4',
    )..writeAsStringSync('demo');
    final File firstChunk = File('${video.parent.path}/chunk_00000.wav')
      ..writeAsStringSync('first');
    final File emptyChunk = File('${video.parent.path}/chunk_00001.wav')
      ..writeAsStringSync('empty');
    addTearDown(() => video.parent.deleteSync(recursive: true));

    int calls = 0;
    final AsrSubtitleService service = AsrSubtitleService(
      prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
        AsrAudioChunk(file: firstChunk, offsetMs: 0),
        AsrAudioChunk(file: emptyChunk, offsetMs: 60000),
      ],
      postJsonOverride:
          ({
            required BaseOptions options,
            required String path,
            required Map<String, Object?> data,
            required Map<String, String> headers,
          }) async {
            calls += 1;
            return Response<dynamic>(
              requestOptions: RequestOptions(path: path),
              data: <String, dynamic>{
                'Response': <String, dynamic>{
                  'WordList': calls == 1
                      ? <Map<String, dynamic>>[
                          <String, dynamic>{
                            'Word': 'Hello',
                            'StartTime': 0,
                            'EndTime': 300,
                          },
                        ]
                      : const <Map<String, dynamic>>[],
                },
              },
            );
          },
    );

    final String raw = await service.generateWordsJson(
      videoPath: video.path,
      settings: LearningSettingsState.defaults().copyWith(
        asrProvider: '腾讯云',
        asrApiKey: 'secret-id:secret-key',
        asrBaseUrl: 'https://asr.tencentcloudapi.com',
        asrModel: '16k_en',
      ),
    );

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(raw);
    expect(calls, 2);
    expect(lines, hasLength(1));
    expect(lines.single.words.single.text, 'Hello');
  });

  test('MiMo transcription uploads chunks and offsets merged timestamps', () async {
    final File video = File(
      '${Directory.systemTemp.createTempSync('mimo-asr-chunk-test-').path}/lesson.mp4',
    )..writeAsStringSync('demo');
    final File firstChunk = File('${video.parent.path}/chunk_00000.m4a')
      ..writeAsStringSync('first');
    final File secondChunk = File('${video.parent.path}/chunk_00001.m4a')
      ..writeAsStringSync('second');
    addTearDown(() => video.parent.deleteSync(recursive: true));

    int calls = 0;
    final List<AsrSubtitleProgress> progress = <AsrSubtitleProgress>[];
    final AsrSubtitleService service = AsrSubtitleService(
      prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
        AsrAudioChunk(file: firstChunk, offsetMs: 0),
        AsrAudioChunk(file: secondChunk, offsetMs: 300000),
      ],
      postChatCompletionOverride:
          ({
            required BaseOptions options,
            required Map<String, Object?> data,
          }) async {
            calls += 1;
            return Response<dynamic>(
              requestOptions: RequestOptions(path: '/chat/completions'),
              data: <String, dynamic>{
                'choices': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'message': <String, dynamic>{
                      'content':
                          '{"version":1,"language":"en","lines":[{"startMs":1000,"endMs":2000,"english":"chunk $calls","chinese":"","words":[{"text":"chunk","startMs":1000,"endMs":1400}]}]}',
                    },
                  },
                ],
              },
            );
          },
    );

    final String raw = await service.generateWordsJson(
      videoPath: video.path,
      settings: LearningSettingsState.defaults().copyWith(
        asrProvider: 'MiMo Token Plan',
        asrApiKey: 'tp-demo',
        asrBaseUrl: 'https://token-plan-cn.xiaomimimo.com/v1',
        asrModel: 'mimo-v2.5-asr',
      ),
      onProgress: progress.add,
    );

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(raw);
    expect(calls, 2);
    expect(lines.map((PlayerSubtitleLine line) => line.startMs), <int>[
      1000,
      301000,
    ]);
    expect(lines.last.words.single.startMs, 301000);
    expect(
      progress.map((AsrSubtitleProgress item) => item.completedChunks),
      <int>[0, 1, 2],
    );
  });

  test('MiMo errors include status and response body', () async {
    final File video = File(
      '${Directory.systemTemp.createTempSync('mimo-asr-error-test-').path}/lesson.mp4',
    )..writeAsStringSync('demo');
    addTearDown(() => video.parent.deleteSync(recursive: true));

    final AsrSubtitleService service = AsrSubtitleService(
      prepareAudioOverride: (_) async => video,
      postChatCompletionOverride:
          ({
            required BaseOptions options,
            required Map<String, Object?> data,
          }) async {
            throw DioException(
              requestOptions: RequestOptions(path: '/chat/completions'),
              response: Response<dynamic>(
                requestOptions: RequestOptions(path: '/chat/completions'),
                statusCode: 400,
                data: <String, Object?>{'error': 'bad audio'},
              ),
            );
          },
    );

    expect(
      service.generateWordsJson(
        videoPath: video.path,
        settings: LearningSettingsState.defaults().copyWith(
          asrProvider: 'MiMo Token Plan',
          asrApiKey: 'tp-demo',
          asrBaseUrl: 'https://token-plan-cn.xiaomimimo.com/v1',
          asrModel: 'mimo-v2.5-asr',
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('HTTP 400'),
        ),
      ),
    );
  });
}
