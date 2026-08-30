import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:nai_launcher/core/platform/platform_capabilities.dart';
import 'package:nai_launcher/data/models/gallery/local_image_record.dart';
import 'package:nai_launcher/data/models/online_gallery/gallery_item.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/pic_manager_push_provider.dart';
import 'package:nai_launcher/presentation/utils/pic_manager_push_actions.dart';
import 'package:nai_launcher/presentation/widgets/common/card_action_buttons.dart';
import 'package:nai_launcher/presentation/widgets/common/image_detail/components/detail_top_bar.dart';
import 'package:nai_launcher/presentation/widgets/common/image_detail/image_detail_data.dart';
import 'package:nai_launcher/presentation/widgets/danbooru_post_card.dart';
import 'package:nai_launcher/presentation/widgets/gallery/local_image_card_3d.dart';

import '../../helpers/pic_manager_test_support.dart';

void main() {
  setUp(() {
    PlatformCapabilities.debugOverride = PlatformCapabilities.forPlatform(
      TargetPlatform.windows,
    );
  });

  tearDown(() {
    PlatformCapabilities.debugOverride = null;
  });

  testWidgets('manual push is immediately before every card favorite action', (
    tester,
  ) async {
    final service = RecordingPicManagerPushService();
    final settings = await createPicManagerTestSettings(
      service: service,
      autoPushOnFavorite: false,
    );
    final record = await _localRecord(tester);

    Widget app(Widget child) => ProviderScope(
      overrides: [
        picManagerSettingsProvider.overrideWith((_) => settings),
        picManagerPushServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(alignment: Alignment.topLeft, child: child),
        ),
      ),
    );

    await tester.pumpWidget(
      app(
        LocalImageCard3D(
          record: record,
          width: 220,
          height: 120,
          onFavoriteToggle: () {},
        ),
      ),
    );
    await tester.pump();
    var actions = tester.widget<CardActionButtons>(
      find.byType(CardActionButtons),
    );
    expect(actions.buttons.take(2).map((button) => button.tooltip), [
      'Push to Pic Manager',
      'Favorite',
    ]);

    const post = GalleryItem(
      id: 42,
      fileUrl: 'https://cdn.example/original.png',
      previewFileUrl: 'https://cdn.example/preview.png',
      width: 832,
      height: 1216,
    );
    await tester.pumpWidget(
      app(
        DanbooruPostCard(
          post: post,
          itemWidth: 220,
          layoutAspectRatio: 1,
          loadMedia: false,
          isFavorited: false,
          onTap: () {},
          onTagTap: (_) {},
          onFavoriteToggle: () {},
        ),
      ),
    );
    await tester.pump();
    actions = tester.widget<CardActionButtons>(find.byType(CardActionButtons));
    expect(actions.buttons.take(2).map((button) => button.tooltip), [
      'Push to Pic Manager',
      'Favorite',
    ]);
  });

  testWidgets('auto mode hides push and merges its busy state into favorite', (
    tester,
  ) async {
    final service = RecordingPicManagerPushService(blockUploads: true);
    addTearDown(service.release);
    final settings = await createPicManagerTestSettings(
      service: service,
      autoPushOnFavorite: true,
    );
    final record = await _localRecord(tester);
    final container = ProviderContainer(
      overrides: [
        picManagerSettingsProvider.overrideWith((_) => settings),
        picManagerPushServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: LocalImageCard3D(
              record: record,
              width: 220,
              height: 120,
              onFavoriteToggle: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    var actions = tester.widget<CardActionButtons>(
      find.byType(CardActionButtons),
    );
    expect(
      actions.buttons.where(
        (button) => button.tooltip == 'Push to Pic Manager',
      ),
      isEmpty,
    );
    expect(actions.buttons.first.isLoading, isFalse);

    final upload = container
        .read(picManagerUploadsProvider.notifier)
        .uploadRequest(
          PicManagerUploadRequest(
            uploadKey: localImagePicManagerRequest(record).uploadKey,
            fileName: 'original.png',
            loadImageBytes: () async => Uint8List.fromList([1, 2, 3]),
            pageUrl: 'https://novelai.net/',
            capturedAt: DateTime.utc(2026, 8, 30),
          ),
        );
    await tester.pump();
    actions = tester.widget<CardActionButtons>(find.byType(CardActionButtons));
    expect(actions.buttons.first.tooltip, 'Favorite');
    expect(actions.buttons.first.isLoading, isTrue);

    service.release();
    await tester.runAsync(() => upload);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('local detail puts manual push beside favorite', (tester) async {
    final service = RecordingPicManagerPushService();
    final settings = await createPicManagerTestSettings(
      service: service,
      autoPushOnFavorite: false,
    );
    final record = await _localRecord(tester);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          picManagerSettingsProvider.overrideWith((_) => settings),
          picManagerPushServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DetailTopBar(
              currentIndex: 0,
              totalImages: 1,
              currentImage: LocalImageDetailData(record),
              onClose: () {},
              onFavoriteToggle: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final push = find.byTooltip('Push to Pic Manager');
    final favorite = find.byIcon(Icons.favorite_border);
    expect(push, findsOneWidget);
    expect(favorite, findsOneWidget);
    expect(tester.getCenter(push).dx, lessThan(tester.getCenter(favorite).dx));
  });
}

Future<LocalImageRecord> _localRecord(WidgetTester tester) async {
  final directory = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('pic_manager_controls_'),
  ))!;
  addTearDown(() => directory.delete(recursive: true));
  final file = File('${directory.path}${Platform.pathSeparator}original.png');
  await tester.runAsync(
    () => file.writeAsBytes(
      image.encodePng(image.Image(width: 16, height: 16)),
      flush: true,
    ),
  );
  final stat = (await tester.runAsync(file.stat))!;
  return LocalImageRecord(
    path: file.path,
    size: stat.size,
    modifiedAt: stat.modified,
  );
}
