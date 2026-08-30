import 'dart:async';
import 'dart:typed_data';

import 'package:nai_launcher/core/constants/storage_keys.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/core/storage/secure_storage_service.dart';
import 'package:nai_launcher/data/models/pic_manager/pic_manager_push_config.dart';
import 'package:nai_launcher/data/services/pic_manager_push_service.dart';
import 'package:nai_launcher/presentation/providers/pic_manager_push_provider.dart';

Future<PicManagerSettingsNotifier> createPicManagerTestSettings({
  required PicManagerPushService service,
  required bool autoPushOnFavorite,
}) async {
  final settings = PicManagerSettingsNotifier(
    localStorage: PicManagerTestStorage(autoPushOnFavorite),
    secureStorage: PicManagerTestSecureStorage(),
    service: service,
  );
  await settings.credentials();
  return settings;
}

class PicManagerTestStorage extends LocalStorageService {
  PicManagerTestStorage(this.autoPushOnFavorite);

  final bool autoPushOnFavorite;

  @override
  T? getSetting<T>(String key, {T? defaultValue}) {
    if (key != StorageKeys.picManagerPushConfiguration) return defaultValue;
    return <String, Object>{
          'version': 1,
          'base_url': 'https://images.example',
          'allow_insecure_http': false,
          'auto_push_on_favorite': autoPushOnFavorite,
        }
        as T;
  }
}

class PicManagerTestSecureStorage extends SecureStorageService {
  @override
  Future<String?> getPicManagerPushToken() async => 'secret-token';
}

class RecordingPicManagerPushService extends PicManagerPushService {
  RecordingPicManagerPushService({this.blockUploads = false});

  final bool blockUploads;
  final started = Completer<void>();
  final _release = Completer<void>();
  int calls = 0;
  Uint8List? imageBytes;
  String? fileName;
  Map<String, Object?>? source;

  @override
  Future<PicManagerPushReceipt> upload({
    required PicManagerEndpoint endpoint,
    required String token,
    required Uint8List imageBytes,
    required String fileName,
    required Map<String, Object?> source,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    calls++;
    this.imageBytes = imageBytes;
    this.fileName = fileName;
    this.source = source;
    if (!started.isCompleted) started.complete();
    if (blockUploads) await _release.future;
    return PicManagerPushReceipt(id: 'asset-$calls', deduplicated: false);
  }

  void release() {
    if (!_release.isCompleted) _release.complete();
  }
}
