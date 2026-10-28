import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/village.dart';

class TrackerStore extends ChangeNotifier {
  TrackerStore(this.prefs);
  final SharedPreferences prefs;
  static const channel = MethodChannel('coc_tracker/device');
  List<Village> villages = [];
  String? selectedTag;
  String theme = 'system';
  bool reminders = false;
  int quietStart = 22;
  int quietEnd = 8;
  String? platformError;
  String? recoveryData;
  Village? get selected =>
      villages.where((e) => e.tag == selectedTag).firstOrNull ??
      villages.firstOrNull;

  void load() {
    final raw = prefs.getString('tracker.v1');
    if (raw == null) return;
    try {
      _apply(decodeBackup(raw));
    } catch (_) {
      recoveryData = raw;
    }
  }

  static Map<String, dynamic> decodeBackup(String text) {
    if (text.length > 10000000) {
      throw const FormatException('Backup is too large.');
    }
    final j = jsonDecode(text);
    if (j is! Map<String, dynamic> ||
        j['schema'] != 1 ||
        j['villages'] is! List) {
      throw const FormatException(
        'This is not a COCTracker backup. Use Import village for game JSON.',
      );
    }
    final villages = (j['villages'] as List)
        .map((e) => Village.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    if (villages.length > 50 ||
        villages.map((e) => e.tag).toSet().length != villages.length ||
        villages.any(
          (v) =>
              v.items.length > 10000 ||
              !RegExp(r'^#[0289PYLQGRJCUV]{3,15}$').hasMatch(v.tag) ||
              v.items.map((e) => e.key).toSet().length != v.items.length ||
              v.items.any(
                (e) =>
                    e.level < 0 ||
                    e.level > 1000 ||
                    e.data <= 0 ||
                    !homeSections.contains(e.section) ||
                    (e.targetLevel != null && e.targetLevel != e.level + 1),
              ),
        )) {
      throw const FormatException(
        'Backup contains invalid profiles or upgrade entries.',
      );
    }
    if (!['system', 'light', 'dark'].contains(j['theme'] ?? 'system')) {
      throw const FormatException('Invalid theme.');
    }
    for (final key in ['quietStart', 'quietEnd']) {
      final value = j[key] ?? (key == 'quietStart' ? 22 : 8);
      if (value is! int || value < 0 || value > 23) {
        throw const FormatException('Invalid quiet hours.');
      }
    }
    return Map<String, dynamic>.from(j);
  }

  void _apply(Map<String, dynamic> j) {
    villages = (j['villages'] as List)
        .map((e) => Village.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    selectedTag = j['selectedTag'] as String?;
    theme = j['theme'] ?? 'system';
    reminders = j['reminders'] == true;
    quietStart = j['quietStart'] ?? 22;
    quietEnd = j['quietEnd'] ?? 8;
  }

  String backup() => jsonEncode({
    'schema': 1,
    'villages': villages.map((e) => e.toJson()).toList(),
    'selectedTag': selectedTag,
    'theme': theme,
    'reminders': reminders,
    'quietStart': quietStart,
    'quietEnd': quietEnd,
  });

  Future<void> save() async {
    if (recoveryData != null) {
      throw StateError(
        'Restore a valid backup before saving. Your original data has been retained.',
      );
    }
    if (!await prefs.setString('tracker.v1', backup())) {
      throw StateError('Could not save to this device.');
    }
    notifyListeners();
    await syncReminders();
  }

  Future<void> add(Village village) async {
    if (!villages.any((e) => e.tag == village.tag) && villages.length >= 50) {
      throw StateError('A maximum of 50 profiles is supported.');
    }
    villages.removeWhere((e) => e.tag == village.tag);
    villages.add(village);
    selectedTag = village.tag;
    await save();
  }

  Future<void> restore(String text) async {
    final j = decodeBackup(text);
    // Write before replacing in-memory data so failed storage cannot erase it.
    if (!await prefs.setString('tracker.v1', jsonEncode(j))) {
      throw StateError('Could not save backup.');
    }
    _apply(j);
    recoveryData = null;
    notifyListeners();
    await syncReminders();
  }

  Future<void> syncReminders() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await channel.invokeMethod('configure', {
        'enabled': reminders,
        'quietStart': quietStart,
        'quietEnd': quietEnd,
        'upgrades': [
          for (final v in villages)
            for (final item in v.active)
              {
                'id':
                    '${v.tag}:${item.key}:${item.finishesAt!.millisecondsSinceEpoch}',
                'at': item.finishesAt!.millisecondsSinceEpoch,
                'village': v.name,
                'profile': v.tag,
              },
        ],
      });
      platformError = null;
    } on PlatformException catch (e) {
      platformError = e.message;
    }
  }

  Future<Map<String, dynamic>> deviceStatus() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return {'supported': false};
    }
    return Map<String, dynamic>.from(
      await channel.invokeMethod('status') as Map,
    );
  }

  Future<void> deviceAction(String action) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await channel.invokeMethod(action);
  }
}
