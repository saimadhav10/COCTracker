import 'dart:convert';

const homeSections = [
  'buildings',
  'traps',
  'units',
  'siege_machines',
  'heroes',
  'spells',
  'pets',
  'equipment',
];

class VillageItem {
  VillageItem({
    required this.key,
    required this.data,
    required this.section,
    required this.level,
    this.finishesAt,
    this.targetLevel,
    this.extra = const {},
  });
  final String key;
  final int data;
  final String section;
  int level;
  DateTime? finishesAt;
  int? targetLevel;
  final Map<String, dynamic> extra;
  bool get upgrading => finishesAt != null;
  bool ready(DateTime now) => finishesAt != null && !finishesAt!.isAfter(now);
  Map<String, dynamic> toJson() => {
    'key': key,
    'data': data,
    'section': section,
    'level': level,
    'finishesAt': finishesAt?.toUtc().toIso8601String(),
    'targetLevel': targetLevel,
    'extra': extra,
  };
  factory VillageItem.fromJson(Map<String, dynamic> j) => VillageItem(
    key: j['key'] as String,
    data: j['data'] as int,
    section: j['section'] as String,
    level: j['level'] as int,
    finishesAt: DateTime.tryParse(j['finishesAt'] ?? ''),
    targetLevel: j['targetLevel'] as int?,
    extra: Map<String, dynamic>.from(j['extra'] ?? {}),
  );
}

class Village {
  Village({
    required this.tag,
    required this.name,
    required this.exportedAt,
    required this.importedAt,
    required this.items,
  });
  final String tag;
  String name;
  final DateTime exportedAt;
  final DateTime importedAt;
  final List<VillageItem> items;
  int get townHall =>
      items.where((e) => e.data == 1000001).firstOrNull?.level ?? 1;
  List<VillageItem> get active =>
      items.where((e) => e.upgrading).toList()
        ..sort((a, b) => a.finishesAt!.compareTo(b.finishesAt!));
  bool needsRefresh(DateTime now) =>
      now.difference(exportedAt).inHours >= 24 ||
      active.any((e) => e.ready(now));
  Map<String, dynamic> toJson() => {
    'tag': tag,
    'name': name,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'importedAt': importedAt.toUtc().toIso8601String(),
    'items': items.map((e) => e.toJson()).toList(),
  };
  factory Village.fromJson(Map<String, dynamic> j) => Village(
    tag: j['tag'] as String,
    name: j['name'] as String,
    exportedAt: DateTime.parse(j['exportedAt']),
    importedAt: DateTime.parse(j['importedAt']),
    items: (j['items'] as List)
        .map((e) => VillageItem.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
  );
}

int _integer(dynamic value, String label, {int min = 0, int max = 2147483647}) {
  if (value is! int || value < min || value > max) {
    throw FormatException(
      '$label must be a whole number between $min and $max.',
    );
  }
  return value;
}

Village parseVillage(String text, {String? name, DateTime? now}) {
  if (text.length > 2000000) {
    throw const FormatException('Export is too large (maximum 2 MB).');
  }
  final dynamic decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const FormatException(
      'Paste the complete JSON copied from Clash of Clans settings.',
    );
  }
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Expected a village JSON object.');
  }
  final tag = decoded['tag'];
  if (tag is! String ||
      !RegExp(r'^#[0289PYLQGRJCUV]{3,15}$').hasMatch(tag.toUpperCase())) {
    throw const FormatException('The export needs a valid player tag.');
  }
  final clock = (now ?? DateTime.now()).toUtc();
  final timestamp = _integer(
    decoded['timestamp'],
    'Export timestamp',
    min: 1,
    max: 4102444800,
  );
  final exportedAt = DateTime.fromMillisecondsSinceEpoch(
    timestamp * 1000,
    isUtc: true,
  );
  if (exportedAt.isAfter(clock.add(const Duration(minutes: 10)))) {
    throw const FormatException(
      'Export timestamp is in the future. Check your device clock.',
    );
  }
  if (decoded['buildings'] is! List) {
    throw const FormatException('Home Village buildings are missing.');
  }
  final items = <VillageItem>[];
  final ordinals = <String, int>{};
  for (final section in homeSections) {
    final rows = decoded[section] ?? [];
    if (rows is! List) throw FormatException('$section must be a list.');
    for (final row in rows) {
      if (row is! Map<String, dynamic>) {
        throw FormatException('Invalid entry in $section.');
      }
      final data = _integer(row['data'], 'Data ID', min: 1);
      final level = _integer(row['lvl'] ?? 0, 'Level', max: 1000);
      final count = _integer(row['cnt'] ?? 1, 'Count', min: 1, max: 1000);
      final timer = row['timer'] == null
          ? null
          : _integer(row['timer'], 'Timer', max: 31536000);
      if (items.length + count > 10000) {
        throw const FormatException('Too many village entries.');
      }
      for (var n = 0; n < count; n++) {
        final group = '$section:$data';
        final index = ordinals.update(group, (v) => v + 1, ifAbsent: () => 0);
        items.add(
          VillageItem(
            key: '$group:$index',
            data: data,
            section: section,
            level: level,
            finishesAt: timer == null
                ? null
                : exportedAt.add(Duration(seconds: timer)),
            targetLevel: timer == null ? null : level + 1,
            extra: Map<String, dynamic>.from(row),
          ),
        );
      }
    }
  }
  if (!items.any((e) => e.data == 1000001 && e.level > 0)) {
    throw const FormatException('A Home Village Town Hall could not be found.');
  }
  return Village(
    tag: tag.toUpperCase(),
    name: name?.trim().isNotEmpty == true ? name!.trim() : 'My village',
    exportedAt: exportedAt,
    importedAt: clock,
    items: items,
  );
}

String durationLabel(Duration value) {
  if (value.isNegative || value.inSeconds == 0) return 'Ready to confirm';
  if (value.inDays > 0) return '${value.inDays}d ${value.inHours % 24}h';
  if (value.inHours > 0) return '${value.inHours}h ${value.inMinutes % 60}m';
  return '${value.inMinutes + 1}m';
}

class Catalogue {
  Catalogue(this.entries, this.updatedAt);
  final Map<String, dynamic> entries;
  final String updatedAt;
  Map<String, dynamic>? entry(int data) =>
      entries['$data'] as Map<String, dynamic>?;
  String name(VillageItem item) =>
      entry(item.data)?['name'] ?? 'Unmapped item ${item.data}';
  String? image(VillageItem item) => entry(item.data)?['image'] as String?;
  List<Map<String, dynamic>> levels(int data) =>
      ((entry(data)?['levels'] ?? []) as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
  Map<String, dynamic>? next(VillageItem item) =>
      levels(item.data).where((e) => e['level'] == item.level + 1).firstOrNull;
  int? maxLevel(VillageItem item, int th) {
    final eligible = levels(
      item.data,
    ).where((e) => (e['townHall'] as num? ?? 999) <= th);
    if (eligible.isEmpty) return null;
    return eligible
        .map((e) => e['level'] as int)
        .reduce((a, b) => a > b ? a : b);
  }
}
