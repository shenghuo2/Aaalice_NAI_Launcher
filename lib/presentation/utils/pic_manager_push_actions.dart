import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

import '../../core/cache/online_gallery_image_cache_manager.dart';
import '../../core/utils/localization_extension.dart';
import '../../data/models/gallery/local_image_record.dart';
import '../../data/models/online_gallery/gallery_item.dart';
import '../../data/services/pic_manager_push_service.dart';
import '../providers/pic_manager_push_provider.dart';
import '../widgets/common/app_toast.dart';
import '../widgets/common/image_detail/image_detail_data.dart';
import 'pic_manager_localization.dart';

const _novelAiPageUrl = 'https://novelai.net/';

PicManagerUploadRequest localImagePicManagerRequest(LocalImageRecord record) {
  final metadata = record.metadata?.upgradeFromRawJsonIfNeeded();
  return PicManagerUploadRequest(
    uploadKey: 'local:${record.path}',
    fileName: path.basename(record.path),
    loadImageBytes: () => File(record.path).readAsBytes(),
    pageUrl: _novelAiPageUrl,
    capturedAt: record.modifiedAt,
    seedHint: metadata?.seed,
    metadata: <String, Object?>{
      'image_id': record.path,
      'file_name': path.basename(record.path),
      if (metadata?.width != null) 'width': metadata!.width,
      if (metadata?.height != null) 'height': metadata!.height,
    },
  );
}

PicManagerUploadRequest? onlineGalleryPicManagerRequest(
  GalleryItem item, {
  GalleryMedia? media,
}) {
  final target = media ?? item.cover;
  if (target.capability.isVideo) return null;
  final url = media == null
      ? item.bestQualityUrl.trim()
      : (target.downloadUrl.trim().isNotEmpty
            ? target.downloadUrl.trim()
            : target.displayUrl.trim());
  if (url.isEmpty) return null;

  final uri = Uri.tryParse(url);
  final urlFileName = path.basename(uri?.path ?? '');
  final extension = target.extension?.replaceFirst(RegExp(r'^\.'), '') ?? '';
  final fallbackName = extension.isEmpty
      ? '${item.sourceId.key}_${item.sourceWorkId}.png'
      : '${item.sourceId.key}_${item.sourceWorkId}.$extension';
  final capturedAt =
      DateTime.tryParse(item.createdAt) ?? DateTime.now().toUtc();

  return PicManagerUploadRequest(
    uploadKey: 'online:${item.stableKey}:${target.id}',
    fileName: urlFileName.isEmpty ? fallbackName : urlFileName,
    loadImageBytes: () async {
      final file = await OnlineGalleryImageCacheManager.instance.getSingleFile(
        url,
        key: onlineGalleryImageCacheKeyForUrl(url),
        headers: onlineGalleryImageHeadersForUrl(url),
      );
      return file.readAsBytes();
    },
    pageUrl: _validPageUrl(item.postUrl),
    capturedAt: capturedAt,
    metadata: <String, Object?>{
      'image_id': item.stableKey,
      'source_id': item.sourceId.key,
      'work_id': item.sourceWorkId,
      'media_id': target.id,
      if (target.width > 0) 'width': target.width,
      if (target.height > 0) 'height': target.height,
    },
  );
}

PicManagerUploadRequest imageDetailPicManagerRequest(ImageDetailData image) {
  if (image is LocalImageDetailData) {
    return localImagePicManagerRequest(image.record);
  }
  final metadata = image.metadata;
  final fileInfo = image.fileInfo;
  return PicManagerUploadRequest(
    uploadKey: 'detail:${image.identifier}',
    fileName: fileInfo?.fileName ?? '${image.identifier}.png',
    loadImageBytes: image.getImageBytes,
    pageUrl: _novelAiPageUrl,
    capturedAt: fileInfo?.modifiedAt ?? DateTime.now().toUtc(),
    seedHint: metadata?.seed,
    metadata: <String, Object?>{
      'image_id': image.identifier,
      if (fileInfo != null) 'file_name': fileInfo.fileName,
      if (metadata?.width != null) 'width': metadata!.width,
      if (metadata?.height != null) 'height': metadata!.height,
    },
  );
}

Future<PicManagerPushReceipt?> pushToPicManagerWithToast({
  required BuildContext context,
  required WidgetRef ref,
  required PicManagerUploadRequest request,
}) async {
  try {
    final receipt = await ref
        .read(picManagerUploadsProvider.notifier)
        .uploadRequest(request);
    if (context.mounted) {
      AppToast.success(
        context,
        receipt.deduplicated
            ? context.l10n.picManager_pushDeduplicated
            : context.l10n.picManager_pushSuccess,
      );
    }
    return receipt;
  } catch (error) {
    if (context.mounted) {
      AppToast.error(context, localizePicManagerError(context.l10n, error));
    }
    return null;
  }
}

Future<bool> toggleFavoriteWithPicManagerPush({
  required BuildContext context,
  required WidgetRef ref,
  required bool wasFavorited,
  required Future<bool> Function() toggleFavorite,
  PicManagerUploadRequest? request,
}) async {
  final success = await toggleFavorite();
  final config = ref.read(picManagerSettingsProvider).valueOrNull;
  if (success &&
      !wasFavorited &&
      request != null &&
      config?.isConfigured == true &&
      config!.autoPushOnFavorite) {
    if (context.mounted) {
      await pushToPicManagerWithToast(
        context: context,
        ref: ref,
        request: request,
      );
    } else {
      try {
        await ref
            .read(picManagerUploadsProvider.notifier)
            .uploadRequest(request);
      } catch (_) {
        // The originating surface is gone, so there is nowhere to show errors.
      }
    }
  }
  return success;
}

String _validPageUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty) {
    return uri.toString();
  }
  return _novelAiPageUrl;
}
