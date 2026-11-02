"""Debug: Simulate the SpriteSlicer alpha-gutter detection on Row 1
to see how many frames it detects and if any are blank/tiny."""
from PIL import Image
import numpy as np

CELL = 256
ROW_IDX = 1
ALPHA_THRESHOLD = 16

sheet = Image.open('/Users/admin/.agentpet/pets/pandagirl/spritesheet.png').convert('RGBA')
sw, sh = sheet.size
print(f'Sheet: {sw}×{sh}')

# Extract Row 1 band
row_y0 = ROW_IDX * CELL
row_y1 = (ROW_IDX + 1) * CELL
row_band = sheet.crop((0, row_y0, sw, row_y1))
arr = np.array(row_band)
h, w = arr.shape[:2]
print(f'Row 1 band: {w}×{h}')

# Check which pixel rows have content (alpha > threshold)
row_has = np.any(arr[:, :, 3] > ALPHA_THRESHOLD, axis=1)
print(f'Pixel rows with content: {np.sum(row_has)} / {h}')
print(f'  Content y-range: {np.argmax(row_has)} to {h - 1 - np.argmax(row_has[::-1])}')

# Check which pixel columns have content
col_has = np.any(arr[:, :, 3] > ALPHA_THRESHOLD, axis=0)
print(f'Pixel cols with content: {np.sum(col_has)} / {w}')

# Find column segments (transparent gaps = frame boundaries)
segments = []
start = None
for i in range(w):
    if col_has[i] and start is None:
        start = i
    elif not col_has[i] and start is not None:
        segments.append((start, i))
        start = None
if start is not None:
    segments.append((start, w))

print(f'\nDetected {len(segments)} frame columns:')
for idx, (s, e) in enumerate(segments):
    frame_w = e - s
    # Check if this frame has actual content or is mostly empty
    frame_region = arr[:, s:e, 3]
    content_pixels = np.sum(frame_region > ALPHA_THRESHOLD)
    total_pixels = frame_region.size
    print(f'  Frame {idx}: x=[{s},{e}) width={frame_w}px, content={content_pixels}/{total_pixels} ({100*content_pixels/total_pixels:.1f}%)')

# Also dump every 256px cell to see what's in each
print(f'\n--- Per 256px cell analysis ---')
for col in range(8):
    x0 = col * CELL
    x1 = x0 + CELL
    cell = arr[:, x0:x1, :]
    alpha = cell[:, :, 3]
    content_px = np.sum(alpha > ALPHA_THRESHOLD)
    total_px = alpha.size
    has_content = content_px > 0
    # Check for any white/near-white opaque pixels (potential background)
    if has_content:
        opaque = cell[alpha > ALPHA_THRESHOLD]
        avg_rgb = opaque[:, :3].mean(axis=0)
        print(f'  Cell {col}: {content_px} content px ({100*content_px/total_px:.1f}%), avg RGB=({avg_rgb[0]:.0f},{avg_rgb[1]:.0f},{avg_rgb[2]:.0f})')
    else:
        print(f'  Cell {col}: EMPTY')
