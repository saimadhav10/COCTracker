import 'dart:io';

import 'package:coc_tracker/domain/village.dart';
import 'package:coc_tracker/services/game_updates.dart';
import 'package:flutter_test/flutter_test.dart';

// Optional local smoke check: the file path and player export never enter Git.
void main() {
  const input = String.fromEnvironment('EXPORT_FILE');
  test(
    'provided export imports with distinct instances and mapped names',
    () {
      final village = parseVillage(File(input).readAsStringSync());
      final catalogue = decodeCatalogue(
        File('assets/catalogue/home.json').readAsStringSync(),
      );
      expect(village.items, isNotEmpty);
      expect(
        village.items.map((e) => e.key).toSet().length,
        village.items.length,
      );
      expect(
        village.items.every((e) => homeSections.contains(e.section)),
        true,
      );
      expect(
        village.active.every((e) => e.finishesAt!.isAfter(village.exportedAt)),
        true,
      );
      final mapped = village.items
          .where((e) => catalogue.entry(e.data) != null)
          .length;
      expect(mapped / village.items.length, greaterThan(.95));
    },
    skip: input.isEmpty
        ? 'Set EXPORT_FILE to validate a private game export.'
        : false,
  );
}
