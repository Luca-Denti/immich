import 'dart:async';
import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/locales.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/config/app_config.dart';
import 'package:immich_mobile/domain/models/timeline.model.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/generated/codegen_loader.g.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_viewer.page.dart';
import 'package:immich_mobile/presentation/widgets/images/thumbnail_tile.widget.dart';
import 'package:immich_mobile/presentation/widgets/timeline/timeline.widget.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../fixtures/asset.stub.dart';
import '../../../unit/presentation/presentation_context.dart';

Future<TimelineService> _createReadyTimelineService(List<BaseAsset> assets) async {
  final timelineService = TimelineService((
    assetSource: (index, count) async => assets.sublist(index, math.min(index + count, assets.length)),
    bucketSource: () => Stream.value([TimeBucket(date: DateTime(2025), assetCount: assets.length)]),
    origin: TimelineOrigin.main,
  ));

  for (var i = 0; i < 20 && timelineService.totalAssets != assets.length; i++) {
    await Future<void>.microtask(() {});
  }
  return timelineService;
}

void main() {
  testWidgets('only animates the timeline when the last viewed asset is off-screen', (tester) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(1206, 2622);
    addTearDown(tester.view.reset);

    final presentationContext = await PresentationContext.create();
    addTearDown(presentationContext.dispose);
    when(() => presentationContext.service.asset.service.watchAsset(any())).thenAnswer((_) => const Stream.empty());

    final assets = List<BaseAsset>.generate(200, (i) => LocalAssetStub.image1.copyWith(id: 'a$i'));
    final timelineService = await _createReadyTimelineService(assets);
    addTearDown(timelineService.dispose);

    final router = RootStackRouter.build(
      routes: [
        AutoRoute(
          initial: true,
          page: PageInfo(
            'Timeline',
            builder: (_) => Scaffold(
              body: const Timeline(
                withScrubber: false,
                readOnly: true,
                groupBy: GroupAssetsBy.none,
                appBar: SliverToBoxAdapter(child: SizedBox.shrink()),
              ),
              bottomNavigationBar: NavigationBar(
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.photo_library), label: 'Photos'),
                  NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
                ],
              ),
            ),
          ),
        ),
        AutoRoute(
          page: AssetViewerRoute.page,
          type: RouteType.custom(
            customRouteBuilder: <T>(_, child, page) =>
                PageRouteBuilder<T>(settings: page, opaque: false, pageBuilder: (_, _, _) => child),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: locales.values.toList(),
        path: translationsPath,
        startLocale: locales.values.first,
        fallbackLocale: locales.values.first,
        saveLocale: false,
        useFallbackTranslations: true,
        assetLoader: const CodegenLoader(),
        child: ProviderScope(
          overrides: [
            ...presentationContext.overrides,
            timelineServiceProvider.overrideWithValue(timelineService),
            appConfigProvider.overrideWithValue(const AppConfig()),
          ],
          child: Builder(
            builder: (context) => MaterialApp.router(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              routerConfig: router.config(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester.takeException();

    final timelinePosition = tester
        .state<ScrollableState>(find.descendant(of: find.byType(Timeline), matching: find.byType(Scrollable)).first)
        .position;
    expect(timelinePosition.pixels, 0);

    // Moving to another row in the visible viewport should not move the timeline.
    await tester.tap(find.byType(ThumbnailTile).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    tester.takeException();
    expect(find.byType(AssetViewer), findsOneWidget);

    final pageView = tester.widget<PageView>(find.byType(PageView));
    pageView.controller!.jumpToPage(8);
    await tester.pump();

    unawaited(router.maybePop());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.idle();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    tester.takeException();

    expect(find.byType(AssetViewer), findsNothing);
    expect(timelinePosition.pixels, 0);

    // A row that is only partially visible above the bottom navigation bar must be revealed completely.
    await tester.tap(find.byType(ThumbnailTile).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    tester.takeException();
    expect(find.byType(AssetViewer), findsOneWidget);

    final partiallyVisiblePageView = tester.widget<PageView>(find.byType(PageView));
    partiallyVisiblePageView.controller!.jumpToPage(28);
    await tester.pump();

    unawaited(router.maybePop());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.idle();
    await tester.pump();
    tester.takeException();

    expect(find.byType(AssetViewer), findsNothing);
    expect(timelinePosition.pixels, 0);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(timelinePosition.pixels, greaterThan(0));
    expect(timelinePosition.pixels, lessThan(100));

    timelinePosition.jumpTo(0);
    await tester.pump();

    // Moving off-screen should animate the shortest distance that reveals the row.
    await tester.tap(find.byType(ThumbnailTile).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    tester.takeException();
    expect(find.byType(AssetViewer), findsOneWidget);

    final reopenedPageView = tester.widget<PageView>(find.byType(PageView));
    reopenedPageView.controller!.jumpToPage(100);
    await tester.pump();

    unawaited(router.maybePop());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.idle();
    await tester.pump();
    tester.takeException();

    expect(find.byType(AssetViewer), findsNothing);
    expect(timelinePosition.pixels, 0);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final intermediateOffset = timelinePosition.pixels;
    expect(intermediateOffset, greaterThan(0));

    await tester.pump(const Duration(milliseconds: 200));
    expect(timelinePosition.pixels, greaterThan(1000));
    expect(timelinePosition.pixels, greaterThan(intermediateOffset));
  });
}
