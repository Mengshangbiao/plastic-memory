"""Assemble native screenshots using their measured capture timestamps."""
import json
from pathlib import Path

from PIL import Image
import numpy as np

folder = Path(__file__).resolve().parents[1] / 'build' / 'qa' / 'flow'
data = json.loads((folder / 'frames.json').read_text(encoding='utf-8'))
frames = [Image.open(folder / item['file']).convert('RGB') for item in data['frames']]
times = [item['ms'] for item in data['frames']] + [data['durationMs']]
durations = [max(10, times[i + 1] - times[i]) for i in range(len(frames))]
frames[0].save(folder / 'flow-preview.png', save_all=True,
               append_images=frames[1:], duration=durations, loop=0,
               disposal=0, blend=0)
meteor_indices = [i for i, item in enumerate(data['frames']) if item.get('meteors', 0) > 0]
if meteor_indices:
    first = max(0, meteor_indices[0] - 3)
    last = min(len(frames), meteor_indices[-1] + 5)
    frames[first].save(folder / 'meteor-preview.png', save_all=True,
                       append_images=frames[first + 1:last],
                       duration=durations[first:last], loop=0, disposal=0, blend=0)
    peak = max(meteor_indices, key=lambda i: data['frames'][i]['meteors'])
    frames[peak].save(folder / 'meteor-still.png')
for size in ('1280x800', '1920x1080'):
    image = Image.open(folder / f'home-{size}.png')
    image.convert('L').save(folder / f'home-{size}-grayscale.png')
metrics = {}
for name in ('home-1280x800', 'home-1920x1080', 'hover-library', 'hover-creation'):
    image = Image.open(folder / f'{name}.png').convert('RGB')
    rgb = np.asarray(image, dtype=np.float32) / 255
    maximum, minimum = rgb.max(axis=2), rgb.min(axis=2)
    saturation = (maximum - minimum) / np.maximum(maximum, 1 / 255)
    colored = (saturation > .15) & (maximum > .20)
    metrics[name] = {'pixels': list(image.size),
                     'coloredEmphasisPercent': round(float(colored.mean() * 100), 4)}
metrics['criterion'] = 'HSV saturation > 15% and value > 20%; faint near-black washes excluded'
(folder / 'visual-metrics.json').write_text(json.dumps(metrics, indent=2), encoding='utf-8')
print(json.dumps({'frames': len(frames), 'durationMs': sum(durations),
                  'preview': str(folder / 'flow-preview.png')}, ensure_ascii=False))
