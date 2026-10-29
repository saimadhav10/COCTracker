"""Prepare small, attributed army artwork from the catalogue's upstream checkout."""
import json
from pathlib import Path
import sys
from PIL import Image

root=Path(__file__).resolve().parents[1]
upstream=Path(sys.argv[1]).resolve()
units={}
for path in (upstream/'data/home').rglob('*.json'):
    row=json.loads(path.read_text(encoding='utf8'))
    if row.get('category') not in ['troop','spell','hero']:
        continue
    image=root/f"assets/icons/{row.get('dataId')}.webp"
    units[row['name']]={'image':image.relative_to(root).as_posix() if image.exists() else None}
    special=row.get('superTroop')
    if not isinstance(special,dict):
        continue
    icon=special.get('images',{}).get('icon')
    if not icon or not (upstream/icon).is_file():
        continue
    destination=root/f"assets/icons/{special['id']}.webp"
    with Image.open(upstream/icon) as original:
        image=original.convert('RGBA')
        image.thumbnail((128,128),Image.Resampling.LANCZOS)
        image.save(destination,'WEBP',quality=82,method=6)
    units[special['name']]={'image':destination.relative_to(root).as_posix()}
(root/'assets/catalogue/army_units.json').write_text(json.dumps(units,separators=(',',':')),encoding='utf8')
print('Prepared',len(units),'army unit images')
