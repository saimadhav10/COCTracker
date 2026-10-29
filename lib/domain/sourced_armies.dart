import 'dart:convert';
import 'package:flutter/services.dart';

String normaliseArmyName(String name) => name
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9]'), '')
    .replaceFirst(RegExp(r'spell$'), '');

class SourcedArmy {
  SourcedArmy.fromRow(List<dynamic> row, {this.artwork = const {}})
    : townHall = row[0] as int,
      type = row[1] as String,
      source = 'https://clasharmies.com/armies/${row[2]}',
      title = row[3] as String,
      troops = Map<String, int>.from(row[4]),
      spells = Map<String, int>.from(row[5]),
      heroes = List<String>.from(row[6]);
  final int townHall;
  final String type, source, title;
  final Map<String, int> troops, spells;
  final List<String> heroes;
  final Map<String, String> artwork;
  String get clipboardText =>
      '$title · TH$townHall · $type\n${[...troops.entries, ...spells.entries].map((e) => '${e.value} × ${e.key}').join('\n')}\n${heroes.join(', ')}\n$source';
}

Future<List<SourcedArmy>> loadSourcedArmies() async {
  final images =
      jsonDecode(
            await rootBundle.loadString('assets/catalogue/army_units.json'),
          )
          as Map<String, dynamic>;
  final artwork = <String, String>{
    for (final e in images.entries)
      if (e.value['image'] is String)
        normaliseArmyName(e.key): e.value['image'] as String,
  };
  final json =
      jsonDecode(await rootBundle.loadString('assets/catalogue/armies.json'))
          as Map<String, dynamic>;
  return (json['armies'] as List)
      .map(
        (row) => SourcedArmy.fromRow(List<dynamic>.from(row), artwork: artwork),
      )
      .toList();
}
