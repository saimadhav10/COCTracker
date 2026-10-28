import 'dart:convert';

import 'package:coc_tracker/domain/village.dart';
import 'package:coc_tracker/services/tracker_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final clock = DateTime.utc(2026, 10, 28, 12);
Map<String, dynamic> export({String tag = '#PYLQGR'}) => {
  'tag': tag,
  'timestamp': clock.millisecondsSinceEpoch ~/ 1000,
  'buildings': [
    {'data': 1000001, 'lvl': 14},
    {'data': 1000008, 'lvl': 19, 'cnt': 3},
    {'data': 1000008, 'lvl': 18, 'timer': 3600, 'gear_up': 1},
    {
      'data': 1999999,
      'types': [
        {
          'data': 103000011,
          'modules': [
            {'data': 102000033, 'lvl': 1},
          ],
        },
      ],
    },
  ],
  'spells': [
    {'data': 26000009, 'lvl': 6, 'timer': 7200, 'helper_recurrent': true},
  ],
  'buildings2': [
    {'data': 1000034, 'lvl': 10, 'timer': 50},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TrackerStore.channel, (call) async => null);
  });
  test('expands grouped counts with unique keys and excludes Builder Base', () {
    final village = parseVillage(jsonEncode(export()), now: clock);
    expect(village.townHall, 14);
    expect(village.items.where((e) => e.data == 1000008).length, 4);
    expect(
      village.items.map((e) => e.key).toSet().length,
      village.items.length,
    );
    expect(village.items.any((e) => e.data == 1000034), false);
  });
  test('anchors timers to export timestamp rather than import time', () {
    final village = parseVillage(
      jsonEncode(export()),
      now: clock.add(const Duration(hours: 3)),
    );
    expect(
      village.active.first.finishesAt,
      clock.add(const Duration(hours: 1)),
    );
    expect(village.active.first.level, 18);
    expect(village.active.first.targetLevel, 19);
    expect(
      village.active.first.ready(clock.add(const Duration(hours: 3))),
      true,
    );
    expect(
      village.active.first.level,
      18,
      reason: 'Elapsed timers do not auto-complete',
    );
  });
  test('retains unknown nested structures and helper flags', () {
    final village = parseVillage(jsonEncode(export()), now: clock);
    final restored = Village.fromJson(jsonDecode(jsonEncode(village.toJson())));
    expect(
      restored.items.firstWhere((e) => e.data == 1999999).extra['types'],
      isNotEmpty,
    );
    expect(
      restored.items
          .firstWhere((e) => e.section == 'spells')
          .extra['helper_recurrent'],
      true,
    );
  });
  test('rejects malformed, oversized, future, and invalid count imports', () {
    for (final invalid in [
      'not json',
      '[]',
      '{}',
      'x' * 2000001,
      jsonEncode({
        ...export(),
        'timestamp':
            clock.add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000,
      }),
      jsonEncode({
        ...export(),
        'buildings': [
          {'data': 1000001, 'lvl': 14, 'cnt': -1},
        ],
      }),
      jsonEncode({
        ...export(),
        'buildings': [
          {'data': 1000001, 'lvl': 14, 'timer': '3600'},
        ],
      }),
    ]) {
      expect(() => parseVillage(invalid, now: clock), throwsFormatException);
    }
  });
  test('flags snapshot refresh after 24h or expected upgrade completion', () {
    final village = parseVillage(jsonEncode(export()), now: clock);
    expect(village.needsRefresh(clock), false);
    expect(village.needsRefresh(clock.add(const Duration(hours: 1))), true);
    expect(village.needsRefresh(clock.add(const Duration(days: 2))), true);
  });
  test(
    'backup roundtrip preserves all profiles, preferences and manual changes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = TrackerStore(prefs);
      await store.add(
        parseVillage(jsonEncode(export()), now: clock, name: 'Main'),
      );
      await store.add(
        parseVillage(
          jsonEncode(export(tag: '#QGRJCUV')),
          now: clock,
          name: 'Mini',
        ),
      );
      store.villages.first.items.first.level = 15;
      store.theme = 'dark';
      await store.save();
      final fresh = TrackerStore(prefs)..load();
      expect(fresh.villages.length, 2);
      expect(fresh.selected?.name, 'Mini');
      expect(fresh.villages.first.townHall, 15);
      expect(fresh.theme, 'dark');
      await fresh.restore(store.backup());
      expect(
        fresh.villages.first.active.first.finishesAt,
        clock.add(const Duration(hours: 1)),
      );
    },
  );
  test(
    'reimport updates the same player tag without duplicating profiles',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = TrackerStore(await SharedPreferences.getInstance());
      await store.add(
        parseVillage(jsonEncode(export()), now: clock, name: 'Old'),
      );
      await store.add(
        parseVillage(jsonEncode(export()), now: clock, name: 'New'),
      );
      expect(store.villages.single.name, 'New');
    },
  );
  test(
    'corrupt storage is preserved and cannot be silently overwritten',
    () async {
      SharedPreferences.setMockInitialValues({'tracker.v1': '{broken'});
      final prefs = await SharedPreferences.getInstance();
      final store = TrackerStore(prefs)..load();
      expect(store.recoveryData, '{broken');
      await expectLater(store.save(), throwsStateError);
      expect(prefs.getString('tracker.v1'), '{broken');
      await expectLater(store.restore('{"schema":2}'), throwsFormatException);
      expect(prefs.getString('tracker.v1'), '{broken');
    },
  );
  test('invalid backup restores do not replace valid data', () async {
    SharedPreferences.setMockInitialValues({});
    final store = TrackerStore(await SharedPreferences.getInstance());
    await store.add(parseVillage(jsonEncode(export()), now: clock));
    final original = store.backup();
    final invalid = jsonDecode(original) as Map<String, dynamic>;
    invalid['villages'][0]['items'][0]['level'] = -1;
    await expectLater(
      store.restore(jsonEncode(invalid)),
      throwsFormatException,
    );
    expect(store.backup(), original);
  });
}
