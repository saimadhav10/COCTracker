# COCTracker 3.0

Android-first Flutter app with local profiles keyed by normalized player tag. No backend, sign-in, or cloud backup. Existing schema 1 profile backups and schema 2 catalogue caches remain compatible.

`lib/domain/village.dart` validates Home Village game JSON, expands grouped instances, retains unknown fields, and anchors imported timers to the export timestamp. New imports replace the matching profile after confirmation; older exports warn. Expiry never changes a level automatically.

`lib/domain/upgrades.dart` derives missing building slots, current-TH eligibility, completed prerequisites, storage capacity, costs and discounted duration estimates. Merged defenses retain consumed source instances for cancellation. Special crafting, supercharge and weapon-merge semantics are not guessed.

`lib/services/tracker_store.dart` persists profiles and settings, validates backups and configures native reminders. Per-profile Gold Pass settings affect new estimates, not imported finish times. Corrupt data is retained for recovery.

`lib/domain/sourced_armies.dart` loads the bundled source compositions and exact unit artwork. Rows contain only TH, source attack-type label, source ID, title, troop counts, spell counts and explicitly listed heroes. No composition generator remains. Public cards were checked on 29 October 2026. `tool/audit_armies.py` checks source transcription fingerprints and mapped TH requirements; rejected entries are recorded in `docs/army-source-audit.json`. There are at most two entries per attack type and TH; absent slots are left empty.

`lib/app.dart` provides six icon-navigation tabs: Home, Upgrades, Armies, Recommendations, Profiles and Settings. Home retains overall/category percentages and active builders/lab/pet timers. It omits raw level-step counts, resource totals and guide prose. Actions use icons with tooltips. A one-second notifier updates countdowns from absolute finish times; completion dates use device-local date/time formatting. Imported timers without a known start do not invent elapsed percentages. Three dark palettes share low-opacity accent borders.

Recommendations select distinct eligible upgrade types using the documented offense/prerequisite-first planning rule. They are app suggestions, not game rankings or affordability claims. Upgrade search, category/sort controls, locked/maxed toggles, inline start/complete/cancel, all profile operations, backups, reminders and official news remain available.

`lib/services/game_updates.dart` retrieves this repository's maintained catalogue and the official Supercell blog. It does not upload profile JSON. Army compositions are bundled for offline use; they do not silently change with live web pages.

Android ReminderEngine uses opt-in Usage Access for launches of `com.supercell.clashofclans`. After 24 hours it reminds no more frequently than every three hours outside quiet hours. Inexact AlarmManager checks and battery restrictions can delay alerts. Upgrade reminders ask for fresh imports. Tapping opens Clash; there are no forced launches. Reboot/app replacement restores scheduling. Monitoring is per device, not per profile.

Signed releases reuse the original private key. Split ABI APKs, small WebP assets and tree-shaken icons limit download size. Android adaptive and legacy launcher icons, the web favicon and README all use the original tracker emblem.
