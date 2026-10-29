"""Check bundled compositions against fingerprints recorded from source cards."""
from pathlib import Path
import json
import re

root=Path(__file__).resolve().parents[1]
audit=json.loads((root/'docs/army-source-audit.json').read_text(encoding='utf8'))
expected=dict(audit['fingerprints'])
rows=json.loads((root/'assets/catalogue/armies.json').read_text(encoding='utf8'))['armies']
catalogue=json.loads((root/'assets/catalogue/home.json').read_text(encoding='utf8'))['entries']
normalise=lambda text:re.sub(r'spell$','',re.sub('[^a-z0-9]','',text.lower()))
entries={normalise(e['name']):e for e in catalogue.values()}
seen=set()
for row in rows:
    assert row[2] not in seen, row[2]
    seen.add(row[2])
    facts=[row[0],row[1],row[2],sorted(row[4].items()),sorted(row[5].items()),sorted(row[6])]
    value=2166136261
    for char in json.dumps(facts,separators=(',',':'),ensure_ascii=False):
        value=((value^ord(char))*16777619)&0xffffffff
    assert value==expected[row[2]], f'Source transcription differs: {row[2]}'
    assert str(row[2]) not in audit['excluded'], f'Rejected source army bundled: {row[2]}'
    for name in [*row[4],*row[5],*row[6]]:
        entry=entries.get(normalise(name))
        if entry and entry['levels']:
            assert min(e['townHall'] for e in entry['levels'])<=row[0], f'{row[2]}: {name} is locked'
print(f'{len(rows)} source compositions match recorded troop, spell, and hero facts.')
