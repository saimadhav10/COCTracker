import 'village.dart';

class ArmyPlan {
  const ArmyPlan(this.title, this.type, this.roster, this.steps);
  final String title;
  final String type;
  final Map<int, int> roster;
  final List<String> steps;
}

int campCapacity(Village village, Catalogue catalogue) {
  var total = 0;
  for (final item in village.items) {
    if (catalogue.entry(item.data)?['slug'] != 'army-camp') continue;
    final level = catalogue
        .levels(item.data)
        .where((e) => e['level'] == item.level)
        .firstOrNull;
    total += (level?['stats']?['housingSpace'] as num? ?? 0).toInt();
  }
  return total;
}

List<ArmyPlan> armyPlans(Village village, Catalogue catalogue) {
  final capacity = campCapacity(village, catalogue);
  if (capacity <= 0) return [];
  final owned = <String, VillageItem>{};
  for (final i in village.items.where(
    (e) => e.section == 'units' && e.level > 0,
  )) {
    final slug = catalogue.entry(i.data)?['slug'];
    if (slug is String) owned[slug] = i;
  }
  Map<int, int> roster(List<(String, double)> ratios) {
    final result = <int, int>{};
    var spent = 0;
    for (final part in ratios) {
      final item = owned[part.$1];
      if (item == null) continue;
      final housing = catalogue.entry(item.data)?['housing'] as num?;
      if (housing == null || housing <= 0) continue;
      final count = ((capacity * part.$2) ~/ housing).clamp(
        0,
        (capacity - spent) ~/ housing,
      );
      if (count > 0) {
        result[item.data] = count;
        spent += (count * housing).toInt();
      }
    }
    final cleanup = owned['archer'] ?? owned['barbarian'];
    final housing = cleanup == null
        ? null
        : catalogue.entry(cleanup.data)?['housing'] as num?;
    if (cleanup != null && housing != null && housing > 0) {
      final count = (capacity - spent) ~/ housing;
      if (count > 0) {
        result.update(cleanup.data, (n) => n + count, ifAbsent: () => count);
      }
    }
    return result;
  }

  return [
    if (owned.containsKey('dragon'))
      ArmyPlan(
        'Dragon air push',
        'Air',
        roster([('dragon', .75), ('balloon', .20)]),
        [
          'Scout Air Defenses, Air Sweepers and the route into the Town Hall. Pick an entry where your air army can stay together.',
          'Clear the edges before committing the main group. Use Balloons behind the tanking Dragons rather than ahead of all support.',
          'Plan spell coverage around the actual defending base. Practise the entry and reserve cleanup troops for exposed outside buildings.',
        ],
      ),
    if (owned.containsKey('giant'))
      ArmyPlan(
        'Giant-supported ground push',
        'Ground',
        roster([('giant', .35), ('wizard', .4), ('wall-breaker', .08)]),
        [
          'Inspect the nearest defenses and walls. Create a narrow entry so the army does not split around the outside.',
          'Use Giants to absorb defensive fire, then send damage troops behind them. Time Wall Breakers for the wall segment you want opened.',
          'Deploy support and spells where the troops actually path. Save cleanup troops and watch the battle clock.',
        ],
      ),
    if (owned.containsKey('goblin'))
      ArmyPlan(
        'Resource-focused farming',
        'Farming',
        roster([('giant', .25), ('goblin', .50)]),
        [
          'Choose a target with reachable collectors or storages. Evaluate the loot and defensive coverage before committing.',
          'Use tanking troops only where needed, then deploy Goblins toward accessible resources. Work from the exposed side of the base.',
          'Spend loot toward the next eligible upgrade. Re-import after starting it so the tracker follows the game.',
        ],
      ),
    ArmyPlan(
      'Build a dependable attack routine',
      'Practice',
      roster([('barbarian', .45), ('archer', .45)]),
      [
        'Scout before deploying: identify defensive coverage, open routes and isolated buildings.',
        'Practise funneling and troop timing in a friendly challenge before taking an unfamiliar army into war.',
        'Review your replay, identify where the army split or lost support, and adjust the next attempt.',
      ],
    ),
  ].where((p) => p.roster.isNotEmpty).toList();
}

int spellCapacity(Village village, Catalogue catalogue) {
  var result = 0;
  for (final item in village.items) {
    if (![
      'spell-factory',
      'dark-spell-factory',
    ].contains(catalogue.entry(item.data)?['slug'])) {
      continue;
    }
    final level = catalogue
        .levels(item.data)
        .where((e) => e['level'] == item.level)
        .firstOrNull;
    result += (level?['stats']?['spellStorageCapacity'] as num? ?? 0).toInt();
  }
  return result;
}
