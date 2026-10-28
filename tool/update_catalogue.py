"""Build an attributed, offline catalogue from an upstream checkout.

Usage: python tool/update_catalogue.py /path/to/clash-of-clans-data
The input must be the chiefpansancolt/clash-of-clans-data repository.
"""
import json
import pathlib
import shutil
import subprocess
import sys
from datetime import datetime, timezone

root = pathlib.Path(__file__).resolve().parents[1]
upstream = pathlib.Path(sys.argv[1]).resolve()
home = upstream / 'data/home'
rows = [json.loads(p.read_text(encoding='utf-8')) for p in sorted(home.rglob('*.json'))]
by_slug = {r['id']: r for r in rows}
output = root / 'assets/catalogue'
output.mkdir(parents=True, exist_ok=True)
images = root / 'assets/icons'
images.mkdir(parents=True, exist_ok=True)

def requirement(building, level):
    for row in by_slug.get(building, {}).get('levels', []):
        if row.get('level') == level:
            return row.get('townHallRequired', 999)
    return 999

def seconds(time):
    if not isinstance(time, dict):
        return None
    return sum(time.get(k, 0) * n for k, n in [('days', 86400), ('hours', 3600), ('minutes', 60), ('seconds', 1)])

entries = {}
for row in rows:
    data = row.get('dataId')
    if not isinstance(data, int):
        continue
    levels = []
    for level in row.get('levels', []):
        number = level.get('level')
        if not isinstance(number, int):
            continue
        th = level.get('townHallRequired')
        if row['id'] == 'town-hall':
            th = number
        if th is None:
            for key, building in [('heroHallLevelRequired', 'hero-hall'), ('blacksmithLevelRequired', 'blacksmith'), ('petHouseLevelRequired', 'pet-house'), ('laboratoryRequired', 'laboratory')]:
                if key in level:
                    th = requirement(building, level[key])
                    break
        cost = level.get('buildCost', level.get('researchCost', level.get('upgradeCost')))
        resource = level.get('buildCostResource', level.get('researchCostResource', level.get('upgradeCostResource')))
        ores = {ore: level[key] for ore, key in [('Shiny ore', 'upgradeShinyOre'), ('Glowing ore', 'upgradeGlowingOre'), ('Starry ore', 'upgradeStarryOre')] if level.get(key)}
        levels.append({'level': number, 'townHall': th or 999, 'cost': cost, 'resource': resource,
                       'seconds': seconds(level.get('buildTime', level.get('researchTime', level.get('upgradeTime')))),
                       'ores': ores, 'requirements': {k: v for k, v in level.items() if 'Required' in k},
                       'stats': {k: v for k, v in level.items() if k in ['hitpoints', 'damagePerSecond', 'stats', 'storageCapacity']}})
    top_images = row.get('images', {})
    icon = top_images.get('icon') if isinstance(top_images, dict) else None
    if not icon:
        for level in reversed(row.get('levels', [])):
            choices = level.get('images', {})
            if not isinstance(choices, dict):
                continue
            icon = choices.get('normal') or next(iter(choices.values()), None)
            if isinstance(icon, str):
                break
    icon_path = None
    if isinstance(icon, str) and (upstream / icon).is_file():
        target = images / f'{data}{pathlib.Path(icon).suffix}'
        shutil.copyfile(upstream / icon, target)
        icon_path = target.relative_to(root).as_posix()
    entries[str(data)] = {'name': row['name'], 'slug': row['id'], 'category': row.get('category'),
                          'description': row.get('description', ''), 'image': icon_path, 'levels': levels}
    if row['id'] == 'town-hall':
        for level in row.get('levels', []):
            path = level.get('images', {}).get('normal')
            if path and (upstream / path).is_file():
                shutil.copyfile(upstream / path, images / f'townhall_{level["level"]}.png')

commit = subprocess.check_output(['git', '-C', str(upstream), 'rev-parse', 'HEAD'], text=True).strip()
catalogue = {'schema': 1, 'updatedAt': datetime.now(timezone.utc).isoformat(),
             'source': 'https://github.com/chiefpansancolt/clash-of-clans-data',
             'revision': commit, 'entries': entries}
(output / 'home.json').write_text(json.dumps(catalogue, separators=(',', ':')), encoding='utf-8')
shutil.copyfile(upstream / 'LICENSE', output / 'UPSTREAM_LICENSE.txt')
print(f'Wrote {len(entries)} entities, {sum(len(e["levels"]) for e in entries.values())} upgrade levels, and {len(list(images.iterdir()))} icons. Source {commit}')
