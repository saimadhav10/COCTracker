import 'village.dart';

class UpgradeChoice {
  const UpgradeChoice(
    this.item,
    this.level,
    this.lockReason, {
    this.missing = false,
  });
  final VillageItem item;
  final Map<String, dynamic>? level;
  final String? lockReason;
  final bool missing;
  bool get eligible => !item.upgrading && level != null && lockReason == null;
  bool get maxed =>
      !item.upgrading &&
      (lockReason == 'At catalogue maximum' ||
          (lockReason?.startsWith('At Town Hall ') ?? false));
}

String categoryOf(VillageItem item, Catalogue catalogue) {
  final c = catalogue.entry(item.data)?['category'];
  if (item.section == 'heroes') return 'Heroes';
  if (item.section == 'pets') return 'Pets';
  if (item.section == 'equipment') return 'Equipment';
  if (['units', 'spells', 'siege_machines'].contains(item.section)) {
    return 'Lab';
  }
  if (['defense', 'crafted-defense', 'trap'].contains(c)) return 'Defenses';
  if (c == 'army') return 'Army';
  if (c == 'wall') return 'Walls';
  return 'Buildings';
}

class UpgradePlanner {
  UpgradePlanner(
    this.village,
    this.catalogue, {
    this.builderDiscount = 0,
    this.researchDiscount = 0,
  });
  final Village village;
  final Catalogue catalogue;
  final int builderDiscount;
  final int researchDiscount;

  int building(String slug) {
    final id = catalogue.entries.entries
        .where((e) => e.value['slug'] == slug)
        .firstOrNull
        ?.key;
    if (id == null) return 0;
    return village.items
        .where((e) => e.data == int.parse(id))
        .fold(0, (n, e) => e.level > n ? e.level : n);
  }

  int allowed(int data) {
    final rows = (catalogue.entry(data)?['counts'] ?? []) as List;
    final matches =
        rows
            .where((e) => (e['townHallLevel'] as num) <= village.townHall)
            .toList()
          ..sort(
            (a, b) => (a['townHallLevel'] as num).compareTo(
              b['townHallLevel'] as num,
            ),
          );
    if (matches.isEmpty) return 0;
    var count = (matches.last['count'] as num).toInt();
    // Existing merged structures consume their original defenses; don't invent replacements.
    final mergedCannon = village.items
        .where((e) => catalogue.entry(e.data)?['slug'] == 'ricochet-cannon')
        .length;
    final mergedArcher = village.items
        .where((e) => catalogue.entry(e.data)?['slug'] == 'multi-archer-tower')
        .length;
    final gear = village.items
        .where((e) => catalogue.entry(e.data)?['slug'] == 'multi-gear-tower')
        .length;
    final slug = catalogue.entry(data)?['slug'];
    if (slug == 'cannon') count -= mergedCannon * 2 + gear;
    if (slug == 'archer-tower') count -= mergedArcher * 2 + gear;
    return count.clamp(0, 1000);
  }

  List<VillageItem> get inventory {
    final result = [...village.items];
    for (final entry in catalogue.entries.entries) {
      final data = int.parse(entry.key);
      final actual = village.items.where((e) => e.data == data).length;
      final total = allowed(data);
      for (var n = actual; n < total; n++) {
        result.add(
          VillageItem(
            key: 'new:$data:$n',
            data: data,
            section: entry.value['category'] == 'trap' ? 'traps' : 'buildings',
            level: 0,
            extra: {},
          ),
        );
      }
    }
    return result;
  }

