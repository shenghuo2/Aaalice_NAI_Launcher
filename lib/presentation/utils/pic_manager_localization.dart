import '../../data/models/pic_manager/pic_manager_push_config.dart';
import '../../data/services/pic_manager_push_service.dart';
import '../../l10n/app_localizations.dart';

String localizePicManagerError(AppLocalizations l10n, Object error) {
  if (error is PicManagerConfigException) {
    return switch (error.reason) {
      PicManagerConfigFailure.invalidUrl => l10n.picManager_errorInvalidUrl,
      PicManagerConfigFailure.insecureHttp => l10n.picManager_errorInsecureHttp,
    };
  }
  if (error is PicManagerPushException) {
    return switch (error.failure) {
      PicManagerPushFailure.unauthorized => l10n.picManager_errorUnauthorized,
      PicManagerPushFailure.invalidRequest =>
        l10n.picManager_errorInvalidRequest,
      PicManagerPushFailure.server => l10n.picManager_errorServer,
      PicManagerPushFailure.timeout => l10n.picManager_errorTimeout,
      PicManagerPushFailure.network => l10n.picManager_errorNetwork,
      PicManagerPushFailure.invalidResponse =>
        l10n.picManager_errorInvalidResponse,
      PicManagerPushFailure.alreadyUploading =>
        l10n.picManager_errorAlreadyUploading,
      PicManagerPushFailure.notConfigured => l10n.picManager_errorNotConfigured,
    };
  }
  return l10n.picManager_errorInvalidResponse;
}
