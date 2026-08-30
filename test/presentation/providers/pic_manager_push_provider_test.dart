import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/constants/storage_keys.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/core/storage/secure_storage_service.dart';
import 'package:nai_launcher/data/models/pic_manager/pic_manager_push_config.dart';
import 'package:nai_launcher/data/services/pic_manager_push_service.dart';
import 'package:nai_launcher/presentation/providers/generation/generation_models.dart';
import 'package:nai_launcher/presentation/providers/pic_manager_push_provider.dart';

void main() {
  test(
    'locks each image before upload and builds the launcher source',
    () async {
      final service = _BlockingPushService();
      final settings = PicManagerSettingsNotifier(
        localStorage: _MemoryStorage(),
        secureStorage: _MemorySecureStorage(),
        service: service,
      );
      final container = ProviderContainer(
        overrides: [
          picManagerSettingsProvider.overrideWith((_) => settings),
          picManagerPushServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);
      await settings.credentials();

      final image = GeneratedImage(
        id: 'image-1',
        bytes: Uint8List.fromList([1, 2, 3]),
        width: 832,
        height: 1216,
        createdAt: DateTime.utc(2026, 8, 30, 12, 34, 56),
      );
      final uploads = container.read(picManagerUploadsProvider.notifier);
      final first = uploads.upload(image);
      await service.started.future;

      expect(container.read(picManagerUploadsProvider), {'image-1'});
      await expectLater(
        uploads.upload(image),
        throwsA(
          isA<PicManagerPushException>().having(
            (error) => error.failure,
            'failure',
            PicManagerPushFailure.alreadyUploading,
          ),
        ),
      );
      expect(service.calls, 1);
      expect(service.source, containsPair('adapter', picManagerAdapter));
      expect(service.source, containsPair('source_name', picManagerSourceName));
      expect(service.source, containsPair('page_url', 'https://novelai.net/'));
      expect(service.imageBytes, image.bytes);

      service.complete();
      expect((await first).id, 'asset-1');
      expect(container.read(picManagerUploadsProvider), isEmpty);
    },
  );
}

class _MemoryStorage extends LocalStorageService {
  @override
  T? getSetting<T>(String key, {T? defaultValue}) {
    if (key != StorageKeys.picManagerPushConfiguration) return defaultValue;
    return <String, Object>{
          'version': 1,
          'base_url': 'https://images.example',
          'allow_insecure_http': false,
          'auto_push_on_favorite': true,
        }
        as T;
  }
}

class _MemorySecureStorage extends SecureStorageService {
  @override
  Future<String?> getPicManagerPushToken() async => 'secret-token';
}

class _BlockingPushService extends PicManagerPushService {
  final started = Completer<void>();
  final _result = Completer<PicManagerPushReceipt>();
  int calls = 0;
  late Map<String, Object?> source;
  late Uint8List imageBytes;

  @override
  Future<PicManagerPushReceipt> upload({
    required PicManagerEndpoint endpoint,
    required String token,
    required Uint8List imageBytes,
    required String fileName,
    required Map<String, Object?> source,
    Duration timeout = const Duration(minutes: 2),
  }) {
    calls++;
    this.imageBytes = imageBytes;
    this.source = source;
    if (!started.isCompleted) started.complete();
    return _result.future;
  }

  void complete() {
    _result.complete(
      const PicManagerPushReceipt(id: 'asset-1', deduplicated: false),
    );
  }
}
