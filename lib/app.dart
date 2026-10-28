import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'domain/village.dart';
import 'services/game_updates.dart';
import 'services/tracker_store.dart';

const forest = Color(0xff247258);
const gold = Color(0xffdbac43);
const violet = Color(0xff8261b5);

// Wait for the closing transition before disposing text controllers used by a route.
Future<T?> managedDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  final route = DialogRoute<T>(context: context, builder: builder);
  final result = await Navigator.of(
    context,
    rootNavigator: true,
  ).push<T>(route);
  await route.completed;
  return result;
}

ThemeData trackerTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: forest,
    brightness: brightness,
    surface: dark ? const Color(0xff17201d) : const Color(0xfffffdf7),
  );
  return ThemeData(
    fontFamily: 'Manrope',
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark
        ? const Color(0xff101713)
        : const Color(0xfff3f4ed),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: dark ? forest : const Color(0xffd5eadc),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}

class TrackerApp extends StatefulWidget {
  const TrackerApp({super.key, required this.store, required this.catalogue});
  final TrackerStore store;
  final Catalogue catalogue;
  @override
  State<TrackerApp> createState() => _TrackerAppState();
}

class _TrackerAppState extends State<TrackerApp> with WidgetsBindingObserver {
  late Catalogue catalogue = widget.catalogue;
  int page = 0;
  Timer? ticker;
  String query = '';
  String category = 'All';
  bool library = false;
  bool refreshing = false;
  bool importing = false;
  Future<List<NewsArticle>>? news;
  TrackerStore get store => widget.store;
  bool get onAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  DateTime get now => DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    store.addListener(redraw);
    ticker = Timer.periodic(const Duration(minutes: 1), (_) => redraw());
    unawaited(store.syncReminders());
  }

  @override
  void dispose() {
    ticker?.cancel();
    store.removeListener(redraw);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) redraw();
  }

  void redraw() {
    if (mounted) setState(() {});
  }

  void message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(ui).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> act(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (e) {
      message(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> open(String url) async {
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      throw Exception('Could not open this link.');
    }
  }

  Future<bool> confirm(String title, String body) async =>
      await managedDialog<bool>(
        context: ui,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => MaterialApp(
      title: 'COCTracker',
      debugShowCheckedModeBanner: false,
      theme: trackerTheme(Brightness.light),
      darkTheme: trackerTheme(Brightness.dark),
      themeMode: switch (store.theme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      home: Builder(builder: (context) => _home(context)),
    ),
  );

  Widget _home(BuildContext context) {
    // Use a context below MaterialApp for dialogs and snackbars.
    return _ContextHost(
      onContext: (c) => actionContext = c,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: forest,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.fort_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'COCTracker',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Village profiles',
              onPressed: profiles,
              icon: const Icon(Icons.switch_account_rounded),
            ),
            const SizedBox(width: 10),
          ],
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: store.recoveryData != null
                  ? recovery()
                  : switch (page) {
                      0 => dashboard(context),
                      1 => upgrades(context),
                      2 => newsPage(context),
                      _ => settings(context),
                    },
            ),
          ),
        ),
        floatingActionButton: page < 2 && store.recoveryData == null
            ? FloatingActionButton.extended(
                onPressed: importing ? null : importVillage,
                icon: const Icon(Icons.content_paste_go_rounded),
                label: const Text('Import village'),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: page,
          onDestinationSelected: (value) => setState(() {
            page = value;
          }),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.grid_view_rounded),
              label: 'Village',
            ),
            NavigationDestination(
              icon: Icon(Icons.construction_rounded),
              label: 'Upgrades',
            ),
            NavigationDestination(
              icon: Icon(Icons.newspaper_rounded),
              label: 'News',
            ),
            NavigationDestination(
              icon: Icon(Icons.tune_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }

  BuildContext? actionContext;
  BuildContext get ui => actionContext ?? context;

  Widget heading(String eyebrow, String title, [String? subtitle]) => Builder(
    builder: (context) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            title,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget dashboard(BuildContext context) {
    final v = store.selected;
    if (v == null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          heading(
            'Your village, in focus',
            'A little order.\nA stronger village.',
            'Keep every upgrade and every account in one place.',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  Image.asset(
                    'assets/icons/1000001.png',
                    height: 160,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.fort, size: 120, color: forest),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Your journey starts here',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'In Clash of Clans, open Settings → More Settings → Export Data. Copy the JSON and paste it here.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: importVillage,
                    icon: const Icon(Icons.add),
                    label: const Text('Import your first village'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No login. No ads. Stored on your device.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'You stay in control',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Import fresh snapshots whenever things change, or record upgrades manually. Add more villages at any time.',
          ),
          const SizedBox(height: 90),
        ],
      );
    }
    final active = v.active;
    final ready = active.where((e) => e.ready(now)).length;
    final known = v.items
        .where((e) => catalogue.maxLevel(e, v.townHall) != null)
        .toList();
    final maxed = known
        .where((e) => e.level >= catalogue.maxLevel(e, v.townHall)!)
        .length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      children: [
        heading('Welcome back, chief', 'Your village. At a glance.'),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: forest,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'HOME VILLAGE',
                      style: TextStyle(
                        color: Color(0xffc8e5cf),
                        letterSpacing: 2,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      v.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                      ),
                    ),
                    Text(
                      '${v.tag}  ·  Town Hall ${v.townHall}',
                      style: const TextStyle(color: Color(0xffd9ebdf)),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: profiles,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 28),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        side: const BorderSide(color: Color(0xff81ab91)),
                      ),
                      child: Text(
                        '${store.villages.length} village${store.villages.length == 1 ? '' : 's'} · Switch',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 105,
                child: itemImage(
                  VillageItem(
                    key: '',
                    data: 1000001,
                    section: 'buildings',
                    level: v.townHall,
                  ),
                  size: 112,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: stat(
                'IN PROGRESS',
                '${active.length}',
                Icons.construction,
                forest,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: stat('TO CONFIRM', '$ready', Icons.task_alt, violet),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.eco_rounded, color: forest),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Town Hall ${v.townHall} progress',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '$maxed / ${known.length}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LinearProgressIndicator(
                    value: known.isEmpty ? 0 : maxed / known.length,
                    minHeight: 9,
                    color: forest,
                    backgroundColor: forest.withValues(alpha: .12),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Imported items at their known TH level cap. Not a time or cost estimate.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        refreshNotice(v),
        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(
              child: Text(
                'On the builders’ bench',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => page = 1),
              child: const Text('View all'),
            ),
          ],
        ),
        if (active.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: forest,
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'No upgrades recorded',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Text(
                    'Start one from Upgrades, or import a fresh snapshot.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        for (final item in active.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: itemTile(item),
          ),
        const SizedBox(height: 18),
        if (onAndroid)
          OutlinedButton.icon(
            onPressed: () => act(() => store.deviceAction('openClash')),
            icon: const Icon(Icons.sports_esports),
            label: const Text('Open Clash of Clans'),
          ),
      ],
    );
  }

  Widget stat(String label, String value, IconData icon, Color color) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 23),
              const SizedBox(width: 12),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );

  Widget refreshNotice(Village v) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: gold.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.sync_rounded, color: Color(0xffad7c1e)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                v.needsRefresh(now)
                    ? 'Time for a fresh snapshot'
                    : 'Your snapshot is saved',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                'Exported ${dateLabel(v.exportedAt)}. Timers are estimates; boosts and in-game changes need a new import.',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget itemImage(VillageItem item, {double size = 52}) {
    final path = item.data == 1000001 && item.level >= 1 && item.level <= 18
        ? 'assets/icons/townhall_${item.level}.png'
        : catalogue.image(item);
    return SizedBox(
      width: size,
      height: size,
      child: path == null
          ? Icon(sectionIcon(item.section), color: forest, size: size * .6)
          : Image.asset(
              path,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Icon(
                sectionIcon(item.section),
                color: forest,
                size: size * .6,
              ),
            ),
    );
  }

  IconData sectionIcon(String section) => switch (section) {
    'heroes' => Icons.shield_rounded,
    'equipment' => Icons.auto_fix_high,
    'pets' => Icons.pets,
    'spells' => Icons.science,
    'units' || 'siege_machines' => Icons.groups,
    _ => Icons.fort_rounded,
  };

  Widget itemTile(VillageItem item, {int count = 1, bool reference = false}) {
    final next = catalogue.next(item);
    final subtitle = item.upgrading
        ? 'Level ${item.level} → ${item.targetLevel} · ${durationLabel(item.finishesAt!.difference(now))}'
        : 'Level ${item.level}${count > 1 ? ' · $count items' : ''}${next == null ? '' : ' · Next: ${costLabel(next)}'}';
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: itemImage(item),
        title: Text(
          catalogue.name(item),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: item.ready(now) ? violet : null,
          ),
        ),
        trailing: Icon(
          item.ready(now) ? Icons.check_circle : Icons.chevron_right,
          color: item.ready(now) ? violet : null,
        ),
        onTap: () => details(item, reference: reference),
      ),
    );
  }

  Widget upgrades(BuildContext context) {
    final v = store.selected;
    var items = v?.items ?? <VillageItem>[];
    if (library) {
      items = catalogue.entries.entries
          .map(
            (e) => VillageItem(
              key: 'library:${e.key}',
              data: int.parse(e.key),
              section: sectionFor(e.value['category'] as String?),
              level: 0,
            ),
          )
          .toList();
    }
    items = items
        .where(
          (e) =>
              (category == 'All' || groupFor(e.section) == category) &&
              catalogue.name(e).toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    items.sort((a, b) {
      if (a.upgrading != b.upgrading) return a.upgrading ? -1 : 1;
      return catalogue.name(a).compareTo(catalogue.name(b));
    });
    final grouped = <String, List<VillageItem>>{};
    for (final item in items) {
      final key = item.upgrading ? item.key : '${item.data}:${item.level}';
      grouped.putIfAbsent(key, () => []).add(item);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      children: [
        heading(
          'One upgrade at a time',
          'Build what’s next.',
          library
              ? 'Browse the offline Home Village catalogue.'
              : 'Inspect levels, costs, and timers for ${v?.name ?? 'your village'}.',
        ),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('My village'),
              icon: Icon(Icons.fort),
            ),
            ButtonSegment(
              value: true,
              label: Text('Library'),
              icon: Icon(Icons.menu_book),
            ),
          ],
          selected: {library},
          onSelectionChanged: (s) => setState(() => library = s.first),
        ),
        const SizedBox(height: 16),
        TextField(
          onChanged: (value) => setState(() => query = value),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Find a building, hero, troop…',
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final label in [
                'All',
                'Buildings',
                'Army',
                'Heroes',
                'Pets',
                'Equipment',
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: category == label,
                    onSelected: (_) => setState(() => category = label),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (grouped.isEmpty)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Text(
              'No items found. Import a village or explore the Library.',
            ),
          ),
        for (final group in grouped.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: itemTile(
              group.first,
              count: group.length,
              reference: library,
            ),
          ),
      ],
    );
  }

  String groupFor(String section) => switch (section) {
    'buildings' || 'traps' => 'Buildings',
    'heroes' => 'Heroes',
    'pets' => 'Pets',
    'equipment' => 'Equipment',
    _ => 'Army',
  };
  String sectionFor(String? cat) => switch (cat) {
    'hero' => 'heroes',
    'pet' => 'pets',
    'hero-equipment' || 'equipment' => 'equipment',
    'troop' => 'units',
    'spell' => 'spells',
    'siege-machine' => 'siege_machines',
    _ => 'buildings',
  };

  Widget newsPage(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      heading(
        'Straight from Supercell',
        'The village bulletin.',
        'Game updates, events and balance announcements from the official Clash blog.',
      ),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => act(() => open(newsUrl)),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Official blog'),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Refresh news',
            onPressed: () => setState(() => news = null),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      const SizedBox(height: 16),
      FutureBuilder<List<NewsArticle>>(
        future: news ??= fetchNews(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(Icons.wifi_off, size: 32),
                    const SizedBox(height: 12),
                    const Text('Couldn’t load the bulletin.'),
                    const Text(
                      'Your tracker still works offline. Use the official blog link or try again later.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return Column(
            children: [
              for (final article in snapshot.data ?? [])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(18),
                      leading: const Icon(
                        Icons.campaign_rounded,
                        color: forest,
                      ),
                      title: Text(
                        article.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'supercell.com · Official announcement',
                      ),
                      trailing: const Icon(Icons.arrow_outward),
                      onTap: () => act(() => open(article.url)),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );

  Widget settings(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
    children: [
      heading('Make it yours', 'Village preferences.'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Appearance',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'system', label: Text('System')),
                  ButtonSegment(value: 'light', label: Text('Light')),
                  ButtonSegment(value: 'dark', label: Text('Dark')),
                ],
                selected: {store.theme},
                onSelectionChanged: (s) => act(() async {
                  store.theme = s.first;
                  await store.save();
                }),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: Column(
          children: [
            SwitchListTile(
              title: const Text(
                'Village check-in reminders',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'After 24 hours away from Clash on this device. Repeats every 3 hours outside quiet hours. Also reminds you to refresh completed upgrade timers.',
              ),
              value: store.reminders,
              onChanged: (value) => act(() async {
                store.reminders = value;
                await store.save();
                if (value) {
                  await store.deviceAction('requestNotifications');
                  redraw();
                }
              }),
            ),
            ListTile(
              leading: const Icon(Icons.bedtime_outlined),
              title: const Text('Quiet hours'),
              subtitle: Text(
                '${hourLabel(store.quietStart)} – ${hourLabel(store.quietEnd)} · same hour disables quiet time',
              ),
              onTap: quietHours,
            ),
            FutureBuilder<Map<String, dynamic>>(
              future: store.deviceStatus(),
              builder: (context, snapshot) {
                final status = snapshot.data ?? {};
                return Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.query_stats),
                      title: const Text('Usage Access'),
                      subtitle: Text(
                        status['supported'] == false
                            ? 'Check-in monitoring is available in the Android app.'
                            : status['usageAccess'] == true
                            ? 'Granted · monitors Clash launches on this device'
                            : 'Tap to allow detection of when Clash was last opened',
                      ),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () =>
                          act(() => store.deviceAction('usageSettings')),
                    ),
                    if (status['supported'] != false)
                      ListTile(
                        leading: const Icon(Icons.notifications_outlined),
                        title: const Text('Notification permission'),
                        subtitle: Text(
                          status['notifications'] == true
                              ? 'Allowed'
                              : 'Tap to enable reminders in Android settings',
                        ),
                        onTap: () => act(
                          () => store.deviceAction('notificationSettings'),
                        ),
                      ),
                  ],
                );
              },
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Text(
                'Android may delay background reminders to save battery. Opening Clash cannot tell us which village you visited.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('Export backup'),
              subtitle: const Text(
                'All profiles, manual upgrades and preferences',
              ),
              onTap: exportBackup,
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Restore backup'),
              subtitle: const Text(
                'Replace this device’s data with a saved backup',
              ),
              onTap: restoreBackup,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.cloud_download_outlined),
              title: const Text('Refresh game catalogue'),
              subtitle: Text(
                'Bundled data: ${catalogue.updatedAt.split('T').first}\nCommunity-maintained costs and times; verify in-game.',
              ),
              trailing: refreshing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              onTap: refreshing
                  ? null
                  : () => act(() async {
                      setState(() => refreshing = true);
                      try {
                        final result = await refreshCatalogue(store.prefs);
                        if (mounted) setState(() => catalogue = result);
                        message('Catalogue refreshed.');
                      } finally {
                        if (mounted) setState(() => refreshing = false);
                      }
                    }),
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('Source & APK releases'),
              onTap: () =>
                  act(() => open('https://github.com/saimadhav10/COCTracker')),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About & credits'),
              onTap: about,
            ),
          ],
        ),
      ),
      if (store.platformError != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text('Reminder setup: ${store.platformError}'),
        ),
      const SizedBox(height: 20),
      const Text(
        'COCTracker 0.1.0 · Local storage only\nNo account credentials are requested or stored.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12),
      ),
    ],
  );

  Future<void> importVillage() async {
    if (importing) return;
    setState(() => importing = true);
    final name = TextEditingController();
    final input = TextEditingController();
    String? error;
    try {
      await managedDialog<void>(
        context: ui,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Import village'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Paste Export Data JSON from Clash settings. Matching player tags update the existing profile. Other tags create a new profile.',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: name,
                      maxLength: 60,
                      decoration: const InputDecoration(
                        labelText: 'Village nickname (optional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: input,
                      minLines: 5,
                      maxLines: 9,
                      decoration: const InputDecoration(
                        labelText: 'Village JSON',
                        hintText: '{"tag":"#…", …}',
                      ),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  try {
                    final v = parseVillage(input.text, name: name.text);
                    final existing = store.villages
                        .where((e) => e.tag == v.tag)
                        .firstOrNull;
                    if (existing != null) {
                      if (name.text.trim().isEmpty) v.name = existing.name;
                      if (!await confirmIn(
                        context,
                        'Replace ${existing.name}?',
                        '${v.exportedAt.isBefore(existing.exportedAt) ? 'This export is older than the saved snapshot. ' : ''}The import replaces recorded levels and manual timers for ${v.tag}.',
                      )) {
                        return;
                      }
                    }
                    await store.add(v);
                    if (context.mounted) Navigator.pop(context);
                    message('Village saved on this device.');
                  } catch (e) {
                    update(
                      () => error = e.toString().replaceFirst(
                        'FormatException: ',
                        '',
                      ),
                    );
                  }
                },
                child: const Text('Import'),
              ),
            ],
          ),
        ),
      );
    } finally {
      name.dispose();
      input.dispose();
      if (mounted) setState(() => importing = false);
    }
  }

  Future<bool> confirmIn(
    BuildContext context,
    String title,
    String body,
  ) async =>
      await managedDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> profiles() async {
    await showModalBottomSheet<void>(
      context: ui,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .65,
            child: Column(
              children: [
                const Text(
                  'Your villages',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    children: [
                      for (final v in store.villages)
                        ListTile(
                          leading: const Icon(Icons.fort, color: forest),
                          title: Text(v.name),
                          subtitle: Text('${v.tag} · TH ${v.townHall}'),
                          selected: v.tag == store.selected?.tag,
                          onTap: () => act(() async {
                            store.selectedTag = v.tag;
                            await store.save();
                            if (context.mounted) Navigator.pop(context);
                          }),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) async {
                              if (value == 'rename') {
                                final name = await askText(
                                  'Rename village',
                                  'Nickname',
                                  initial: v.name,
                                );
                                if (name?.trim().isNotEmpty == true) {
                                  await act(() async {
                                    v.name = name!.trim();
                                    await store.save();
                                  });
                                }
                              } else if (await confirmIn(
                                context,
                                'Remove ${v.name}?',
                                'This removes the local profile. Export a backup first if you want to keep manual changes.',
                              )) {
                                await act(() async {
                                  store.villages.remove(v);
                                  await store.save();
                                });
                              }
                              if (context.mounted) Navigator.pop(context);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'rename',
                                child: Text('Rename'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Remove'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    importVillage();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Import another village'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<String?> askText(
    String title,
    String label, {
    String initial = '',
    int lines = 1,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await managedDialog<String>(
      context: ui,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            minLines: lines,
            maxLines: lines + 3,
            maxLength: lines == 1 ? 60 : null,
            decoration: InputDecoration(labelText: label),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> details(VillageItem item, {bool reference = false}) async {
    await showModalBottomSheet<void>(
      context: ui,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final entry = catalogue.entry(item.data);
        final levels = catalogue.levels(item.data);
        final next = catalogue.next(item);
        final th = store.selected?.townHall;
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .88,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              children: [
                Row(
                  children: [
                    itemImage(item, size: 76),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            catalogue.name(item),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            reference
                                ? 'Home Village upgrade library'
                                : 'Current level ${item.level} · ${groupFor(item.section)}',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  entry?['description'] ??
                      'This item is preserved from your export, but is not mapped in this catalogue. Refresh the catalogue after game updates.',
                ),
                const SizedBox(height: 16),
                if (item.upgrading && !reference) ...[
                  Text(
                    'Level ${item.level} → ${item.targetLevel}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${durationLabel(item.finishesAt!.difference(now))} · ${dateLabel(item.finishesAt!)}',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => act(() async {
                      if (!await confirmIn(
                        context,
                        'Confirm completed upgrade?',
                        'Only confirm if the upgrade is complete in Clash of Clans.',
                      )) {
                        return;
                      }
                      item.level = item.targetLevel ?? item.level + 1;
                      item.finishesAt = null;
                      item.targetLevel = null;
                      await store.save();
                      if (context.mounted) Navigator.pop(context);
                    }),
                    icon: const Icon(Icons.check),
                    label: const Text('Confirm complete'),
                  ),
                  TextButton(
                    onPressed: () => act(() async {
                      if (!await confirmIn(
                        context,
                        'Cancel recorded upgrade?',
                        'The recorded level will stay unchanged. This does not cancel anything in the game.',
                      )) {
                        return;
                      }
                      item.finishesAt = null;
                      item.targetLevel = null;
                      await store.save();
                      if (context.mounted) Navigator.pop(context);
                    }),
                    child: const Text('Cancel recorded timer'),
                  ),
                ] else if (!reference) ...[
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      startUpgrade(item);
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Record upgrade'),
                  ),
                  TextButton(
                    onPressed: () => act(() async {
                      final result = await askText(
                        'Correct recorded level',
                        'Current level',
                        initial: '${item.level}',
                      );
                      if (result == null) return;
                      final level = int.tryParse(result);
                      if (level == null || level < 0 || level > 1000) {
                        throw const FormatException(
                          'Enter a level from 0 to 1000.',
                        );
                      }
                      item.level = level;
                      await store.save();
                      if (context.mounted) Navigator.pop(context);
                    }),
                    child: const Text('Correct level manually'),
                  ),
                ],
                if (next != null && !reference)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Next level: ${costLabel(next)} · ${timeLabel(next)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                const Divider(height: 32),
                const Text(
                  'Every level, in detail',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Base values before Gold Pass discounts, boosts, helpers or events. Building prerequisites can also apply.',
                  style: TextStyle(fontSize: 12),
                ),
                for (final level in levels)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: level['level'] == item.level && !reference
                          ? forest.withValues(alpha: .13)
                          : Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Level ${level['level']}${th != null && level['townHall'] > th ? ' · Requires higher TH' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text('${costLabel(level)} · ${timeLabel(level)}'),
                        Text(
                          level['townHall'] == 999
                              ? 'Town Hall requirement not mapped'
                              : 'Town Hall ${level['townHall']}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        if ((level['requirements'] as Map?)?.isNotEmpty == true)
                          Text(
                            (level['requirements'] as Map).entries
                                .map(
                                  (e) =>
                                      '${humanize(e.key.toString())}: ${e.value}',
                                )
                                .join(' · '),
                            style: const TextStyle(fontSize: 12),
                          ),
                        if ((level['stats'] as Map?)?.isNotEmpty == true)
                          Text(
                            flatStats(level['stats'] as Map),
                            style: const TextStyle(fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                if (levels.isEmpty)
                  const Text(
                    'Level tables are not available for this item yet.',
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> startUpgrade(VillageItem item) async {
    final next = catalogue.next(item);
    final hours = TextEditingController(
      text: next?['seconds'] == null
          ? ''
          : '${(next!['seconds'] as num) ~/ 3600}',
    );
    final minutes = TextEditingController(
      text: next?['seconds'] == null
          ? '0'
          : '${((next!['seconds'] as num) % 3600 / 60).ceil()}',
    );
    String? error;
    await managedDialog<void>(
      context: ui,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('Record ${catalogue.name(item)}'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Level ${item.level} → ${item.level + 1}. Enter the remaining time shown in the game, including any boosts or discounts.',
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: hours,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Hours'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: minutes,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Minutes'),
                      ),
                    ),
                  ],
                ),
                if (next != null) Text('Base cost: ${costLabel(next)}'),
                if (next != null &&
                    next['townHall'] > (store.selected?.townHall ?? 1))
                  const Text(
                    'Catalogue lists a higher Town Hall requirement. Verify this upgrade in-game.',
                  ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final h = int.tryParse(hours.text);
                final m = int.tryParse(minutes.text);
                if (h == null ||
                    m == null ||
                    h < 0 ||
                    h > 8760 ||
                    m < 0 ||
                    m > 59 ||
                    h + m == 0) {
                  update(
                    () => error =
                        'Enter a positive duration. Minutes must be 0–59.',
                  );
                  return;
                }
                try {
                  item.finishesAt = now.add(Duration(hours: h, minutes: m));
                  item.targetLevel = item.level + 1;
                  await store.save();
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  update(() => error = e.toString());
                }
              },
              child: const Text('Start timer'),
            ),
          ],
        ),
      ),
    );
    hours.dispose();
    minutes.dispose();
  }

  Future<void> quietHours() async {
    final start = await showTimePicker(
      context: ui,
      initialTime: TimeOfDay(hour: store.quietStart, minute: 0),
      helpText: 'Quiet hours start (hour only)',
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: ui,
      initialTime: TimeOfDay(hour: store.quietEnd, minute: 0),
      helpText: 'Quiet hours end (hour only)',
    );
    if (end == null) return;
    await act(() async {
      store.quietStart = start.hour;
      store.quietEnd = end.hour;
      await store.save();
    });
  }

  Future<void> exportBackup() async {
    final text = store.recoveryData ?? store.backup();
    await managedDialog<void>(
      context: ui,
      builder: (context) => AlertDialog(
        title: const Text('Export backup'),
        content: const Text(
          'Keep this backup somewhere safe. It contains your village profiles and recorded upgrades. Import it on another device to transfer them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () => act(() async {
              await Clipboard.setData(ClipboardData(text: text));
              message('Backup copied.');
            }),
            child: const Text('Copy JSON'),
          ),
          if (onAndroid)
            FilledButton(
              onPressed: () => act(() async {
                final result = await TrackerStore.channel.invokeMethod<bool>(
                  'saveBackup',
                  {'text': text},
                );
                if (result == true) {
                  message('Backup saved.');
                  if (context.mounted) Navigator.pop(context);
                }
              }),
              child: const Text('Save file'),
            ),
        ],
      ),
    );
  }

  Future<void> restoreBackup() async {
    final text = TextEditingController();
    String? error;
    await managedDialog<void>(
      context: ui,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Restore backup'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Paste a COCTracker backup, or choose a saved JSON file. This replaces all local profiles and preferences.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: text,
                  minLines: 4,
                  maxLines: 7,
                  decoration: const InputDecoration(labelText: 'Backup JSON'),
                ),
                if (onAndroid)
                  TextButton.icon(
                    onPressed: () => act(() async {
                      final result = await TrackerStore.channel
                          .invokeMethod<String>('readBackup');
                      if (result != null) text.text = result;
                    }),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Choose file'),
                  ),
                if (error != null) Text(error!),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  TrackerStore.decodeBackup(text.text);
                  if (!await confirmIn(
                    context,
                    'Replace local data?',
                    'All existing profiles will be replaced with this backup.',
                  )) {
                    return;
                  }
                  await store.restore(text.text);
                  if (context.mounted) Navigator.pop(context);
                  message('Backup restored.');
                } catch (e) {
                  update(() => error = 'Invalid backup: $e');
                }
              },
              child: const Text('Restore'),
            ),
          ],
        ),
      ),
    );
    text.dispose();
  }

  Widget recovery() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      heading(
        'Your data is preserved',
        'Storage needs attention.',
        'The saved data could not be read. Export it before restoring a valid backup.',
      ),
      FilledButton(
        onPressed: exportBackup,
        child: const Text('Export original data'),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: restoreBackup,
        child: const Text('Restore a valid backup'),
      ),
    ],
  );
  void about() => managedDialog<void>(
    context: ui,
    builder: (context) => AlertDialog(
      title: const Text('Built for your village'),
      content: const SingleChildScrollView(
        child: Text(
          'COCTracker is a free, unofficial fan app.\n\nThis material is unofficial and is not endorsed by Supercell. For more information see Supercell’s Fan Content Policy: supercell.com/en/fan-content-policy\n\nGame artwork belongs to Supercell. Catalogue and image packaging: chiefpansancolt/clash-of-clans-data, MIT License (Christopher Pezza, 2026).\n\nProfiles are stored on your device. Network requests fetch the public game catalogue and official news; your village JSON is not uploaded. Android Usage Access is used locally for Clash reminders.\n\nUpgrade costs and times are community-maintained base values. Confirm current values in-game.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              showLicensePage(context: context, applicationName: 'COCTracker'),
          child: const Text('Licenses'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class _ContextHost extends StatelessWidget {
  const _ContextHost({required this.onContext, required this.child});
  final void Function(BuildContext) onContext;
  final Widget child;
  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) {
      onContext(context);
      return child;
    },
  );
}

String dateLabel(DateTime date) {
  final d = date.toLocal();
  return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String hourLabel(int hour) => '${hour.toString().padLeft(2, '0')}:00';
String numberLabel(num value) => value >= 1000000
    ? '${(value / 1000000).toStringAsFixed(2)}M'
    : value >= 1000
    ? '${(value / 1000).toStringAsFixed(1)}K'
    : '$value';
String costLabel(Map<String, dynamic> level) {
  final ores = level['ores'] as Map? ?? {};
  if (ores.isNotEmpty) {
    return ores.entries
        .map((e) => '${numberLabel(e.value as num)} ${e.key}')
        .join(' + ');
  }
  return level['cost'] == null
      ? 'Cost unavailable'
      : '${numberLabel(level['cost'] as num)} ${level['resource'] ?? ''}'
            .trim();
}

String timeLabel(Map<String, dynamic> level) => level['seconds'] == null
    ? 'Time unavailable'
    : level['seconds'] == 0
    ? 'Instant'
    : durationLabel(Duration(seconds: (level['seconds'] as num).toInt()));
String humanize(String text) =>
    text.replaceAllMapped(RegExp(r'[A-Z]'), (m) => ' ${m[0]}').trim();
String flatStats(Map stats, [String prefix = '']) => stats.entries
    .map(
      (e) => e.value is Map
          ? flatStats(e.value as Map, '${e.key} ')
          : '$prefix${humanize(e.key.toString())}: ${e.value}',
    )
    .join(' · ');
