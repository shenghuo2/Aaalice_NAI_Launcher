import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_http2_adapter/dio_http2_adapter.dart';

/// Plain HTTP services commonly speak HTTP/1.1, while HTTPS keeps HTTP/2.
class SchemeAwareHttpClientAdapter implements HttpClientAdapter {
  final IOHttpClientAdapter _http1 = IOHttpClientAdapter();
  late final Http2Adapter _http2 = Http2Adapter(
    ConnectionManager(idleTimeout: const Duration(seconds: 15)),
    fallbackAdapter: _http1,
  );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => (options.uri.scheme == 'http' ? _http1 : _http2).fetch(
    options,
    requestStream,
    cancelFuture,
  );

  @override
  void close({bool force = false}) {
    _http2.close(force: force);
    _http1.close(force: force);
  }
}
