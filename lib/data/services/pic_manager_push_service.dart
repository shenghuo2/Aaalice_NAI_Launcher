import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/pic_manager/pic_manager_push_config.dart';

typedef PicManagerRequestSender =
    Future<http.StreamedResponse> Function(http.BaseRequest request);

enum PicManagerPushFailure {
  unauthorized,
  invalidRequest,
  server,
  timeout,
  network,
  invalidResponse,
  alreadyUploading,
  notConfigured,
}

class PicManagerPushException implements Exception {
  const PicManagerPushException(
    this.failure, {
    this.statusCode,
    this.serverCode,
    this.serverMessage,
  });

  final PicManagerPushFailure failure;
  final int? statusCode;
  final String? serverCode;
  final String? serverMessage;

  @override
  String toString() => 'PicManagerPushException(${failure.name})';
}

class PicManagerPushReceipt {
  const PicManagerPushReceipt({required this.id, required this.deduplicated});

  final String id;
  final bool deduplicated;
}

class PicManagerPushService {
  PicManagerPushService({
    http.Client? client,
    PicManagerRequestSender? requestSender,
  }) : _client = client ?? http.Client(),
       _requestSender = requestSender;

  static const int maxSourceBytes = 64 * 1024;
  final http.Client _client;
  final PicManagerRequestSender? _requestSender;

  Future<void> validateConnection({
    required PicManagerEndpoint endpoint,
    required String token,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final request = http.Request('GET', endpoint.sourcesUri)
      ..headers['Authorization'] = _authorization(token);
    final response = await _send(request, timeout: timeout);
    if (response.statusCode != 200) {
      throw _failureFromResponse(response);
    }
  }

  Future<PicManagerPushReceipt> upload({
    required PicManagerEndpoint endpoint,
    required String token,
    required Uint8List imageBytes,
    required String fileName,
    required Map<String, Object?> source,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    if (imageBytes.isEmpty) {
      throw const PicManagerPushException(PicManagerPushFailure.invalidRequest);
    }
    final sourceJson = jsonEncode(source);
    if (utf8.encode(sourceJson).length > maxSourceBytes) {
      throw const PicManagerPushException(PicManagerPushFailure.invalidRequest);
    }

    final request = http.MultipartRequest('POST', endpoint.assetsUri)
      ..headers['Authorization'] = _authorization(token)
      ..fields['source'] = sourceJson
      ..files.add(
        http.MultipartFile.fromBytes('file', imageBytes, filename: fileName),
      );
    final response = await _send(request, timeout: timeout);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw _failureFromResponse(response);
    }
    final payload = _decodeObject(response.bodyBytes);
    final id = payload?['id'];
    final deduplicated = payload?['deduplicated'];
    if (id is! String || id.isEmpty || deduplicated is! bool) {
      throw const PicManagerPushException(
        PicManagerPushFailure.invalidResponse,
      );
    }
    return PicManagerPushReceipt(id: id, deduplicated: deduplicated);
  }

  String _authorization(String token) {
    final normalized = token
        .trim()
        .replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '')
        .trim();
    if (normalized.isEmpty ||
        normalized.runes.any((rune) => rune <= 0x20 || rune == 0x7f)) {
      throw const PicManagerPushException(PicManagerPushFailure.notConfigured);
    }
    return 'Bearer $normalized';
  }

  Future<http.Response> _send(
    http.BaseRequest request, {
    required Duration timeout,
  }) async {
    try {
      final streamed = await (_requestSender ?? _client.send)(
        request,
      ).timeout(timeout);
      return await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw const PicManagerPushException(PicManagerPushFailure.timeout);
    } on PicManagerPushException {
      rethrow;
    } catch (_) {
      // Lower-level errors can contain request details. This request carries a
      // Bearer credential, so expose only a stable failure category.
      throw const PicManagerPushException(PicManagerPushFailure.network);
    }
  }

  PicManagerPushException _failureFromResponse(http.Response response) {
    final payload = _decodeObject(response.bodyBytes);
    final error = payload?['error'];
    final serverCode = error is Map && error['code'] is String
        ? error['code'] as String
        : null;
    final serverMessage = error is Map && error['message'] is String
        ? (error['message'] as String).trim()
        : null;
    final failure = switch (response.statusCode) {
      400 => PicManagerPushFailure.invalidRequest,
      401 => PicManagerPushFailure.unauthorized,
      >= 500 => PicManagerPushFailure.server,
      _ => PicManagerPushFailure.invalidResponse,
    };
    return PicManagerPushException(
      failure,
      statusCode: response.statusCode,
      serverCode: serverCode,
      serverMessage: serverMessage?.isEmpty == true ? null : serverMessage,
    );
  }

  Map<String, dynamic>? _decodeObject(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map) {
        return <String, dynamic>{
          for (final entry in decoded.entries)
            if (entry.key is String) entry.key as String: entry.value,
        };
      }
    } catch (_) {}
    return null;
  }

  void close() => _client.close();
}
