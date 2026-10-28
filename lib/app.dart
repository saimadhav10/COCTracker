import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'domain/village.dart';
import 'domain/upgrades.dart';
import 'domain/armies.dart';
import 'services/game_updates.dart';
import 'services/tracker_store.dart';
import 'ui/citadel_theme.dart';

const forest = amber;
const gold = amber;
const violet = elixir;
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

class TrackerApp extends StatefulWidget {
  const TrackerApp({super.key, required this.store, required this.catalogue});
  final TrackerStore store;
  final Catalogue catalogue;
  @override
  State<TrackerApp> createState() => _TrackerAppState();
}

class _TrackerAppState extends State<TrackerApp> with WidgetsBindingObserver {
  late Catalogue catalogue = widget.catalogue;
  TrackerStore get store => widget.store;
  final clock = ValueNotifier<DateTime>(DateTime.now());
  Timer? ticker;
  int page = 0;
  String query = '';
  String category = 'All';
  String sort = 'Priority';
  String armyType = 'All';
  bool showLocked = false;
  bool showMaxed = false;
  bool refreshing = false;
  bool importing = false;
  String? busy;
  BuildContext? actionContext;
  BuildContext get ui => actionContext ?? context;
  DateTime get now => DateTime.now();
  bool get onAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    store.addListener(redraw);
    ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => clock.value = DateTime.now(),
    );
    unawaited(store.syncReminders());
  }

  @override
  void dispose() {
    ticker?.cancel();
    clock.dispose();
    store.removeListener(redraw);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      clock.value = DateTime.now();
      redraw();
    }
  }

  void redraw() {
    if (mounted) setState(() {});
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(ui).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> act(Future<void> Function() f) async {
    try {
      await f();
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

  UpgradePlanner planner(Village v) => UpgradePlanner(
    v,
    catalogue,
    builderDiscount: v.builderDiscount,
    researchDiscount: v.researchDiscount,
  );
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'COCTracker',
    debugShowCheckedModeBanner: false,
    theme: citadelTheme(store.theme),
    home: Builder(
      builder: (context) {
        actionContext = context;
        return shell(context);
      },
    ),
  );

  Widget shell(BuildContext context) {
    final v = store.selected;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            if (v != null)
              itemImage(
                VillageItem(
                  key: '',
                  data: 1000001,
                  section: 'buildings',
                  level: v.townHall,
                ),
                size: 36,
              )
            else
              const Icon(Icons.fort_rounded, color: amber, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      'COCTracker',
                      'Upgradables',
                      'Army Compositions',
                      'Village Accounts',
                      'Village Preferences',
                    ][page],
                    style: const TextStyle(
                      fontFamily: 'SpaceGrotesk',
                      fontWeight: FontWeight.w700,
                      fontSize: 19,
                      color: Color(0xffffc174),
                    ),
                  ),
                  Text(
                    v == null
                        ? 'Import your Home Village'
                        : '${v.tag} · Town Hall ${v.townHall}',
                    style: const TextStyle(fontSize: 10, color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Import village JSON',
            onPressed: importing ? null : importVillage,
            icon: const Icon(Icons.sync_rounded, color: amber),
          ),
          const SizedBox(width: 6),
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
                    2 => armiesPage(context),
                    3 => profilesPage(context),
                    _ => settings(context),
                  },
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 70,
        selectedIndex: page,
        onDestinationSelected: (n) => setState(() => page = n),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.fort_rounded), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.construction_rounded),
            label: 'Upgrades',
          ),
          NavigationDestination(
            icon: Icon(Icons.sports_martial_arts),
            label: 'Armies',
          ),
          NavigationDestination(
            icon: Icon(Icons.manage_accounts_outlined),
            label: 'Profiles',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget title(String text, {String? subtitle}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: const TextStyle(
            fontFamily: 'SpaceGrotesk',
            fontSize: 23,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: muted, fontSize: 12)),
        ],
      ],
    ),
  );
  Widget emptyVillage() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      CitadelPanel(
        color: amber,
        child: Column(
          children: [
            Image.asset('assets/icons/townhall_14.webp', height: 140),
            const SizedBox(height: 16),
            title(
              'Your village command center',
              subtitle:
                  'Import game JSON to reveal your upgrades, progress and available armies.',
            ),
            const Text(
              'In Clash, open Settings → More Settings → Export Data. Paste the copied JSON here.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: importVillage,
              icon: const Icon(Icons.content_paste_go),
              label: const Text('Import your first village'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      const CitadelPanel(
        child: Text(
          'No login required. Profiles and backups stay on your device. Real imported levels power this dashboard.',
        ),
      ),
    ],
  );

  ({int done, int total}) progress(Village v) {
    var done = 0;
    var total = 0;
    for (final item in planner(v).inventory) {
      final cap = catalogue.maxLevel(item, v.townHall);
      if (cap == null) continue;
      done += item.level.clamp(0, cap);
      total += cap;
    }
    return (done: done, total: total);
  }

  Widget resourceIcon(String resource, {double size = 17}) {
    final name = switch (resource) {
      'Gold' => 'gold',
      'Gems' => 'gems',
      'Elixir' => 'elixir',
      'Dark Elixir' => 'dark_elixir',
      'Shiny ore' => 'shiny_ore',
      'Glowing ore' => 'glowing_ore',
      'Starry ore' => 'starry_ore',
      _ => null,
    };
    return name == null
        ? Icon(Icons.diamond_outlined, size: size, color: amber)
        : Image.asset(
            'assets/icons/resource_$name.webp',
            width: size,
            height: size,
          );
  }

  Color resourceColor(VillageItem item) => switch (item.section) {
    'heroes' || 'pets' => darkElixir,
    'units' || 'spells' || 'siege_machines' || 'equipment' => elixir,
    _ => amber,
  };
  Widget itemImage(VillageItem item, {double size = 52}) {
    final path = item.data == 1000001 && item.level >= 1 && item.level <= 18
        ? 'assets/icons/townhall_${item.level}.webp'
        : catalogue.image(item);
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xff0b111e),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xff55513e)),
      ),
      child: path == null
          ? const Icon(Icons.fort_outlined, color: amber)
          : Image.asset(
              path,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.fort_outlined, color: amber),
            ),
    );
  }

  Widget amount(String resource, num value) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      resourceIcon(resource),
      const SizedBox(width: 5),
      Text(
        '${fullNumber(value)}${resource == 'Gold or Elixir' ? ' Gold/Elixir' : ''}',
        style: TextStyle(
          color: resource == 'Dark Elixir'
              ? darkElixir
              : resource == 'Elixir'
              ? elixir
              : amber,
          fontFamily: 'SpaceGrotesk',
          fontWeight: FontWeight.w700,
          fontSize: 13,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
  Widget countdown(VillageItem item) => ValueListenableBuilder<DateTime>(
    valueListenable: clock,
    builder: (context, time, _) => Text(
      liveCountdown(item.finishesAt!.difference(time)),
      style: TextStyle(
        color: item.ready(time) ? readyGreen : resourceColor(item),
        fontFamily: 'SpaceGrotesk',
        fontSize: 18,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );
  Widget liveProgress(VillageItem item) => ValueListenableBuilder<DateTime>(
    valueListenable: clock,
    builder: (context, time, _) {
      final start = item.startedAt;
      if (start == null) return const SizedBox.shrink();
      final whole = item.finishesAt!.difference(start).inMilliseconds;
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            minHeight: 5,
            color: resourceColor(item),
            value: whole <= 0
                ? 1
                : (time.difference(start).inMilliseconds / whole).clamp(0, 1),
          ),
        ),
      );
    },
  );

  Widget dashboard(BuildContext context) {
    final v = store.selected;
    if (v == null) return emptyVillage();
    final p = planner(v);
    final choices = p.choices;
    final stats = progress(v);
    final ratio = stats.total == 0 ? 0.0 : stats.done / stats.total;
    final costs = p.remainingCosts(choices);
    final active = v.active;
    final builderActive = active
        .where((e) => ['buildings', 'traps', 'heroes'].contains(e.section))
        .toList();
    final laboratory = active
        .where((e) => ['units', 'spells', 'siege_machines'].contains(e.section))
        .toList();
    final pets = active.where((e) => e.section == 'pets').toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        CitadelPanel(
          color: amber,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  itemImage(
                    VillageItem(
                      key: '',
                      data: 1000001,
                      section: 'buildings',
                      level: v.townHall,
                    ),
                    size: 70,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          v.name,
                          style: const TextStyle(
                            fontFamily: 'SpaceGrotesk',
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Color(0xffffc174),
                          ),
                        ),
                        Text(
                          'Town Hall ${v.townHall}',
                          style: const TextStyle(
                            fontFamily: 'SpaceGrotesk',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const CitadelLabel(
                          'Imported village',
                          color: readyGreen,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xff0b111e),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const CitadelLabel(
                            'Known level progress',
                            color: muted,
                          ),
                          Text(
                            '${(ratio * 100).toStringAsFixed(1)}%',
                            style: const TextStyle(
                              fontFamily: 'SpaceGrotesk',
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              color: Color(0xffffc174),
                            ),
                          ),
                          Text(
                            '${stats.done} / ${stats.total} mapped level steps',
                            style: const TextStyle(fontSize: 10, color: muted),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 58,
                      height: 58,
                      child: CircularProgressIndicator(
                        value: ratio,
                        strokeWidth: 6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const CitadelLabel(
                'Resources still needed to TH cap',
                color: muted,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 16,
                runSpacing: 10,
                children: [
                  for (final cost in costs.entries.where(
                    (e) => [
                      'Gold',
                      'Elixir',
                      'Dark Elixir',
                      'Gold or Elixir',
                    ].contains(e.key),
                  ))
                    amount(cost.key, cost.value),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Calculated from mapped levels, including missing buildings. Active upgrade costs are already spent.',
                style: TextStyle(fontSize: 10, color: muted),
              ),
              const Divider(),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final group in [
                    'Buildings',
                    'Defenses',
                    'Heroes',
                    'Lab',
                    'Walls',
                  ])
                    categoryProgress(v, group),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        snapshotNotice(v),
        const SizedBox(height: 20),
        sectionHeader(
          'Active Builders',
          builderActive.length,
          Icons.construction_rounded,
        ),
        if (builderActive.isEmpty)
          CitadelPanel(
            color: amber,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No builder upgrades recorded',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Start an eligible upgrade in Clash, then track it here.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: () => setState(() => page = 1),
                  child: const Text('Find an upgrade'),
                ),
              ],
            ),
          ),
        for (final item in builderActive)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: upgradeRow(p.choice(item), p, compact: true),
          ),
        const SizedBox(height: 18),
        sectionHeader(
          'Laboratory Research',
          laboratory.length,
          Icons.science_outlined,
        ),
        if (laboratory.isEmpty)
          const CitadelPanel(
            child: Text(
              'No research timer recorded.',
              style: TextStyle(color: muted),
            ),
          ),
        for (final item in laboratory)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: upgradeRow(p.choice(item), p, compact: true),
          ),
        if (pets.isNotEmpty) ...[
          const SizedBox(height: 18),
          sectionHeader('Pet House Training', pets.length, Icons.pets_outlined),
          for (final item in pets)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: upgradeRow(p.choice(item), p, compact: true),
            ),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: resourcePlan,
          icon: const Icon(Icons.account_balance_wallet_outlined),
          label: const Text('Resource planning & upgrade priorities'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: newsPanel,
          icon: const Icon(Icons.newspaper_outlined),
          label: const Text('Latest official news & events'),
        ),
        if (onAndroid) ...[
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => act(() => store.deviceAction('openClash')),
            icon: const Icon(Icons.sports_esports_outlined),
            label: const Text('Open Clash of Clans'),
          ),
        ],
      ],
    );
  }

  Widget sectionHeader(String text, int count, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Icon(icon, color: amber, size: 21),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: 'SpaceGrotesk',
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        CitadelLabel('$count tracked', color: muted),
      ],
    ),
  );
  Widget categoryProgress(Village v, String group) {
    var done = 0;
    var max = 0;
    for (final i in planner(
      v,
    ).inventory.where((e) => categoryOf(e, catalogue) == group)) {
      final cap = catalogue.maxLevel(i, v.townHall);
      if (cap == null) continue;
      done += i.level.clamp(0, cap);
      max += cap;
    }
    if (max == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xff0b111e),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        '$group  ${(done / max * 100).round()}%',
        style: const TextStyle(fontSize: 10, color: muted),
      ),
    );
  }

  Widget snapshotNotice(Village v) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        v.needsRefresh(now) ? Icons.sync_problem : Icons.check_circle_outline,
        color: v.needsRefresh(now) ? amber : readyGreen,
        size: 16,
      ),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          'Snapshot ${dateLabel(v.exportedAt)}${v.needsRefresh(now) ? ' · Fresh import recommended' : ''}\nTimers follow saved finish times; game-side changes need a new import.',
          style: const TextStyle(fontSize: 10, color: muted),
        ),
      ),
    ],
  );

  Widget upgrades(BuildContext context) {
    final v = store.selected;
    if (v == null) return emptyVillage();
    final p = planner(v);
    final all = p.choices;
    final filtered = all
        .where(
          (o) =>
              (o.item.upgrading ||
                  o.eligible ||
                  (showLocked && !o.maxed) ||
                  (showMaxed && o.maxed)) &&
              (category == 'All' ||
                  categoryOf(o.item, catalogue) == category) &&
              catalogue
                  .name(o.item)
                  .toLowerCase()
                  .contains(query.toLowerCase()),
        )
        .toList();
    filtered.sort((a, b) {
      if (a.item.upgrading != b.item.upgrading) {
        return a.item.upgrading ? -1 : 1;
      }
      if (sort == 'Time') {
        return p
            .duration(a.item, a.level ?? {})
            .compareTo(p.duration(b.item, b.level ?? {}));
      }
      if (sort == 'Cost') {
        final resource = (a.level?['resource'] ?? '').toString().compareTo(
          (b.level?['resource'] ?? '').toString(),
        );
        if (resource != 0) return resource;
        return (a.level?['cost'] as num? ?? 0).compareTo(
          b.level?['cost'] as num? ?? 0,
        );
      }
      final priority = p.priority(a.item).compareTo(p.priority(b.item));
      return priority != 0
          ? priority
          : catalogue.name(a.item).compareTo(catalogue.name(b.item));
    });
    final grouped = <String, List<UpgradeChoice>>{};
    for (final option in filtered) {
      final key = option.item.upgrading
          ? option.item.key
          : '${option.item.data}:${option.item.level}:${option.lockReason}';
      grouped.putIfAbsent(key, () => []).add(option);
    }
    final eligible = all.where((e) => e.eligible).length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          onChanged: (s) => setState(() => query = s),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search your upgrades',
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final c in [
                'All',
                'Buildings',
                'Defenses',
                'Army',
                'Lab',
                'Heroes',
                'Pets',
                'Equipment',
                'Walls',
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: ChoiceChip(
                    label: Text(
                      c,
                      style: TextStyle(
                        fontSize: 12,
                        color: category == c ? const Color(0xff241600) : null,
                      ),
                    ),
                    selected: category == c,
                    onSelected: (_) => setState(() => category = c),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        CitadelPanel(
          color: amber,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CitadelLabel('Eligible at your current Town Hall'),
              const SizedBox(height: 5),
              Text(
                '$eligible upgrades available',
                style: const TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Town Hall ${v.townHall} · completed building and lab prerequisites checked. Resource affordability is not inferred.',
                style: const TextStyle(fontSize: 11, color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const CitadelLabel('Sort', color: muted),
            for (final s in ['Priority', 'Time', 'Cost'])
              ChoiceChip(
                label: Text(
                  s,
                  style: TextStyle(
                    fontSize: 11,
                    color: sort == s ? const Color(0xff241600) : null,
                  ),
                ),
                selected: sort == s,
                onSelected: (_) => setState(() => sort = s),
              ),
            FilterChip(
              label: const Text('Show locked', style: TextStyle(fontSize: 11)),
              selected: showLocked,
              onSelected: (b) => setState(() => showLocked = b),
            ),
            FilterChip(
              label: const Text('Show maxed', style: TextStyle(fontSize: 11)),
              selected: showMaxed,
              onSelected: (b) => setState(() => showMaxed = b),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (sort == 'Priority')
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'App planning order: offense & prerequisites → heroes/research → economy → defenses → walls. Adjust for your goals.',
              style: TextStyle(fontSize: 10, color: muted),
            ),
          ),
        for (final group in grouped.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: upgradeRow(group.first, p, count: group.length),
          ),
        if (grouped.isEmpty)
          const CitadelPanel(
            child: Text(
              'No matching eligible upgrades. Try another category or reveal locked and maxed items.',
            ),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: resourcePlan,
          icon: const Icon(Icons.account_balance_wallet_outlined),
          label: const Text('Plan remaining resources'),
        ),
      ],
    );
  }

  Widget upgradeRow(
    UpgradeChoice option,
    UpgradePlanner p, {
    int count = 1,
    bool compact = false,
  }) {
    final item = option.item;
    final level = option.level;
    final active = item.upgrading;
    final color = resourceColor(item);
    final costs = level == null ? <String, num>{} : p.costs(item, level);
    final canStart = option.eligible && busy != item.key;
    return CitadelPanel(
      color: active ? color : null,
      padding: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              itemImage(item, size: compact ? 48 : 58),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      catalogue.name(item),
                      style: const TextStyle(
                        fontFamily: 'SpaceGrotesk',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 7,
                      runSpacing: 5,
                      children: [
                        Text(
                          item.level == 0
                              ? 'Not built'
                              : 'LVL ${item.level}${level != null ? ' → ${item.targetLevel ?? item.level + 1}' : ''}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (count > 1)
                          CitadelLabel('$count available', color: muted),
                        if (option.maxed)
                          const CitadelLabel('TH MAX', color: readyGreen),
                      ],
                    ),
                    if (costs.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 8,
                        runSpacing: 5,
                        children: [
                          for (final c in costs.entries) amount(c.key, c.value),
                        ],
                      ),
                    ],
                    if (!active && level != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          timeLabel({
                            ...level,
                            'seconds': p.duration(item, level),
                          }),
                          style: const TextStyle(fontSize: 11, color: muted),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 22),
          if (active) ...[
            Row(
              children: [
                Expanded(child: countdown(item)),
                if (busy == item.key)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else ...[
                  TextButton(
                    onPressed: () =>
                        rowAction(item.key, () => store.complete(item)),
                    child: const Text(
                      'Complete',
                      style: TextStyle(
                        color: readyGreen,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        rowAction(item.key, () => store.cancel(item)),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
            liveProgress(item),
            Text(
              item.startedAt == null
                  ? 'Imported finish time'
                  : 'Tracked countdown · estimated duration',
              style: const TextStyle(fontSize: 9, color: muted),
            ),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    option.eligible
                        ? (option.missing
                              ? 'Available to build'
                              : 'Ready to upgrade')
                        : option.maxed
                        ? option.lockReason!
                        : option.lockReason ?? 'Unavailable',
                    style: TextStyle(
                      color: option.eligible ? readyGreen : muted,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (option.eligible)
                  FilledButton(
                    onPressed: canStart
                        ? () => rowAction(
                            item.key,
                            () => store.start(option, catalogue),
                          )
                        : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 36),
                    ),
                    child: Text(
                      busy == item.key
                          ? 'Saving…'
                          : option.missing
                          ? 'Build'
                          : 'Upgrade',
                    ),
                  ),
              ],
            ),
          if (p.discount(item) > 0 && level != null && !active)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${p.discount(item)}% selected boost · rounded estimate',
                style: const TextStyle(fontSize: 9, color: muted),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> rowAction(String key, Future<void> Function() f) async {
    if (busy != null) return;
    setState(() => busy = key);
    await act(f);
    if (mounted) setState(() => busy = null);
  }

  Widget armiesPage(BuildContext context) {
    final v = store.selected;
    if (v == null) return emptyVillage();
    final capacity = campCapacity(v, catalogue);
    final plans = armyPlans(
      v,
      catalogue,
    ).where((p) => armyType == 'All' || p.type == armyType).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CitadelPanel(
          color: elixir,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CitadelLabel('Army planning', color: elixir),
              const SizedBox(height: 7),
              Text(
                '$capacity housing from your camps',
                style: const TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Text(
                'Calculated composition suggestions use your imported troops and levels. These are planning recommendations, not your trained army or measured performance.',
                style: TextStyle(fontSize: 11, color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final type in [
                'All',
                'Air',
                'Ground',
                'Farming',
                'Practice',
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      type,
                      style: TextStyle(
                        color: armyType == type ? Colors.black : null,
                      ),
                    ),
                    selected: armyType == type,
                    onSelected: (_) => setState(() => armyType = type),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (final plan in plans)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: armyCard(plan, v, capacity),
          ),
        if (plans.isEmpty)
          const CitadelPanel(
            child: Text(
              'Army capacity or troop data is not mapped for this snapshot. Import full village JSON to generate a plan.',
            ),
          ),
        const SizedBox(height: 12),
        guidePanel('War preparation', [
          'Scout the assigned target and identify the Clan Castle, defending heroes, Town Hall and major defenses before choosing an entry.',
          'Choose an army you can practise in friendly challenges. Plan the funnel, spell timings, cleanup and siege role around that specific base.',
          'Coordinate target assignments with your clan. Check hero, equipment, siege and reinforcement availability in-game before committing.',
          'Review the replay after each attack. Track what happened rather than assuming a strategy guarantees stars.',
        ]),
        const SizedBox(height: 14),
        guidePanel('Farming and progression', [
          'Open the eligible-upgrade list and choose a concrete resource goal. The resource planner calculates catalogue costs still ahead of your village.',
          'Prioritise capacity or storage prerequisites that prevent your next upgrade. Keep a useful attack army levelled so farming remains practical.',
          'Choose reachable loot and a suitable route into collectors or storages. The best entry depends on the defending base, not a fixed deployment pattern.',
          'After spending resources on upgrades, import fresh village JSON. The tracker does not know your live resource balances.',
        ]),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => act(
            () => open(
              'https://supercell.com/en/games/clashofclans/blog/news/home-village-changes-2/',
            ),
          ),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Official army & village update'),
        ),
      ],
    );
  }

  Widget armyCard(ArmyPlan plan, Village v, int capacity) {
    final occupied = plan.roster.entries.fold<int>(
      0,
      (n, e) =>
          n +
          ((catalogue.entry(e.key)?['housing'] as num? ?? 0) * e.value).toInt(),
    );
    return CitadelPanel(
      color: elixir,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CitadelLabel('${plan.type} · calculated plan', color: elixir),
          const SizedBox(height: 8),
          Text(
            plan.title,
            style: const TextStyle(
              fontFamily: 'SpaceGrotesk',
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Army roster · $occupied / $capacity housing',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              for (final e in plan.roster.entries)
                SizedBox(
                  width: 75,
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          itemImage(
                            v.items.firstWhere((i) => i.data == e.key),
                            size: 64,
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: amber,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '×${e.value}',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        catalogue.entry(e.key)?['name'] ?? 'Unmapped',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 10),
                      ),
                      Text(
                        'Lv ${v.items.firstWhere((i) => i.data == e.key).level}',
                        style: const TextStyle(fontSize: 10, color: muted),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              'Spells & support · ${spellCapacity(v, catalogue)} spell capacity',
              style: const TextStyle(
                fontFamily: 'SpaceGrotesk',
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            children: [
              for (final section in [
                'spells',
                'siege_machines',
                'heroes',
                'equipment',
              ])
                if (v.items.any((e) => e.section == section))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CitadelLabel(
                          'Owned ${section.replaceAll('_', ' ')}',
                          color: elixir,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            for (final item in v.items.where(
                              (e) => e.section == section,
                            ))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xff0b111e),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Text(
                                  '${catalogue.name(item)} · Lv ${item.level}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: muted,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'Tactical attack plan',
              style: TextStyle(
                fontFamily: 'SpaceGrotesk',
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            children: [
              for (var n = 0; n < plan.steps.length; n++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CitadelLabel('P${n + 1}'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          plan.steps[n],
                          style: const TextStyle(fontSize: 12, color: muted),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          FilledButton.icon(
            onPressed: () => act(() async {
              final text =
                  '${plan.title}\n${plan.roster.entries.map((e) => '${e.value} × ${catalogue.entry(e.key)?['name']}').join('\n')}\n$occupied/$capacity housing\nCalculated COCTracker plan; verify spells and heroes in-game.';
              await Clipboard.setData(ClipboardData(text: text));
              message('Army plan copied.');
            }),
            icon: const Icon(Icons.copy),
            label: const Text('Copy army plan'),
          ),
        ],
      ),
    );
  }

  Widget guidePanel(String heading, List<String> paragraphs) => CitadelPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: const TextStyle(
            fontFamily: 'SpaceGrotesk',
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        for (var n = 0; n < paragraphs.length; n++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '${n + 1}. ${paragraphs[n]}',
              style: const TextStyle(fontSize: 12, color: muted),
            ),
          ),
      ],
    ),
  );

  Future<void> resourcePlan() async {
    final v = store.selected;
    if (v == null) return;
    final p = planner(v);
    final choices = p.choices;
    final totals = p.remainingCosts(choices);
    var work = 0;
    for (final c in choices) {
      final cap = catalogue.maxLevel(c.item, v.townHall);
      if (cap == null) continue;
      for (final l
          in catalogue
              .levels(c.item.data)
              .where(
                (l) =>
                    l['level'] > (c.item.targetLevel ?? c.item.level) &&
                    l['level'] <= cap,
              )) {
        work += p.duration(c.item, l);
      }
    }
    await showModalBottomSheet<void>(
      context: ui,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .87,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              title(
                'Resource planning',
                subtitle: 'Remaining known upgrades at Town Hall ${v.townHall}',
              ),
              CitadelPanel(
                color: amber,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CitadelLabel('Remaining costs'),
                    const SizedBox(height: 12),
                    for (final e in totals.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: amount(e.key, e.value),
                      ),
                    const Text(
                      'Includes missing buildings and all mapped levels up to this TH cap. Excludes upgrades already paid for and in progress. Unknown costs are not guessed.',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              CitadelPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CitadelLabel('Total remaining upgrade work'),
                    const SizedBox(height: 8),
                    Text(
                      work == 0
                          ? 'No mapped work remaining'
                          : durationLabel(Duration(seconds: work)),
                      style: const TextStyle(
                        fontFamily: 'SpaceGrotesk',
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text(
                      'Sum of known durations, not a completion date. Builders, the laboratory and pets can work in parallel. Selected boosts apply as estimates.',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              guidePanel('Upgrade priorities', [
                'Unlock useful offense and prerequisites first: laboratory, camps, Clan Castle and production buildings. This is an app planning rule, not an official ranking.',
                'Keep the troops, spells, heroes and equipment used by your attack plan progressing. Coordinate hero availability with your clan’s war schedule.',
                'Check storages before saving for an upgrade. Resolve resource capacity requirements before the builder becomes free.',
                'Use the Cost sort within each currency and Time sort to fit your available resources and play schedule. Gold and Dark Elixir are not treated as interchangeable.',
                'Spend surplus resources toward walls when appropriate. Re-import whenever you want to reconcile manual tracking with the game.',
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget profilesPage(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const CitadelLabel('Active village focus', color: readyGreen),
      const SizedBox(height: 12),
      for (final v in store.villages)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: CitadelPanel(
            color: v == store.selected ? amber : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    itemImage(
                      VillageItem(
                        key: '',
                        data: 1000001,
                        section: 'buildings',
                        level: v.townHall,
                      ),
                      size: 62,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            v.name,
                            style: const TextStyle(
                              fontFamily: 'SpaceGrotesk',
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${v.tag} · TH ${v.townHall}',
                            style: const TextStyle(fontSize: 11, color: muted),
                          ),
                          if (v == store.selected)
                            const CitadelLabel(
                              'Current active',
                              color: readyGreen,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  '${v.active.length} recorded upgrades · Imported ${dateLabel(v.exportedAt)}',
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () => act(() async {
                          store.selectedTag = v.tag;
                          await store.save();
                          setState(() => page = 0);
                        }),
                        child: Text(
                          v == store.selected ? 'View village' : 'Switch',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Rename ${v.name}',
                      onPressed: () => act(() async {
                        final name = await askText(
                          'Rename village',
                          'Nickname',
                          initial: v.name,
                        );
                        if (name?.trim().isNotEmpty == true) {
                          v.name = name!.trim();
                          await store.save();
                        }
                      }),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Remove ${v.name}',
                      onPressed: () => act(() async {
                        if (await confirmIn(
                          ui,
                          'Remove ${v.name}?',
                          'This removes the local profile. Export a backup first to keep manual changes.',
                        )) {
                          store.villages.remove(v);
                          await store.save();
                        }
                      }),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      CitadelPanel(
        color: amber,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title(
              'Link another village',
              subtitle:
                  'Import another account’s in-game JSON. Each player tag gets its own local profile.',
            ),
            FilledButton.icon(
              onPressed: importVillage,
              icon: const Icon(Icons.add),
              label: const Text('Import village JSON'),
            ),
          ],
        ),
      ),
    ],
  );

  Widget settings(BuildContext context) {
    final v = store.selected;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        title(
          'Settings & local data',
          subtitle: 'Your snapshots stay on this device.',
        ),
        if (v != null) ...[
          CitadelPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CitadelLabel('Gold Pass boosts'),
                const SizedBox(height: 8),
                const Text(
                  'Select the discounts currently unlocked in-game. These adjust new manual timers and planning estimates; imported timers stay unchanged.',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
                const SizedBox(height: 12),
                boostSelector(
                  'Builder boost',
                  v.builderDiscount,
                  (n) => act(() async {
                    v.builderDiscount = n;
                    await store.save();
                  }),
                ),
                boostSelector(
                  'Research boost',
                  v.researchDiscount,
                  (n) => act(() async {
                    v.researchDiscount = n;
                    await store.save();
                  }),
                ),
                TextButton(
                  onPressed: () => act(
                    () => open(
                      'https://sc-clashofclans.zendesk.com/hc/en-us/articles/49529123544091-Gold-Pass',
                    ),
                  ),
                  child: const Text('Official Gold Pass information'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        CitadelPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CitadelLabel('Theme mode'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final pair in [
                    ('citadel', 'Dark Citadel'),
                    ('onyx', 'Onyx Black'),
                    ('purple', 'Midnight Purple'),
                  ])
                    ChoiceChip(
                      label: Text(
                        pair.$2,
                        style: TextStyle(
                          color: store.theme == pair.$1 ? Colors.black : null,
                          fontSize: 11,
                        ),
                      ),
                      selected: store.theme == pair.$1,
                      onSelected: (_) => act(() async {
                        store.theme = pair.$1;
                        await store.save();
                      }),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        CitadelPanel(
          padding: 0,
          child: Column(
            children: [
              SwitchListTile(
                title: const Text(
                  'Check-in & upgrade reminders',
                  style: TextStyle(
                    fontFamily: 'SpaceGrotesk',
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: const Text(
                  '24 hours away from Clash; repeats every 3 hours outside quiet hours. Also alerts when upgrade timers end.',
                  style: TextStyle(fontSize: 11),
                ),
                value: store.reminders,
                onChanged: !onAndroid
                    ? null
                    : (value) => act(() async {
                        store.reminders = value;
                        await store.save();
                        if (value) {
                          await store.deviceAction('requestNotifications');
                        }
                        redraw();
                      }),
              ),
              ListTile(
                leading: const Icon(Icons.bedtime_outlined, color: elixir),
                title: const Text('Quiet hours'),
                subtitle: Text(
                  '${hourLabel(store.quietStart)} – ${hourLabel(store.quietEnd)}',
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
                        leading: const Icon(
                          Icons.query_stats,
                          color: darkElixir,
                        ),
                        title: const Text('Usage Access'),
                        subtitle: Text(
                          status['supported'] == false
                              ? 'Available in the Android app'
                              : status['usageAccess'] == true
                              ? 'Granted · local Clash launch detection'
                              : 'Allow detection of when Clash was opened',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onTap: !onAndroid
                            ? null
                            : () => act(
                                () => store.deviceAction('usageSettings'),
                              ),
                      ),
                      if (onAndroid)
                        ListTile(
                          leading: const Icon(
                            Icons.notifications_outlined,
                            color: amber,
                          ),
                          title: const Text('Notification permission'),
                          subtitle: Text(
                            status['notifications'] == true
                                ? 'Allowed'
                                : 'Tap to allow in Android settings',
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
                padding: EdgeInsets.all(16),
                child: Text(
                  'Android may delay background checks. Opening Clash is detected per device, not per village.',
                  style: TextStyle(fontSize: 10, color: muted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        CitadelPanel(
          padding: 0,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.download_outlined, color: amber),
                title: const Text('Export backup'),
                subtitle: const Text('All local profiles and preferences'),
                onTap: exportBackup,
              ),
              ListTile(
                leading: const Icon(Icons.restore, color: amber),
                title: const Text('Restore backup'),
                onTap: restoreBackup,
              ),
              ListTile(
                leading: const Icon(
                  Icons.cloud_download_outlined,
                  color: darkElixir,
                ),
                title: const Text('Refresh upgrade catalogue'),
                subtitle: Text(
                  'Snapshot ${catalogue.updatedAt.split('T').first} · community maintained',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: refreshing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                onTap: refreshing
                    ? null
                    : () => act(() async {
                        setState(() => refreshing = true);
                        try {
                          final next = await refreshCatalogue(store.prefs);
                          if (mounted) setState(() => catalogue = next);
                          message('Catalogue refreshed.');
                        } finally {
                          if (mounted) setState(() => refreshing = false);
                        }
                      }),
              ),
              ListTile(
                leading: const Icon(Icons.newspaper_outlined, color: amber),
                title: const Text('Official news & events'),
                onTap: newsPanel,
              ),
              ListTile(
                leading: const Icon(Icons.code, color: muted),
                title: const Text('Source & APK releases'),
                onTap: () => act(
                  () => open('https://github.com/saimadhav10/COCTracker'),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline, color: muted),
                title: const Text('About & credits'),
                onTap: about,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        CitadelPanel(
          color: amber,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CitadelLabel('About the Creator'),
              const SizedBox(height: 10),
              const Text(
                '@saimadhav10',
                style: TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () =>
                    act(() => open('https://github.com/saimadhav10')),
                icon: const Icon(Icons.code),
                label: const Text('View creator on GitHub'),
              ),
            ],
          ),
        ),
        if (store.platformError != null)
          Text(
            'Reminder setup: ${store.platformError}',
            style: const TextStyle(color: amber),
          ),
        const SizedBox(height: 22),
        const Text(
          'COCTracker v2.0.0\nLocal JSON tracking · Unofficial Supercell fan app',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: muted),
        ),
      ],
    );
  }

  Widget boostSelector(String label, int value, void Function(int) change) =>
      Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          DropdownButton<int>(
            value: value,
            items: [
              for (final n in [0, 10, 15, 20])
                DropdownMenuItem(value: n, child: Text('$n%')),
            ],
            onChanged: (n) {
              if (n != null) change(n);
            },
          ),
        ],
      );
  Future<void> newsPanel() async {
    Future<List<NewsArticle>>? bulletin;
    await showModalBottomSheet<void>(
      context: ui,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .85,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              title(
                'Official village bulletin',
                subtitle:
                    'Supercell news, balance changes and event announcements.',
              ),
              OutlinedButton(
                onPressed: () => act(() => open(newsUrl)),
                child: const Text('Open official blog'),
              ),
              FutureBuilder<List<NewsArticle>>(
                future: bulletin ??= fetchNews(),
                builder: (context, s) {
                  if (s.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (s.hasError) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'News could not load. Your tracker still works offline. Use the official blog link above.',
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final a in s.data ?? [])
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            a.title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: const Text(
                            'supercell.com · Official announcement',
                            style: TextStyle(fontSize: 10),
                          ),
                          trailing: const Icon(Icons.open_in_new, size: 18),
                          onTap: () => act(() => open(a.url)),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String fullNumber(num value) => value.round().toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
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

  Widget heading(String eyebrow, String text, [String? subtitle]) =>
      title(text, subtitle: subtitle ?? eyebrow);
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
          'COCTracker is a free, unofficial fan app by @saimadhav10.\n\nThis material is unofficial and is not endorsed by Supercell. For more information see Supercell’s Fan Content Policy: supercell.com/en/fan-content-policy\n\nGame artwork belongs to Supercell. Official currency icons: Supercell Fan Kit. Catalogue and additional game artwork packaging: chiefpansancolt/clash-of-clans-data, MIT License (Christopher Pezza, 2026). Fonts: Space Grotesk and Plus Jakarta Sans, SIL Open Font License.\n\nProfiles are stored on your device. Network requests fetch the public game catalogue and official news; your village JSON is not uploaded. Android Usage Access is used locally for Clash reminders.\n\nUpgrade values are community-maintained base values. Boosts and remaining-work totals are labelled calculations. Army plans are generated planning suggestions using your imported troop levels and capacity; they are not performance statistics. Strategy guidance is app-authored. Verify current game values in Clash.',
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
