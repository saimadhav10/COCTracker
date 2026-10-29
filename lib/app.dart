import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'domain/village.dart';
import 'domain/upgrades.dart';
import 'domain/sourced_armies.dart';
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
  late final armyCatalogue = loadSourcedArmies();
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
                      v?.name ?? 'COCTracker',
                      'Upgradables',
                      'Armies',
                      'Recommendations',
                      'Profiles',
                      'Settings',
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
                        ? 'Home Village'
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
                    3 => recommendationsPage(context),
                    4 => profilesPage(context),
                    _ => settings(context),
                  },
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
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
            icon: Icon(Icons.auto_awesome_outlined),
            label: 'Recommendations',
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
  Widget emptyVillage() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/branding/app-icon.webp', width: 112, height: 112),
        const SizedBox(height: 20),
        const Text(
          'Import village',
          style: TextStyle(
            fontFamily: 'SpaceGrotesk',
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Clash settings → Export Data',
          style: TextStyle(fontSize: 12, color: muted),
        ),
        const SizedBox(height: 12),
        actionIcon(
          'Import your first village',
          Icons.add_circle_outline,
          importVillage,
        ),
      ],
    ),
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
    final stats = progress(v);
    final ratio = stats.total == 0 ? 0.0 : stats.done / stats.total;
    final groups = <(String, IconData, List<VillageItem>)>[
      (
        'Active Builders',
        Icons.construction_rounded,
        v.active
            .where((e) => ['buildings', 'traps', 'heroes'].contains(e.section))
            .toList(),
      ),
      (
        'Laboratory',
        Icons.science_outlined,
        v.active
            .where(
              (e) => ['units', 'spells', 'siege_machines'].contains(e.section),
            )
            .toList(),
      ),
      (
        'Pets',
        Icons.pets_outlined,
        v.active.where((e) => e.section == 'pets').toList(),
      ),
    ];
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        CitadelPanel(
          color: amber,
          child: Column(
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
                    size: 64,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Town Hall ${v.townHall}',
                          style: const TextStyle(
                            fontFamily: 'SpaceGrotesk',
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                            color: amber,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip:
                        '${dateLabel(v.exportedAt)}${v.needsRefresh(now) ? ' · Import recommended' : ''}',
                    onPressed: importVillage,
                    icon: Icon(
                      v.needsRefresh(now)
                          ? Icons.sync_problem
                          : Icons.verified_outlined,
                      color: v.needsRefresh(now) ? amber : readyGreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xff0b111e),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const CitadelLabel('Village progress', color: muted),
                          Tooltip(
                            message:
                                'Recorded level progress toward current Town Hall caps, including unbuilt buildings.',
                            child: Text(
                              '${(ratio * 100).toStringAsFixed(1)}%',
                              style: const TextStyle(
                                fontFamily: 'SpaceGrotesk',
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                color: amber,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 60,
                      height: 60,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox.expand(
                            child: CircularProgressIndicator(
                              value: ratio,
                              strokeWidth: 5,
                              backgroundColor: amber.withValues(alpha: .1),
                            ),
                          ),
                          const Icon(Icons.fort_rounded, color: amber),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, box) => Wrap(
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
                      SizedBox(
                        width: (box.maxWidth - 8) / 2,
                        child: categoryProgress(v, group),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        for (final group in groups) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(
                group.$2,
                color: group.$1 == 'Laboratory'
                    ? elixir
                    : group.$1 == 'Pets'
                    ? darkElixir
                    : amber,
                size: 19,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  group.$1,
                  style: const TextStyle(
                    fontFamily: 'SpaceGrotesk',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${group.$3.length}',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              IconButton(
                tooltip: 'Recommendations',
                onPressed: () => setState(() => page = 3),
                icon: const Icon(Icons.arrow_forward_rounded, size: 19),
              ),
            ],
          ),
          if (group.$3.isEmpty)
            CitadelPanel(
              padding: 12,
              child: Row(
                children: [
                  const Icon(
                    Icons.hourglass_empty_rounded,
                    color: muted,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Idle', style: TextStyle(color: muted)),
                  ),
                  IconButton(
                    tooltip: 'Find an upgrade',
                    onPressed: () => setState(() => page = 1),
                    icon: const Icon(Icons.add_rounded, color: amber),
                  ),
                ],
              ),
            ),
          for (final item in group.$3)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: upgradeRow(p.choice(item), p, compact: true),
            ),
        ],
      ],
    );
  }

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

  IconData categorySymbol(String category) => switch (category) {
    'Buildings' => Icons.home_outlined,
    'Defenses' => Icons.shield_outlined,
    'Army' => Icons.fort_outlined,
    'Lab' => Icons.science_outlined,
    'Heroes' => Icons.person_outline,
    'Pets' => Icons.pets_outlined,
    'Equipment' => Icons.hardware_outlined,
    'Walls' => Icons.view_week_outlined,
    _ => Icons.grid_view_rounded,
  };

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
          : '${option.item.data}:${option.item.level}:${option.lockReason}:${jsonEncode(p.costs(option.item, option.level ?? {}))}';
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
                    label: Tooltip(
                      message: c,
                      child: Icon(
                        categorySymbol(c),
                        size: 18,
                        color: category == c ? Colors.black : muted,
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
        Text(
          '$eligible available',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const CitadelLabel('Sort', color: muted),
            for (final s in ['Priority', 'Time', 'Cost'])
              ChoiceChip(
                label: Tooltip(
                  message: s,
                  child: Icon(
                    s == 'Priority'
                        ? Icons.auto_awesome_outlined
                        : s == 'Time'
                        ? Icons.schedule_rounded
                        : Icons.diamond_outlined,
                    size: 17,
                    color: sort == s ? Colors.black : muted,
                  ),
                ),
                selected: sort == s,
                onSelected: (_) => setState(() => sort = s),
              ),
            FilterChip(
              label: const Tooltip(
                message: 'Show locked',
                child: Icon(Icons.lock_outline, size: 17),
              ),
              selected: showLocked,
              onSelected: (b) => setState(() => showLocked = b),
            ),
            FilterChip(
              label: const Tooltip(
                message: 'Show maxed',
                child: Icon(Icons.verified_outlined, size: 17),
              ),
              selected: showMaxed,
              onSelected: (b) => setState(() => showMaxed = b),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final group in grouped.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: upgradeRow(group.first, p, count: group.length),
          ),
        if (grouped.isEmpty) const CitadelPanel(child: Text('No upgrades')),
      ],
    );
  }

  String finishLabel(DateTime date) {
    final local = date.toLocal();
    final labels = MaterialLocalizations.of(ui);
    return '${labels.formatShortDate(local)} · ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(ui))}';
  }

  Widget actionIcon(
    String label,
    IconData icon,
    VoidCallback? action, {
    Color color = amber,
  }) => IconButton(
    tooltip: label,
    onPressed: action,
    icon: Icon(icon, color: color, size: 21),
  );

  Widget upgradeRow(
    UpgradeChoice option,
    UpgradePlanner p, {
    int count = 1,
    bool compact = false,
  }) {
    final item = option.item;
    final level = option.level;
    final active = item.upgrading;
    final costs = level == null ? <String, num>{} : p.costs(item, level);
    return CitadelPanel(
      color: active ? resourceColor(item) : null,
      padding: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              itemImage(item, size: 48),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      catalogue.name(item),
                      style: const TextStyle(
                        fontFamily: 'SpaceGrotesk',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${item.level == 0 ? 'New' : 'Lv ${item.level}'}${level != null && !option.maxed ? ' → ${item.targetLevel ?? item.level + 1}' : ''}${count > 1 ? '  ×$count' : ''}${option.maxed ? ' · Max' : ''}',
                      style: const TextStyle(fontSize: 10, color: muted),
                    ),
                    if (costs.isNotEmpty && !option.maxed)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Wrap(
                          spacing: 7,
                          runSpacing: 4,
                          children: [
                            for (final c in costs.entries)
                              amount(c.key, c.value),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (busy == item.key)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (active) ...[
                actionIcon(
                  'Complete ${catalogue.name(item)}',
                  Icons.check_circle_outline,
                  () => rowAction(item.key, () => store.complete(item)),
                  color: readyGreen,
                ),
                actionIcon(
                  'Cancel ${catalogue.name(item)}',
                  Icons.close_rounded,
                  () => rowAction(item.key, () => store.cancel(item)),
                  color: muted,
                ),
              ] else if (option.eligible)
                actionIcon(
                  '${option.missing ? 'Build' : 'Upgrade'} ${catalogue.name(item)}',
                  option.missing
                      ? Icons.add_home_work_outlined
                      : Icons.upgrade_rounded,
                  () =>
                      rowAction(item.key, () => store.start(option, catalogue)),
                )
              else
                Tooltip(
                  message: option.lockReason ?? 'Unavailable',
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(
                      option.maxed
                          ? Icons.verified_outlined
                          : Icons.lock_outline,
                      color: muted,
                      size: 18,
                    ),
                  ),
                ),
            ],
          ),
          if (active) ...[
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 14,
              runSpacing: 5,
              children: [
                countdown(item),
                Tooltip(
                  message: 'Completion time',
                  child: Text(
                    finishLabel(item.finishesAt!),
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ),
              ],
            ),
            liveProgress(item),
          ] else if (level != null && !option.maxed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded, size: 13, color: muted),
                  const SizedBox(width: 5),
                  Text(
                    timeLabel({...level, 'seconds': p.duration(item, level)}),
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                  if (p.discount(item) > 0)
                    Text(
                      ' · −${p.discount(item)}%',
                      style: const TextStyle(fontSize: 10, color: readyGreen),
                    ),
                  if (!option.eligible) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        option.lockReason ?? '',
                        style: const TextStyle(color: muted, fontSize: 10),
                      ),
                    ),
                  ],
                ],
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

  Widget recommendationsPage(BuildContext context) {
    final v = store.selected;
    if (v == null) return emptyVillage();
    final p = planner(v);
    final next = p.recommendations;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Next upgrades',
                style: TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Tooltip(
              message:
                  'App priority: offense and prerequisites, research/heroes, economy, defenses, then walls. Current Town Hall and completed prerequisites only; balances are unknown.',
              child: const Icon(Icons.info_outline, size: 18, color: muted),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (next.isEmpty)
          const CitadelPanel(
            child: Text('No eligible upgrades', style: TextStyle(color: muted)),
          ),
        for (var n = 0; n < next.length; n++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (n == 0)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: CitadelLabel('Next best'),
                  ),
                upgradeRow(next[n], p),
              ],
            ),
          ),
      ],
    );
  }

  Widget armiesPage(BuildContext context) {
    final v = store.selected;
    if (v == null) return emptyVillage();
    return FutureBuilder<List<SourcedArmy>>(
      future: armyCatalogue,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(
            child: snapshot.hasError
                ? const Text('Armies unavailable')
                : const CircularProgressIndicator(),
          );
        }
        final plans = snapshot.data!
            .where(
              (a) =>
                  a.townHall == v.townHall &&
                  (armyType == 'All' || a.type == armyType),
            )
            .toList();
        return ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final type in ['All', 'Air', 'Ground', 'Hybrid'])
                  ChoiceChip(
                    label: Tooltip(
                      message: type,
                      child: Icon(
                        type == 'All'
                            ? Icons.grid_view_rounded
                            : type == 'Air'
                            ? Icons.air_rounded
                            : type == 'Ground'
                            ? Icons.terrain_rounded
                            : Icons.merge_type_rounded,
                        size: 18,
                        color: armyType == type ? Colors.black : muted,
                      ),
                    ),
                    selected: armyType == type,
                    onSelected: (_) => setState(() => armyType = type),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            for (final plan in plans)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: armyCard(plan),
              ),
            if (plans.isEmpty)
              const CitadelPanel(
                child: Text(
                  'No verified compositions',
                  style: TextStyle(color: muted),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget armyCard(SourcedArmy plan) => CitadelPanel(
    color: elixir,
    padding: 12,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                plan.title,
                style: const TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ),
            actionIcon(
              'Source: Clash Armies',
              Icons.open_in_new,
              () => act(() => open(plan.source)),
              color: muted,
            ),
            actionIcon(
              'Copy composition',
              Icons.copy_rounded,
              () => act(() async {
                await Clipboard.setData(
                  ClipboardData(text: plan.clipboardText),
                );
                message('Copied');
              }),
            ),
          ],
        ),
        CitadelLabel(plan.type, color: elixir),
        const SizedBox(height: 12),
        armyUnits(plan.troops, plan.artwork),
        if (plan.spells.isNotEmpty) ...[
          const Divider(height: 20),
          armyUnits(plan.spells, plan.artwork),
        ],
        if (plan.heroes.isNotEmpty) ...[
          const Divider(height: 20),
          armyUnits(
            {for (final name in plan.heroes) name: 1},
            plan.artwork,
            heroes: true,
          ),
        ],
      ],
    ),
  );

  Widget armyUnits(
    Map<String, int> units,
    Map<String, String> artwork, {
    bool heroes = false,
  }) => Wrap(
    spacing: 8,
    runSpacing: 10,
    children: [
      for (final entry in units.entries)
        SizedBox(
          width: 64,
          child: Column(
            children: [
              Tooltip(
                message: entry.key,
                child: Stack(
                  children: [
                    armyUnitImage(entry.key, artwork),
                    if (!heroes)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: amber,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            '×${entry.value}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.black,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                entry.key,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 9, color: muted),
              ),
            ],
          ),
        ),
    ],
  );

  Widget armyUnitImage(String name, Map<String, String> artwork) {
    final path = artwork[normaliseArmyName(name)];
    return Container(
      width: 54,
      height: 54,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xff0b111e),
        borderRadius: BorderRadius.circular(9),
      ),
      child: path == null
          ? const Icon(Icons.help_outline, color: muted)
          : Image.asset(path, fit: BoxFit.contain),
    );
  }

  Widget profilesPage(BuildContext context) => ListView(
    padding: const EdgeInsets.all(14),
    children: [
      for (final v in store.villages)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: CitadelPanel(
            color: v == store.selected ? amber : null,
            padding: 12,
            child: Column(
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
                      size: 54,
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
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${v.tag} · TH${v.townHall}',
                            style: const TextStyle(fontSize: 11, color: muted),
                          ),
                        ],
                      ),
                    ),
                    if (v == store.selected)
                      const Icon(
                        Icons.check_circle_outline,
                        color: readyGreen,
                        size: 19,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${v.active.length} upgrades · ${dateLabel(v.exportedAt)}',
                        style: const TextStyle(fontSize: 10, color: muted),
                      ),
                    ),
                    actionIcon(
                      'Select ${v.name}',
                      Icons.swap_horiz,
                      () => act(() async {
                        store.selectedTag = v.tag;
                        await store.save();
                        setState(() => page = 0);
                      }),
                    ),
                    actionIcon(
                      'Rename ${v.name}',
                      Icons.edit_outlined,
                      () => act(() async {
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
                      color: muted,
                    ),
                    actionIcon(
                      'Remove ${v.name}',
                      Icons.delete_outline,
                      () => act(() async {
                        if (await confirmIn(
                          ui,
                          'Remove ${v.name}?',
                          'This removes the local profile. Export a backup to keep it.',
                        )) {
                          store.villages.remove(v);
                          await store.save();
                        }
                      }),
                      color: muted,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      Center(
        child: actionIcon(
          'Import another village',
          Icons.add_circle_outline,
          importVillage,
        ),
      ),
    ],
  );

  Widget settings(BuildContext context) {
    final v = store.selected;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        if (v != null) ...[
          CitadelPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: CitadelLabel('Gold Pass')),
                    actionIcon(
                      'Boosts affect new estimates only',
                      Icons.info_outline,
                      () => act(
                        () => open(
                          'https://sc-clashofclans.zendesk.com/hc/en-us/articles/49529123544091-Gold-Pass',
                        ),
                      ),
                      color: muted,
                    ),
                  ],
                ),
                boostSelector(
                  'Builder',
                  v.builderDiscount,
                  (n) => act(() async {
                    v.builderDiscount = n;
                    await store.save();
                  }),
                ),
                boostSelector(
                  'Research',
                  v.researchDiscount,
                  (n) => act(() async {
                    v.researchDiscount = n;
                    await store.save();
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        CitadelPanel(
          child: Row(
            children: [
              const Expanded(child: CitadelLabel('Theme')),
              for (final pair in [
                ('citadel', 'Dark Citadel', Color(0xff181e2c)),
                ('onyx', 'Onyx Black', Color(0xff000000)),
                ('purple', 'Midnight Purple', Color(0xff442762)),
              ])
                Tooltip(
                  message: pair.$2,
                  child: IconButton(
                    isSelected: store.theme == pair.$1,
                    onPressed: () => act(() async {
                      store.theme = pair.$1;
                      await store.save();
                    }),
                    icon: Icon(Icons.circle, color: pair.$3),
                    selectedIcon: Icon(
                      Icons.check_circle,
                      color: pair.$3 == const Color(0xff000000) ? muted : amber,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        CitadelPanel(
          padding: 12,
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Reminders',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  '24h · every 3h',
                  style: TextStyle(fontSize: 10, color: muted),
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
              Row(
                children: [
                  const Icon(Icons.bedtime_outlined, color: elixir, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${hourLabel(store.quietStart)} – ${hourLabel(store.quietEnd)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  actionIcon(
                    'Quiet hours',
                    Icons.edit_outlined,
                    quietHours,
                    color: muted,
                  ),
                ],
              ),
              if (onAndroid)
                FutureBuilder<Map<String, dynamic>>(
                  future: store.deviceStatus(),
                  builder: (context, snapshot) {
                    final status = snapshot.data ?? {};
                    return Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Permissions',
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        ),
                        actionIcon(
                          'Usage access${status['usageAccess'] == true ? ' · granted' : ''}',
                          Icons.query_stats,
                          () => act(() => store.deviceAction('usageSettings')),
                          color: status['usageAccess'] == true
                              ? readyGreen
                              : amber,
                        ),
                        actionIcon(
                          'Notifications${status['notifications'] == true ? ' · allowed' : ''}',
                          Icons.notifications_outlined,
                          () => act(
                            () => store.deviceAction('notificationSettings'),
                          ),
                          color: status['notifications'] == true
                              ? readyGreen
                              : amber,
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        CitadelPanel(
          child: Wrap(
            alignment: WrapAlignment.spaceEvenly,
            spacing: 12,
            children: [
              actionIcon(
                'Export backup',
                Icons.download_outlined,
                exportBackup,
              ),
              actionIcon(
                'Restore backup',
                Icons.restore_rounded,
                restoreBackup,
              ),
              actionIcon(
                'Refresh catalogue · ${catalogue.updatedAt.split('T').first}',
                Icons.cloud_download_outlined,
                refreshing
                    ? null
                    : () => act(() async {
                        setState(() => refreshing = true);
                        try {
                          final next = await refreshCatalogue(store.prefs);
                          if (mounted) setState(() => catalogue = next);
                          message('Updated');
                        } finally {
                          if (mounted) setState(() => refreshing = false);
                        }
                      }),
              ),
              actionIcon('Official news', Icons.newspaper_outlined, newsPanel),
              actionIcon(
                'Source & releases',
                Icons.code,
                () => act(
                  () => open('https://github.com/saimadhav10/COCTracker'),
                ),
              ),
              actionIcon('About & credits', Icons.info_outline, about),
              if (onAndroid)
                actionIcon(
                  'Open Clash of Clans',
                  Icons.sports_esports_outlined,
                  () => act(() => store.deviceAction('openClash')),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        CitadelPanel(
          color: amber,
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CitadelLabel('About the Creator'),
                    SizedBox(height: 8),
                    Text(
                      '@saimadhav10',
                      style: TextStyle(
                        fontFamily: 'SpaceGrotesk',
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
              ),
              actionIcon(
                'Creator on GitHub',
                Icons.open_in_new,
                () => act(() => open('https://github.com/saimadhav10')),
              ),
            ],
          ),
        ),
        if (store.platformError != null)
          Text(
            store.platformError!,
            style: const TextStyle(color: amber, fontSize: 11),
          ),
        const SizedBox(height: 20),
        const Text(
          'COCTracker 3.0.0',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, color: muted),
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
              title('Official news'),
              OutlinedButton(
                onPressed: () => act(() => open(newsUrl)),
                child: const Tooltip(
                  message: 'Open official blog',
                  child: Icon(Icons.open_in_new),
                ),
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
                      child: Text('News unavailable'),
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
                    const Text('Paste Export Data JSON from Clash settings.'),
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
                child: const Tooltip(
                  message: 'Cancel',
                  child: Icon(Icons.close_rounded),
                ),
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
                    message('Imported');
                  } catch (e) {
                    update(
                      () => error = e.toString().replaceFirst(
                        'FormatException: ',
                        '',
                      ),
                    );
                  }
                },
                child: const Tooltip(
                  message: 'Import',
                  child: Icon(Icons.file_download_outlined),
                ),
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
              child: const Tooltip(
                message: 'Cancel',
                child: Icon(Icons.close_rounded),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Tooltip(
                message: 'Continue',
                child: Icon(Icons.check_rounded),
              ),
            ),
          ],
        ),
      ) ??
      false;

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
            child: const Tooltip(
              message: 'Cancel',
              child: Icon(Icons.close_rounded),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Tooltip(
              message: 'Save',
              child: Icon(Icons.check_rounded),
            ),
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
        content: const Text('All profiles and timers.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Tooltip(
              message: 'Close',
              child: Icon(Icons.close_rounded),
            ),
          ),
          TextButton(
            onPressed: () => act(() async {
              await Clipboard.setData(ClipboardData(text: text));
              message('Backup copied.');
            }),
            child: const Tooltip(
              message: 'Copy JSON',
              child: Icon(Icons.copy_rounded),
            ),
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
              child: const Tooltip(
                message: 'Save file',
                child: Icon(Icons.save_alt_rounded),
              ),
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
                  'Restoring replaces all local profiles and preferences.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: text,
                  minLines: 4,
                  maxLines: 7,
                  decoration: const InputDecoration(labelText: 'Backup JSON'),
                ),
                if (onAndroid)
                  IconButton(
                    tooltip: 'Choose file',
                    onPressed: () => act(() async {
                      final result = await TrackerStore.channel
                          .invokeMethod<String>('readBackup');
                      if (result != null) text.text = result;
                    }),
                    icon: const Icon(Icons.folder_open),
                  ),
                if (error != null) Text(error!),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Tooltip(
                message: 'Cancel',
                child: Icon(Icons.close_rounded),
              ),
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
              child: const Tooltip(
                message: 'Restore',
                child: Icon(Icons.restore_rounded),
              ),
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
        child: const Tooltip(
          message: 'Export original data',
          child: Icon(Icons.download_outlined),
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: restoreBackup,
        child: const Tooltip(
          message: 'Restore a valid backup',
          child: Icon(Icons.restore_rounded),
        ),
      ),
    ],
  );
  void about() => managedDialog<void>(
    context: ui,
    builder: (context) => AlertDialog(
      title: const Text('Built for your village'),
      content: const SingleChildScrollView(
        child: Text(
          'COCTracker is a free, unofficial fan app by @saimadhav10.\n\nThis material is unofficial and is not endorsed by Supercell. For more information see Supercell’s Fan Content Policy: supercell.com/en/fan-content-policy\n\nGame artwork belongs to Supercell. Official currency icons: Supercell Fan Kit. Catalogue and additional game artwork packaging: chiefpansancolt/clash-of-clans-data, MIT License (Christopher Pezza, 2026). Fonts: Space Grotesk and Plus Jakarta Sans, SIL Open Font License.\n\nProfiles are stored on your device. Network requests fetch the public game catalogue and official news; your village JSON is not uploaded. Android Usage Access is used locally for Clash reminders.\n\nUpgrade values are community-maintained base values. Gold Pass durations are estimates; imported finish times are preserved. Army compositions are sourced from Clash Armies and preserved without invented slots, levels or performance statistics. Recommendations use app planning rules. Verify current game values in Clash.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              showLicensePage(context: context, applicationName: 'COCTracker'),
          child: const Tooltip(
            message: 'Licenses',
            child: Icon(Icons.description_outlined),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Tooltip(
            message: 'Close',
            child: Icon(Icons.close_rounded),
          ),
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
