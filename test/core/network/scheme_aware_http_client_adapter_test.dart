import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/network/scheme_aware_http_client_adapter.dart';

void main() {
  test('plain HTTP uses an HTTP/1.1 connection', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      expect(request.uri.path, '/user/subscription');
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"trainingStepsLeft":42}');
      await request.response.close();
    });
    final dio = Dio()..httpClientAdapter = SchemeAwareHttpClientAdapter();

    try {
      final response = await dio.get<Map<String, dynamic>>(
        'http://127.0.0.1:${server.port}/user/subscription',
      );
      expect(response.data?['trainingStepsLeft'], 42);
    } finally {
      dio.close(force: true);
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
