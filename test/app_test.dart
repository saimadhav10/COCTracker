import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:coc_tracker/app.dart';
import 'package:coc_tracker/domain/village.dart';
import 'package:coc_tracker/services/game_updates.dart';
import 'package:coc_tracker/services/tracker_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<TrackerStore> makeStore({bool populated = true}) async {
  SharedPreferences.setMockInitialValues({});
  final store = TrackerStore(await SharedPreferences.getInstance());
  if (populated) {
    final clock = DateTime.now().toUtc();
    await store.add(
      parseVillage(
        jsonEncode({
          'tag': '#PYLQGR',
          'timestamp': clock.millisecondsSinceEpoch ~/ 1000,
          'buildings': [
            {'data': 1000001, 'lvl': 14},
            {'data': 1000008, 'lvl': 19, 'cnt': 6},
            {'data': 1000003, 'lvl': 15, 'cnt': 4},
            {'data': 1000005, 'lvl': 15, 'cnt': 4},
            {'data': 1000000, 'lvl': 11, 'cnt': 4},
            {'data': 1000014, 'lvl': 9, 'timer': 90000},
            {'data': 1000027, 'lvl': 7, 'timer': 190000},
          ],
          'heroes': [
            {'data': 28000001, 'lvl': 75},
          ],
          'units': [
            {'data': 4000000, 'lvl': 9},
            {'data': 4000001, 'lvl': 9},
            {'data': 4000003, 'lvl': 10},
            {'data': 4000008, 'lvl': 9},
          ],
          'spells': [
            {'data': 26000009, 'lvl': 6, 'timer': 133120},
          ],
          'pets': [
            {'data': 73000002, 'lvl': 1, 'timer': 56260},
          ],
        }),
        name: 'Emerald Keep',
        now: clock,
      ),
    );
  }
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          TrackerStore.channel,
          (call) async => call.method == 'status' ? {'supported': false} : null,
        );
  });
  Future<Catalogue> catalogue() async =>
      decodeCatalogue(File('assets/catalogue/home.json').readAsStringSync());

  testWidgets('empty state imports a village and persists it', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await makeStore(populated: false);
    await tester.pumpWidget(
      TrackerApp(store: store, catalogue: await catalogue()),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Import your first village'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Import your first village'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'My main');
    await tester.enterText(
      find.byType(TextField).last,
      jsonEncode({
        'tag': '#PYLQGR',
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'buildings': [
          {'data': 1000001, 'lvl': 14},
        ],
      }),
    );
    await tester.tap(find.byTooltip('Import').last);
    await tester.pumpAndSettle();
    expect(store.villages.single.name, 'My main');
    expect(find.text('My main'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('inline actions start and complete without opening details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await makeStore();
    await tester.pumpWidget(
      TrackerApp(store: store, catalogue: await catalogue()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Upgrades').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Cannon');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Upgrade Cannon').first);
    await tester.pumpAndSettle();
    final cannon = store.selected!.items.firstWhere(
      (e) => e.data == 1000008 && e.upgrading,
    );
    expect(cannon.targetLevel, 20);
    await tester.tap(find.byTooltip('Complete Cannon').first);
    await tester.pumpAndSettle();
    expect(cannon.level, 20);
    expect(cannon.upgrading, false);
    await tester.enterText(find.byType(TextField), "Builder's Hut");
    await tester.pumpAndSettle();
    // Different purchase slots must keep their own row and Gem price.
    for (final price in ['250', '500', '1,000', '2,000']) {
      await tester.scrollUntilVisible(
        find.text(price),
        200,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      expect(find.text(price), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('phone layouts render in all themes and produce previews', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await makeStore();
    final data = await catalogue();
    await tester.runAsync(() async {
      await (FontLoader('SpaceGrotesk')..addFont(
            Future.value(
              ByteData.sublistView(
                File('assets/fonts/SpaceGrotesk.ttf').readAsBytesSync(),
              ),
            ),
          ))
          .load();
      await (FontLoader('PlusJakartaSans')..addFont(
            Future.value(
              ByteData.sublistView(
                File('assets/fonts/PlusJakartaSans.ttf').readAsBytesSync(),
              ),
            ),
          ))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: TrackerApp(store: store, catalogue: data),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      for (final entry in data.entries.values) {
        final asset = entry['image'];
        if (asset is String) {
          await precacheImage(AssetImage(asset), boundary.currentContext!);
        }
      }
      final armyArt =
          jsonDecode(
                File('assets/catalogue/army_units.json').readAsStringSync(),
              )
              as Map;
      for (final unit in armyArt.values) {
        await precacheImage(
          AssetImage(unit['image'] as String),
          boundary.currentContext!,
        );
      }
      for (final asset in [
        'resource_gold',
        'resource_elixir',
        'resource_dark_elixir',
        'resource_gems',
      ]) {
        await precacheImage(
          AssetImage('assets/icons/$asset.webp'),
          boundary.currentContext!,
        );
      }
    });
    await tester.pumpAndSettle();
    for (final theme in ['citadel', 'onyx', 'purple']) {
      store.theme = theme;
      await store.save();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('docs/screenshots/village-$theme.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    store.theme = 'citadel';
    await store.save();
    expect(find.textContaining('mapped level steps'), findsNothing);
    expect(find.textContaining('Resources still needed'), findsNothing);
    expect(find.byTooltip('Completion time'), findsWidgets);
    for (final page in [
      'Upgrades',
      'Armies',
      'Recommendations',
      'Profiles',
      'Settings',
    ]) {
      await tester.tap(find.byTooltip(page).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'docs/screenshots/${page.toLowerCase()}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
    await tester.scrollUntilVisible(find.text('ABOUT THE CREATOR'), 500);
    expect(find.text('@saimadhav10'), findsOneWidget);
    await tester.pumpAndSettle();
    final creatorRender =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await creatorRender.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'docs/screenshots/creator.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(360, 800);
    for (final page in [
      'Home',
      'Upgrades',
      'Armies',
      'Recommendations',
      'Profiles',
      'Settings',
    ]) {
      await tester.tap(find.byTooltip(page).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
