import 'dart:async';

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

class PicManagerUploadsNotifier extends StateNotifier<Set<String>> {
  PicManagerUploadsNotifier(this._ref) : super(const <String>{});

  final Ref _ref;

  Future<PicManagerPushReceipt> upload(GeneratedImage image) async {
    if (state.contains(image.id)) {
      throw const PicManagerPushException(
        PicManagerPushFailure.alreadyUploading,
      );
    }
    state = {...state, image.id};
    try {
      final credentials = await _ref
          .read(picManagerSettingsProvider.notifier)
          .credentials();
      if (credentials == null) {
        throw const PicManagerPushException(
          PicManagerPushFailure.notConfigured,
        );
      }

      final seed = image.metadata?.seed;
      final source = <String, Object?>{
        'adapter': picManagerAdapter,
        'page_url': 'https://novelai.net/',
        'captured_at': image.createdAt.toUtc().toIso8601String(),
        'source_name': picManagerSourceName,
        if (seed != null && seed >= 0 && seed <= 9223372036854775807)
          'seed_hint': seed,
        'metadata': <String, Object>{
          'image_id': image.id,
          'width': image.width,
          'height': image.height,
        },
      };

      return await _ref
          .read(picManagerPushServiceProvider)
          .upload(
            endpoint: credentials.config.endpoint(),
            token: credentials.token,
            imageBytes: image.bytes,
            fileName: '${image.id}.png',
            source: source,
          );
    } finally {
      state = {...state}..remove(image.id);
    }
  }
}
