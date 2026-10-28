import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'services/game_updates.dart';
import 'services/tracker_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final prefs = await SharedPreferences.getInstance();
    final store = TrackerStore(prefs)..load();
    final bundled = await rootBundle.loadString('assets/catalogue/home.json');
    var catalogue = decodeCatalogue(bundled);
    try {
      final cached = prefs.getString('catalogue.v2');
      if (cached != null) catalogue = decodeCatalogue(cached);
    } catch (_) {
      /* Retain bundled catalogue when a cached update is unreadable. */
    }
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks([
        'clash-of-clans-data',
      ], await rootBundle.loadString('assets/catalogue/UPSTREAM_LICENSE.txt'));
    });
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks([
        'Space Grotesk',
      ], await rootBundle.loadString('assets/fonts/SpaceGrotesk-OFL.txt'));
    });
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks([
        'Plus Jakarta Sans',
      ], await rootBundle.loadString('assets/fonts/PlusJakartaSans-OFL.txt'));
    });
    runApp(TrackerApp(store: store, catalogue: catalogue));
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'COCTracker could not open local storage. Restart the app and check available device space. Existing data has not been erased.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
