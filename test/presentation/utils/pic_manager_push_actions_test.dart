import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/data/models/gallery/local_image_record.dart';
import 'package:nai_launcher/presentation/providers/pic_manager_push_provider.dart';
import 'package:nai_launcher/presentation/utils/pic_manager_push_actions.dart';
import 'package:nai_launcher/presentation/widgets/common/image_detail/image_detail_data.dart';

import '../../helpers/pic_manager_test_support.dart';

void main() {
  test('local card and detail upload the same original file bytes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pic_manager_original_bytes_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File(
      '${directory.path}${Platform.pathSeparator}original.webp',
    );
    final originalBytes = Uint8List.fromList([82, 73, 70, 70, 1, 2, 3, 4]);
    await file.writeAsBytes(originalBytes, flush: true);
    final stat = await file.stat();
    final record = LocalImageRecord(
      path: file.path,
      size: stat.size,
      modifiedAt: stat.modified,
    );

    final cardRequest = localImagePicManagerRequest(record);
    final detailRequest = imageDetailPicManagerRequest(
      LocalImageDetailData(record),
    );

    expect(await cardRequest.loadImageBytes(), orderedEquals(originalBytes));
    expect(detailRequest.uploadKey, cardRequest.uploadKey);
    expect(await detailRequest.loadImageBytes(), orderedEquals(originalBytes));
  });

  testWidgets(
    'auto push only follows a successful new favorite and keeps original bytes',
    (tester) async {
      final service = RecordingPicManagerPushService();
      final settings = await createPicManagerTestSettings(
        service: service,
        autoPushOnFavorite: true,
      );
      late BuildContext actionContext;
      late WidgetRef actionRef;
      final originalBytes = Uint8List.fromList([7, 8, 9, 10]);
      final request = PicManagerUploadRequest(
        uploadKey: 'local:/gallery/original.png',
        fileName: 'original.png',
        loadImageBytes: () async => originalBytes,
        pageUrl: 'https://novelai.net/',
        capturedAt: DateTime.utc(2026, 8, 30),
        metadata: const {'image_id': 'original'},
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            picManagerSettingsProvider.overrideWith((_) => settings),
            picManagerPushServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                actionContext = context;
                actionRef = ref;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      var toggleCalls = 0;
      final added = await toggleFavoriteWithPicManagerPush(
        context: actionContext,
        ref: actionRef,
        wasFavorited: false,
        request: request,
        toggleFavorite: () async {
          toggleCalls++;
          return true;
        },
      );
      expect(added, isTrue);
      expect(service.calls, 1);
      expect(service.imageBytes, same(originalBytes));
      expect(
        service.source,
        containsPair('source_name', 'aaalice Nai Launcher'),
      );

      await toggleFavoriteWithPicManagerPush(
        context: actionContext,
        ref: actionRef,
        wasFavorited: true,
        request: request,
        toggleFavorite: () async {
          toggleCalls++;
          return true;
        },
      );
      await toggleFavoriteWithPicManagerPush(
        context: actionContext,
        ref: actionRef,
        wasFavorited: false,
        request: request,
        toggleFavorite: () async {
          toggleCalls++;
          return false;
        },
      );

      expect(toggleCalls, 3);
      expect(service.calls, 1);
    },
  );
}
