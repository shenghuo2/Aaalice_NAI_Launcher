import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/storage_keys.dart';
import '../../core/storage/local_storage_service.dart';
import '../../core/storage/secure_storage_service.dart';
import '../../data/models/pic_manager/pic_manager_push_config.dart';
import '../../data/services/pic_manager_push_service.dart';
import 'generation/generation_models.dart';

final picManagerPushServiceProvider = Provider<PicManagerPushService>((ref) {
  final service = PicManagerPushService();
  ref.onDispose(service.close);
  return service;
});

final picManagerSettingsProvider =
    StateNotifierProvider<
      PicManagerSettingsNotifier,
      AsyncValue<PicManagerPushConfig>
    >((ref) {
      return PicManagerSettingsNotifier(
        localStorage: ref.watch(localStorageServiceProvider),
        secureStorage: ref.watch(secureStorageServiceProvider),
        service: ref.watch(picManagerPushServiceProvider),
      );
    });

class PicManagerSettingsNotifier
    extends StateNotifier<AsyncValue<PicManagerPushConfig>> {
  PicManagerSettingsNotifier({
    required LocalStorageService localStorage,
    required SecureStorageService secureStorage,
    required PicManagerPushService service,
  }) : _localStorage = localStorage,
       _secureStorage = secureStorage,
       _service = service,
       super(const AsyncLoading()) {
    _loadFuture = _load();
    unawaited(_loadFuture);
  }

  final LocalStorageService _localStorage;
  final SecureStorageService _secureStorage;
  final PicManagerPushService _service;
  late final Future<void> _loadFuture;

  Future<void> _load() async {
    try {
      final stored = _localStorage.getSetting<Object?>(
        StorageKeys.picManagerPushConfiguration,
      );
      final config = PicManagerPushConfig.fromStorage(stored);
      final token = await _secureStorage.getPicManagerPushToken();
      state = AsyncData(config.copyWith(hasToken: token?.isNotEmpty == true));
    } catch (error, stack) {
      state = AsyncError(error, stack);
    }
  }

  Future<PicManagerPushConfig> save({
    required String baseUrl,
    required bool allowInsecureHttp,
    required bool autoPushOnFavorite,
    String? token,
  }) async {
    await _loadFuture;
    final endpoint = PicManagerEndpoint.parse(
      baseUrl,
      allowInsecureHttp: allowInsecureHttp,
    );
    final rawToken = token?.trim() ?? '';
    if (rawToken.isNotEmpty) {
      await _secureStorage.savePicManagerPushToken(rawToken);
    }
    final hasToken =
        (await _secureStorage.getPicManagerPushToken())?.isNotEmpty == true;
    final config = PicManagerPushConfig(
      baseUrl: endpoint.normalizedBaseUrl,
      allowInsecureHttp: allowInsecureHttp,
      autoPushOnFavorite: autoPushOnFavorite,
      hasToken: hasToken,
    );
    await _localStorage.setSetting(
      StorageKeys.picManagerPushConfiguration,
      config.toStorage(),
    );
    state = AsyncData(config);
    return config;
  }

  Future<void> clearToken() async {
    await _loadFuture;
    await _secureStorage.clearPicManagerPushToken();
    final current = state.valueOrNull ?? const PicManagerPushConfig();
    state = AsyncData(current.copyWith(hasToken: false));
  }

  Future<void> testConnection({
    required String baseUrl,
    required bool allowInsecureHttp,
    String? token,
  }) async {
    await _loadFuture;
    final endpoint = PicManagerEndpoint.parse(
      baseUrl,
      allowInsecureHttp: allowInsecureHttp,
    );
    final candidate = token?.trim().isNotEmpty == true
        ? token!.trim()
        : await _secureStorage.getPicManagerPushToken();
    if (candidate == null || candidate.isEmpty) {
      throw const PicManagerPushException(PicManagerPushFailure.notConfigured);
    }
    await _service.validateConnection(endpoint: endpoint, token: candidate);
  }

  Future<PicManagerPushCredentials?> credentials() async {
    await _loadFuture;
    final config = state.valueOrNull;
    if (config == null || !config.isConfigured) return null;
    final token = await _secureStorage.getPicManagerPushToken();
    if (token == null || token.isEmpty) return null;
    return PicManagerPushCredentials(config: config, token: token);
  }
}

final picManagerUploadsProvider =
    StateNotifierProvider<PicManagerUploadsNotifier, Set<String>>(
      (ref) => PicManagerUploadsNotifier(ref),
    );

class PicManagerUploadRequest {
  const PicManagerUploadRequest({
    required this.uploadKey,
    required this.fileName,
    required this.loadImageBytes,
    required this.pageUrl,
    required this.capturedAt,
    this.seedHint,
    this.metadata = const <String, Object?>{},
  });

  final String uploadKey;
  final String fileName;
  final Future<Uint8List> Function() loadImageBytes;
  final String pageUrl;
  final DateTime capturedAt;
  final int? seedHint;
  final Map<String, Object?> metadata;

  factory PicManagerUploadRequest.generated(GeneratedImage image) {
    return PicManagerUploadRequest(
      uploadKey: image.id,
      fileName: '${image.id}.png',
      loadImageBytes: () async => image.bytes,
      pageUrl: 'https://novelai.net/',
      capturedAt: image.createdAt,
      seedHint: image.metadata?.seed,
      metadata: <String, Object?>{
        'image_id': image.id,
        'width': image.width,
        'height': image.height,
      },
    );
  }
}

class PicManagerUploadsNotifier extends StateNotifier<Set<String>> {
  PicManagerUploadsNotifier(this._ref) : super(const <String>{});

  final Ref _ref;

  Future<PicManagerPushReceipt> upload(GeneratedImage image) async {
    return uploadRequest(PicManagerUploadRequest.generated(image));
  }

  Future<PicManagerPushReceipt> uploadRequest(
    PicManagerUploadRequest request,
  ) async {
    if (state.contains(request.uploadKey)) {
      throw const PicManagerPushException(
        PicManagerPushFailure.alreadyUploading,
      );
    }
    state = {...state, request.uploadKey};
    try {
      final credentials = await _ref
          .read(picManagerSettingsProvider.notifier)
          .credentials();
      if (credentials == null) {
        throw const PicManagerPushException(
          PicManagerPushFailure.notConfigured,
        );
      }

      final seed = request.seedHint;
      final source = <String, Object?>{
        'adapter': picManagerAdapter,
        'page_url': request.pageUrl,
        'captured_at': request.capturedAt.toUtc().toIso8601String(),
        'source_name': picManagerSourceName,
        if (seed != null && seed >= 0 && seed <= 9223372036854775807)
          'seed_hint': seed,
        'metadata': request.metadata,
      };
      final imageBytes = await request.loadImageBytes();

      return await _ref
          .read(picManagerPushServiceProvider)
          .upload(
            endpoint: credentials.config.endpoint(),
            token: credentials.token,
            imageBytes: imageBytes,
            fileName: request.fileName,
            source: source,
          );
    } finally {
      state = {...state}..remove(request.uploadKey);
    }
  }
}
