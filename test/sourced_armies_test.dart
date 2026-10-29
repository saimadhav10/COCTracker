import 'dart:convert';
import 'dart:io';
import 'package:coc_tracker/domain/sourced_armies.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'source rosters retain exact published counts and no invented heroes',
    () async {
      final armies = await loadSourcedArmies();
      final dragon = armies.firstWhere((a) => a.source.endsWith('/397'));
      expect(dragon.townHall, 14);
      expect(dragon.troops, {'Dragon': 10, 'Balloon': 8, 'Electro Dragon': 2});
      expect(dragon.spells, {'Lightning': 11});
      expect(dragon.heroes, [
        'Barbarian King',
        'Archer Queen',
        'Grand Warden',
        'Royal Champion',
      ]);
      expect(
        armies.firstWhere((a) => a.source.endsWith('/518')).heroes,
        isEmpty,
      );
      expect(
        armies.any(
          (a) => a.source.endsWith('/1267') || a.source.endsWith('/1668'),
        ),
        false,
      );
    },
  );
  test(
    'every TH has sourced coverage with at most two armies per category',
    () async {
      final armies = await loadSourcedArmies();
      expect(armies.map((a) => a.source).toSet().length, armies.length);
      for (var th = 1; th <= 18; th++) {
        final rows = armies.where((a) => a.townHall == th).toList();
        expect(rows, isNotEmpty, reason: 'TH$th');
        for (final type in ['Air', 'Ground', 'Hybrid']) {
          expect(
            rows.where((a) => a.type == type).length,
            lessThanOrEqualTo(2),
          );
        }
      }
      expect(
        armies.where((a) => a.townHall == 1).every((a) => a.type == 'Ground'),
        true,
      );
      expect(armies.where((a) => a.townHall == 14).length, 6);
      final compositions = armies
          .map((a) => jsonEncode([a.townHall, a.troops, a.spells, a.heroes]))
          .toList();
      expect(compositions.toSet().length, compositions.length);
    },
  );
  test(
    'all sourced troop, spell and hero art exists without substituting units',
    () async {
      final armies = await loadSourcedArmies();
      for (final army in armies) {
        expect(army.troops, isNotEmpty);
        expect(
          [...army.troops.values, ...army.spells.values].every((n) => n > 0),
          true,
        );
        for (final name in [
          ...army.troops.keys,
          ...army.spells.keys,
          ...army.heroes,
        ]) {
          final image = army.artwork[normaliseArmyName(name)];
          expect(image, isNotNull, reason: name);
          expect(File(image!).existsSync(), true, reason: name);
        }
      }
    },
  );
  test(
    'army catalogue has no generated descriptions or performance metrics',
    () {
      final data =
          jsonDecode(File('assets/catalogue/armies.json').readAsStringSync())
              as Map;
      expect(data['checkedAt'], '2026-10-29');
      for (final row in data['armies'] as List) {
        expect((row as List).length, 7);
        expect(row[2], isPositive);
      }
    },
  );
}
