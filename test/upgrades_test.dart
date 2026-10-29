import 'dart:convert';
import 'dart:io';
import 'package:coc_tracker/domain/upgrades.dart';
import 'package:coc_tracker/domain/village.dart';
import 'package:coc_tracker/services/game_updates.dart';
import 'package:coc_tracker/services/tracker_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final catalogue = decodeCatalogue(
    File('assets/catalogue/home.json').readAsStringSync(),
  );
  Village village({int th = 14}) => Village(
    tag: '#PYLQGR',
    name: 'Test only',
    exportedAt: DateTime.utc(2026),
    importedAt: DateTime.utc(2026),
    items: [
      VillageItem(key: 'th', data: 1000001, section: 'buildings', level: th),
      VillageItem(key: 'camp', data: 1000000, section: 'buildings', level: 11),
      VillageItem(key: 'gold', data: 1000005, section: 'buildings', level: 15),
      VillageItem(
        key: 'cannon',
        data: 1000008,
        section: 'buildings',
        level: 19,
      ),
    ],
  );
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TrackerStore.channel, (call) async => null);
  });
  test(
    'eligibility rejects higher Town Halls and unfinished lab prerequisites',
    () {
      final v = village(th: 7);
      final p = UpgradePlanner(v, catalogue);
      final late = VillageItem(
        key: 'eagle',
        data: 1000031,
        section: 'buildings',
        level: 0,
      );
      expect(p.choice(late).eligible, false);
      final troop = VillageItem(
        key: 'barb',
        data: 4000000,
        section: 'units',
        level: 1,
      );
      expect(p.choice(troop).eligible, false);
      expect(p.choice(troop).lockReason, contains('laboratory'));
    },
  );
  test('missing building slots are offered without mutating the snapshot', () {
    final v = village();
    final before = v.items.length;
    final p = UpgradePlanner(v, catalogue);
    final camps = p.choices.where((e) => e.item.data == 1000000).toList();
    expect(camps.length, 4);
    expect(camps.where((e) => e.missing).length, 3);
    expect(v.items.length, before);
    expect(p.inventory.map((e) => e.key).toSet().length, p.inventory.length);
  });
  test(
    'recommendations prioritize offense prerequisites and exclude locked/maxed items',
    () {
      final p = UpgradePlanner(village(), catalogue);
      final next = p.recommendations;
      expect(catalogue.entry(next.first.item.data)?['slug'], 'laboratory');
      expect(next.every((c) => c.eligible && !c.item.upgrading), true);
      expect(next.map((c) => c.item.data).toSet().length, next.length);
      expect(next.length, lessThanOrEqualTo(8));
    },
  );
  test('storage capacity is checked using completed levels', () {
    final v = village();
    final p = UpgradePlanner(v, catalogue);
    expect(p.storageCapacity('Gold'), greaterThan(0));
    final item = v.items.firstWhere((e) => e.data == 1000008);
    final level = {...catalogue.next(item)!, 'cost': 999999999};
    expect(p.blocked(item, level), contains('storage'));
  });
  test('merged defenses are not offered as ordinary new construction', () {
    final p = UpgradePlanner(village(th: 16), catalogue);
    final id = int.parse(
      catalogue.entries.entries
          .firstWhere((e) => e.value['slug'] == 'ricochet-cannon')
          .key,
    );
    final c = p.choice(
      VillageItem(key: 'merge', data: id, section: 'buildings', level: 0),
    );
    expect(c.eligible, false);
    expect(c.lockReason, contains('Merged defense'));
  });
  test('unbuilt builder huts use slot prices without Gem discounts', () {
    final p = UpgradePlanner(village(), catalogue, builderDiscount: 20);
    final huts = p.choices
        .where((e) => catalogue.entry(e.item.data)?['slug'] == 'builders-hut')
        .toList();
    expect(
      huts
          .map((e) => p.costs(e.item, e.level!)['Gems'])
          .whereType<num>()
          .toList(),
      [250, 500, 1000, 2000],
    );
  });
  test(
    'merge tracking consumes source defenses and cancellation restores them',
    () async {
      final v = village(th: 16);
      final p = UpgradePlanner(v, catalogue);
      final cannon = v.items.last;
      cannon.level = catalogue.maxLevel(cannon, 15)!;
      v.items.add(
        VillageItem(
          key: 'cannon2',
          data: cannon.data,
          section: 'buildings',
          level: cannon.level,
        ),
      );
      // Four completed storages provide enough capacity for the merge price.
      for (var n = 0; n < 4; n++) {
        v.items.add(
          VillageItem(
            key: 'storage$n',
            data: 1000005,
            section: 'buildings',
            level: 17,
          ),
        );
      }
      final c = p.choices.firstWhere(
        (e) => catalogue.entry(e.item.data)?['slug'] == 'ricochet-cannon',
      );
      expect(c.eligible, true, reason: c.lockReason);
      final store = TrackerStore(await SharedPreferences.getInstance());
      await store.add(v);
      await store.start(c, catalogue);
      expect(v.items.where((e) => e.data == cannon.data), isEmpty);
      final restored = TrackerStore(store.prefs)..load();
      final merged = restored.selected!.items.firstWhere(
        (e) => e.data == c.item.data,
      );
      await restored.cancel(merged);
      expect(
        restored.selected!.items.where((e) => e.data == cannon.data).length,
        2,
      );
      expect(restored.selected!.items.any((e) => e.data == c.item.data), false);
    },
  );
  test('Gold Pass estimates do not discount equipment ores', () {
    final v = village();
    final p = UpgradePlanner(
      v,
      catalogue,
      builderDiscount: 20,
      researchDiscount: 10,
    );
    final cannon = v.items.last;
    final next = catalogue.next(cannon)!;
    expect(p.duration(cannon, next), ((next['seconds'] as num) * .8).ceil());
    final gear = VillageItem(
      key: 'gear',
      data: 90000000,
      section: 'equipment',
      level: 1,
    );
    expect(
      p.costs(gear, catalogue.next(gear)!),
      Map<String, num>.from(catalogue.next(gear)!['ores']),
    );
  });
  test(
    'inline construction, cancel, completion and backup retain absolute finish times',
    () async {
      final store = TrackerStore(await SharedPreferences.getInstance());
      final v = village();
      await store.add(v);
      final p = UpgradePlanner(v, catalogue);
      final next = p.choices.firstWhere(
        (e) =>
            e.missing && e.eligible && (e.level?['seconds'] as num? ?? 0) > 0,
      );
      final start = DateTime.utc(2026, 10, 28, 12);
      await store.start(next, catalogue, clock: start);
      var item = v.items.firstWhere((e) => e.key == next.item.key);
      final end = item.finishesAt;
      expect(end, start.add(Duration(seconds: p.duration(item, next.level!))));
      final reloaded = TrackerStore(store.prefs)..load();
      expect(
        reloaded.selected!.items
            .firstWhere((e) => e.key == item.key)
            .finishesAt,
        end,
      );
      await expectLater(store.start(next, catalogue), throwsStateError);
      await store.cancel(item);
      expect(v.items.any((e) => e.key == item.key), false);
      await store.start(
        p.choices.firstWhere((e) => e.item.key == next.item.key),
        catalogue,
        clock: start,
      );
      item = v.items.firstWhere((e) => e.key == next.item.key);
      await store.complete(item);
      expect(item.level, 1);
      expect(item.finishesAt, isNull);
    },
  );
  test('imported timers are not altered when boosts change', () async {
    final store = TrackerStore(await SharedPreferences.getInstance());
    final v = village();
    v.items.last.finishesAt = DateTime.utc(2027);
    v.items.last.targetLevel = 20;
    await store.add(v);
    v.builderDiscount = 20;
    await store.save();
    expect(v.items.last.finishesAt, DateTime.utc(2027));
  });
  test('legacy backup themes migrate without losing player data', () async {
    final v = village();
    final raw = jsonEncode({
      'schema': 1,
      'theme': 'dark',
      'villages': [v.toJson()],
    });
    SharedPreferences.setMockInitialValues({'tracker.v1': raw});
    final store = TrackerStore(await SharedPreferences.getInstance())..load();
    expect(store.theme, 'citadel');
    expect(store.selected!.tag, v.tag);
    expect(store.recoveryData, isNull);
  });
  test(
    'live countdown shows seconds and completion without auto-advancing levels',
    () {
      expect(
        liveCountdown(
          const Duration(days: 1, hours: 2, minutes: 3, seconds: 4),
        ),
        '1d 02:03:04',
      );
      expect(liveCountdown(Duration.zero), 'Ready to confirm');
    },
  );
}