  String? blocked(VillageItem item, Map<String, dynamic>? next) {
    if (next == null) {
      final levels = catalogue.levels(item.data);
      if (levels.isEmpty) return 'Level data unavailable';
      final highest = levels
          .map((e) => e['level'] as int)
          .reduce((a, b) => a > b ? a : b);
      return item.level > highest
          ? 'Recorded level above catalogue'
          : 'At catalogue maximum';
    }
    if ((next['townHall'] as num? ?? 999) == 999) {
      return 'Requirement not mapped';
    }
    if ((next['townHall'] as num) > village.townHall) {
      final cap = catalogue.maxLevel(item, village.townHall);
      if (item.level > 0 && cap != null && item.level >= cap) {
        return 'At Town Hall ${village.townHall} cap';
      }
      return 'Requires Town Hall ${next['townHall']}';
    }
    final requirements = Map<String, dynamic>.from(next['requirements'] ?? {});
    const buildings = {
      'laboratoryRequired': 'laboratory',
      'heroHallLevelRequired': 'hero-hall',
      'blacksmithLevelRequired': 'blacksmith',
      'petHouseLevelRequired': 'pet-house',
    };
    for (final rule in buildings.entries) {
      final required = (requirements[rule.key] as num?)?.toInt() ?? 0;
      if (building(rule.value) < required) {
        return 'Requires ${rule.value.replaceAll('-', ' ')} level $required';
      }
    }
    final entry = catalogue.entry(item.data);
    final unlock = Map<String, dynamic>.from(entry?['unlock'] ?? {});
    if (unlock['barrackLevelRequired'] is num) {
      final slug = unlock['troopType'] == 'dark' ? 'dark-barracks' : 'barracks';
      if (building(slug) < unlock['barrackLevelRequired']) {
        return 'Requires $slug level ${unlock['barrackLevelRequired']}';
      }
    }
    if (unlock['spellFactoryLevelRequired'] is num) {
      final slug = unlock['spellType'] == 'dark'
          ? 'dark-spell-factory'
          : 'spell-factory';
      if (building(slug) < unlock['spellFactoryLevelRequired']) {
        return 'Requires $slug level ${unlock['spellFactoryLevelRequired']}';
      }
    }
    if (item.level == 0 &&
        [
          'ricochet-cannon',
          'multi-archer-tower',
          'multi-gear-tower',
        ].contains(entry?['slug']) &&
        mergeInputs(item).isEmpty) {
      return 'Merged defense requires completed maximum-level source defenses';
    }
    if (item.level == 0 && entry?['slug'] == 'inferno-artillery') {
      return 'Town Hall weapon merge: import after starting in-game';
    }
    if (item.level == 0 && entry?['category'] == 'crafted-defense') {
      return 'Craft in-game, then import a fresh snapshot';
    }
    if (next['seconds'] == null) {
      return 'Duration not mapped; import after starting in-game';
    }
    for (final cost in costs(item, next).entries) {
      final capacity = storageCapacity(cost.key);
      if (capacity != null && cost.value > capacity) {
        return 'Requires more ${cost.key} storage capacity';
      }
    }
    return null;
  }

  List<VillageItem> mergeInputs(VillageItem item) {
    final slug = catalogue.entry(item.data)?['slug'];
    if (item.level != 0 ||
        ![
          'ricochet-cannon',
          'multi-archer-tower',
          'multi-gear-tower',
        ].contains(slug)) {
      return [];
    }
    List<VillageItem> candidates(String source, bool geared) {
      final row = catalogue.entries.entries
          .where((e) => e.value['slug'] == source)
          .firstOrNull;
      if (row == null) return [];
      final data = int.parse(row.key);
      final template = VillageItem(
        key: '',
        data: data,
        section: 'buildings',
        level: 0,
      );
      final maximum = catalogue.maxLevel(template, 15);
      if (maximum == null) return [];
      return village.items
          .where(
            (e) =>
                e.data == data &&
                e.level >= maximum &&
                !e.upgrading &&
                (e.extra['gear_up'] == 1) == geared,
          )
          .toList();
    }

    if (slug == 'multi-gear-tower') {
      final cannon = candidates('cannon', true);
      final archer = candidates('archer-tower', true);
      return cannon.isNotEmpty && archer.isNotEmpty
          ? [cannon.first, archer.first]
          : [];
    }
    final pool = candidates(
      slug == 'ricochet-cannon' ? 'cannon' : 'archer-tower',
      false,
    );
    return pool.length >= 2 ? pool.take(2).toList() : [];
  }

