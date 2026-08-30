import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nai_launcher/data/models/pic_manager/pic_manager_push_config.dart';
import 'package:nai_launcher/data/services/pic_manager_push_service.dart';

void main() {
  group('PicManagerEndpoint', () {
    test('normalizes a service root or complete assets endpoint', () {
      expect(
        PicManagerEndpoint.parse(
          'https://images.example/',
          allowInsecureHttp: false,
        ).assetsUri,
        Uri.parse('https://images.example/api/v1/assets'),
      );
      expect(
        PicManagerEndpoint.parse(
          'https://images.example/base/api/v1/assets/',
          allowInsecureHttp: false,
        ).sourcesUri,
        Uri.parse('https://images.example/base/api/v1/sources'),
      );
    });

    test('rejects credentials, query, fragment, and implicit HTTP', () {
      for (final value in [
        'https://token@images.example',
        'https://images.example?token=x',
        'https://images.example/#token',
        'ftp://images.example',
      ]) {
        expect(
          () => PicManagerEndpoint.parse(value, allowInsecureHttp: false),
          throwsA(isA<PicManagerConfigException>()),
        );
      }
      expect(
        () => PicManagerEndpoint.parse(
          'http://127.0.0.1:3210',
          allowInsecureHttp: false,
        ),
        throwsA(
          isA<PicManagerConfigException>().having(
            (error) => error.reason,
            'reason',
            PicManagerConfigFailure.insecureHttp,
          ),
        ),
      );
    });
  });

  test('sends the exact multipart contract with unchanged bytes', () async {
    late http.MultipartRequest captured;
    late List<int> capturedBytes;
    final service = PicManagerPushService(
      requestSender: (request) async {
        captured = request as http.MultipartRequest;
        capturedBytes = await captured.files.single.finalize().fold<List<int>>(
          <int>[],
          (bytes, chunk) => bytes..addAll(chunk),
        );
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"id":"asset-1","deduplicated":false}')),
          201,
        );
      },
    );
    addTearDown(service.close);
    final original = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);
    final source = <String, Object?>{
      'adapter': picManagerAdapter,
      'page_url': 'https://novelai.net/',
      'captured_at': '2026-08-30T00:00:00.000Z',
      'source_name': picManagerSourceName,
      'metadata': <String, Object>{'image_id': 'image-1'},
    };

    final receipt = await service.upload(
      endpoint: PicManagerEndpoint.parse(
        'https://images.example',
        allowInsecureHttp: false,
      ),
      token: 'Bearer secret-token',
      imageBytes: original,
      fileName: 'image-1.png',
      source: source,
    );

    expect(receipt.id, 'asset-1');
    expect(receipt.deduplicated, isFalse);
    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/v1/assets');
    expect(captured.headers['Authorization'], 'Bearer secret-token');
    expect(captured.fields, hasLength(1));
    expect(jsonDecode(captured.fields['source']!), source);
    expect(captured.files, hasLength(1));
    expect(captured.files.single.field, 'file');
    expect(capturedBytes, original);
  });

  test('maps deduplication and structured authentication errors', () async {
    var status = 200;
    var body = '{"id":"asset-1","deduplicated":true}';
    final service = PicManagerPushService(
      requestSender: (_) async =>
          http.StreamedResponse(Stream.value(utf8.encode(body)), status),
    );
    addTearDown(service.close);
    final endpoint = PicManagerEndpoint.parse(
      'https://images.example',
      allowInsecureHttp: false,
    );
    final receipt = await service.upload(
      endpoint: endpoint,
      token: 'secret-token',
      imageBytes: Uint8List.fromList([1]),
      fileName: 'image.png',
      source: const <String, Object?>{},
    );
    expect(receipt.deduplicated, isTrue);

    status = 401;
    body = '{"error":{"code":"unauthorized","message":"revoked"}}';
    await expectLater(
      service.validateConnection(endpoint: endpoint, token: 'secret-token'),
      throwsA(
        isA<PicManagerPushException>()
            .having(
              (error) => error.failure,
              'failure',
              PicManagerPushFailure.unauthorized,
            )
            .having((error) => error.serverCode, 'serverCode', 'unauthorized'),
      ),
    );
  });

  test('public exceptions never contain the bearer Token', () async {
    const token = 'super-secret-token';
    final service = PicManagerPushService(
      requestSender: (_) async => throw StateError(token),
    );
    addTearDown(service.close);

    Object? failure;
    try {
      await service.validateConnection(
        endpoint: PicManagerEndpoint.parse(
          'https://images.example',
          allowInsecureHttp: false,
        ),
        token: token,
      );
    } catch (error) {
      failure = error;
    }

    expect(failure, isA<PicManagerPushException>());
    expect(failure.toString(), isNot(contains(token)));
  });
}
