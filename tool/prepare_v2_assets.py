"""Optimize bundled images and install attributed official Fan Kit resource icons."""
from pathlib import Path
from PIL import Image
import json

root = Path(__file__).resolve().parents[1]
icons = (root / 'assets/icons').resolve()
assert icons == root / 'assets/icons'
manifest = []
resources = {
    'gems': ('Icon_HV_Resource_Gem', 'u7pauwgAjgRLZUNKg3jT'),
    'gold': ('Icon_HV_Resource_Gold_1', '9YH5NnM3Ycxvi2wThWCt'),
    'elixir': ('Icon_HV_Resource_Elixir_1', 'BV54prjNWJCcjemWQH4G'),
    'dark_elixir': ('Icon_HV_Resource_Dark_Elixir_1', 'n6j4KEJdcJqJurrkvrtU'),
    'shiny_ore': ('Icon_HV_Resource_Shiny_Ore', 'vcy22P2s3SfB91tUm6HV'),
    'glowing_ore': ('Icon_HV_Resource_Glowy_Ore', '54BRhBgyLWvGDsg2UCsj'),
    'starry_ore': ('Icon_HV_Resource_Starry_Ore', 'zaS6mtw1tiftumPVcgPY'),
}
for name, (title, token) in resources.items():
    source = Path.home() / 'Downloads' / f'{token}.webp'
    if not source.is_file():
        raise SystemExit(f'Download {title} from the official Fan Kit before running this tool.')
    with Image.open(source) as image:
        image = image.convert('RGBA')
        bounds=image.getchannel('A').getbbox()
        if bounds:
            image=image.crop(bounds)
        image.thumbnail((64, 64), Image.Resampling.LANCZOS)
        image.save(icons / f'resource_{name}.webp', 'WEBP', quality=85, method=6)
    manifest.append({'name': title, 'asset': f'assets/icons/resource_{name}.webp',
      'source': 'https://fankit.supercell.com/d/vkEdmkUCngKw/game-assets',
      'imageUrl': f'https://media.ffycdn.net/eu/supercell/{token}.png?width=800'})
# Remove only superseded, tracked PNG copies, after their WebP equivalents exist.
for original in icons.glob('*.png'):
    if original.with_suffix('.webp').is_file():
        original.unlink()
(root / 'assets/catalogue/fankit_sources.json').write_text(json.dumps(manifest, indent=2))
print('Bundled image bytes:', sum(p.stat().st_size for p in icons.iterdir() if p.is_file()))