  num? storageCapacity(String resource) {
    if (resource == 'Gold or Elixir') {
      final gold = storageCapacity('Gold');
      final elixir = storageCapacity('Elixir');
      if (gold == null && elixir == null) return null;
      return (gold ?? 0) > (elixir ?? 0) ? gold : elixir;
    }
    final slug = switch (resource) {
      'Gold' => 'gold-storage',
      'Elixir' => 'elixir-storage',
      'Dark Elixir' => 'dark-elixir-storage',
      _ => null,
    };
    if (slug == null) return null;
    num capacity = 0;
    var known = false;
    for (final item in village.items) {
      final name = catalogue.entry(item.data)?['slug'];
      if (name != slug && name != 'town-hall') continue;
      final level = catalogue
          .levels(item.data)
          .where((e) => e['level'] == item.level)
          .firstOrNull;
      final stats = level?['stats'];
      if (name == slug && stats?['capacity'] is num) {
        capacity += stats['capacity'] as num;
        known = true;
      }
      if (name == 'town-hall') {
        final key = switch (resource) {
          'Gold' => 'gold',
          'Elixir' => 'elixir',
          _ => 'darkElixir',
        };
        final value = stats?['storageCapacity']?[key];
        if (value is num) {
          capacity += value;
          known = true;
        }
      }
    }
    return known ? capacity : null;
  }

  UpgradeChoice choice(VillageItem item) {
    var level = catalogue
        .levels(item.data)
        .where((e) => e['level'] == (item.targetLevel ?? item.level + 1))
        .firstOrNull;
    if (item.level == 0 && item.key.startsWith('new:') && level != null) {
      final slot = (int.tryParse(item.key.split(':').last) ?? 0) + 1;
      final placements =
          (catalogue.entry(item.data)?['placementCosts'] ?? []) as List;
      final price = placements.where((e) => e['instance'] == slot).firstOrNull;
      if (price != null) {
        level = {
          ...level,
          'cost': price['cost'],
          'resource': price['costResource'],
        };
      }
    }
    return UpgradeChoice(
      item,
      level,
      blocked(item, level),
      missing: item.level == 0,
    );
  }

  List<UpgradeChoice> get choices => inventory.map(choice).toList();
  int discount(VillageItem item) =>
      ['units', 'spells', 'siege_machines', 'pets'].contains(item.section)
      ? researchDiscount
      : item.section == 'equipment'
      ? 0
      : builderDiscount;
  int duration(VillageItem item, Map<String, dynamic> level) =>
      (((level['seconds'] as num? ?? 0) * (100 - discount(item))) / 100).ceil();
  Map<String, num> costs(VillageItem item, Map<String, dynamic> level) {
    final ores = Map<String, dynamic>.from(level['ores'] ?? {});
    if (ores.isNotEmpty) return ores.map((k, v) => MapEntry(k, v as num));
    if (level['cost'] is! num || level['resource'] is! String) return {};
    return {
      level['resource']:
          ((level['cost'] as num) *
                  (level['resource'] == 'Gems' ? 100 : 100 - discount(item)) /
                  100)
              .ceil(),
    };
  }

  Map<String, num> remainingCosts(Iterable<UpgradeChoice> choices) {
    final totals = <String, num>{};
    for (final option in choices) {
      final item = option.item;
      final cap = catalogue.maxLevel(item, village.townHall);
      if (cap == null) continue;
      for (final level
          in catalogue
              .levels(item.data)
              .where(
                (e) =>
                    e['level'] > (item.targetLevel ?? item.level) &&
                    e['level'] <= cap,
              )) {
        final priced = item.level == 0 && level['level'] == 1
            ? (option.level ?? level)
            : level;
        for (final cost in costs(item, priced).entries) {
          totals.update(
            cost.key,
            (n) => n + cost.value,
            ifAbsent: () => cost.value,
          );
        }
      }
    }
    return totals;
  }

  int priority(VillageItem item) {
    final slug = catalogue.entry(item.data)?['slug'];
    if ([
      'laboratory',
      'army-camp',
      'clan-castle',
      'barracks',
      'dark-barracks',
      'spell-factory',
      'hero-hall',
      'blacksmith',
      'pet-house',
    ].contains(slug)) {
      return 0;
    }
    if ([
      'heroes',
      'units',
      'spells',
      'siege_machines',
      'pets',
      'equipment',
    ].contains(item.section)) {
      return 1;
    }
    if (catalogue.entry(item.data)?['category'] == 'resource') return 2;
    if (catalogue.entry(item.data)?['category'] == 'wall') return 4;
    return 3;
  }
}

String liveCountdown(Duration d) {
  if (d.inSeconds <= 0) return 'Ready to confirm';
  final h = (d.inHours % 24).toString().padLeft(2, '0');
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '${d.inDays > 0 ? '${d.inDays}d ' : ''}$h:$m:$s';
}
