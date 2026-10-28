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
            {'data': 1000014, 'lvl': 9, 'timer': 90000},
            {'data': 1000027, 'lvl': 7, 'timer': 190000},
          ],
          'heroes': [
            {'data': 28000001, 'lvl': 75},
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
    await tester.ensureVisible(find.text('Import your first village'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import your first village'));
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
    await tester.tap(find.text('Import').last);
    await tester.pumpAndSettle();
    expect(store.villages.single.name, 'My main');
    expect(find.text('My main'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('upgrade detail can manually start, then confirm an upgrade', (
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
    await tester.tap(find.text('Upgrades').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Cannon');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ListTile, 'Cannon').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Cannon').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record upgrade'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '1');
    await tester.enterText(fields.at(2), '0');
    await tester.tap(find.text('Start timer'));
    await tester.pumpAndSettle();
    final cannon = store.selected!.items.firstWhere(
      (e) => e.data == 1000008 && e.upgrading,
    );
    expect(cannon.targetLevel, 20);
    await tester.tap(find.widgetWithText(ListTile, 'Cannon').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm complete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(cannon.level, 20);
    expect(cannon.upgrading, false);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('phone layouts render in both themes and produce previews', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await makeStore();
    final data = await catalogue();
    await tester.runAsync(() async {
      await (FontLoader('Manrope')..addFont(
            Future.value(
              ByteData.sublistView(
                File('assets/fonts/Manrope.ttf').readAsBytesSync(),
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
    for (final theme in ['light', 'dark']) {
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
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.text('Village preferences.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
