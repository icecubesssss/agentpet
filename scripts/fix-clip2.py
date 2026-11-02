"""Fix spritesheet Row 1 — final approach.

Root cause: workingwithtask_clean.png has tiny stray pixels (remnants of
number labels) that survive the label-removal heuristic. The SpriteSlicer
finds these as 1px-wide "frames", causing black flashes.

Fix: After pasting each frame into its 256×256 cell, flood-fill from edges
to find all disconnected small blobs and remove them. Only keep the largest
connected component (the actual character).
"""
from PIL import Image
import numpy as np
from scipy import ndimage

CELL = 256
ROW_IDX = 1
NUM_COLS = 8

src_path = '/Users/admin/Library/CloudStorage/OneDrive-lovenhu/Code/Antigravity/titroutine/apps/web/public/assets/workingwithtask_clean.png'
sheet_path = '/Users/admin/.agentpet/pets/pandagirl/spritesheet.png'

src = Image.open(src_path).convert('RGBA')
sw, sh = src.size
src_cols, src_rows = 5, 2
frame_w = sw // src_cols
frame_h = sh // src_rows
print(f'Source: {sw}×{sh}, frame cell: {frame_w}×{frame_h}')

frames = []
for r in range(src_rows):
    for c in range(src_cols):
        x0 = c * frame_w
        y0 = r * frame_h
        cell = src.crop((x0, y0, x0 + frame_w, y0 + frame_h))
        arr = np.array(cell)
        
        # Create binary mask of opaque pixels
        mask = arr[:, :, 3] > 16
        
        # Label connected components
        labeled, num_features = ndimage.label(mask)
        if num_features == 0:
            continue
        
        # Find the largest component (the character)
        component_sizes = ndimage.sum(mask, labeled, range(1, num_features + 1))
        largest_label = np.argmax(component_sizes) + 1
        
        # Keep only the largest component
        arr[labeled != largest_label, 3] = 0
        
        cell = Image.fromarray(arr)
        bbox = cell.getbbox()
        if not bbox:
            continue
        cell = cell.crop(bbox)
        
        # Fit into CELL×CELL
        cw, ch = cell.size
        scale = min(CELL / cw, CELL / ch)
        new_w = max(1, int(cw * scale))
        new_h = max(1, int(ch * scale))
        cell = cell.resize((new_w, new_h), Image.LANCZOS)
        
        # Center on transparent canvas
        frame = Image.new('RGBA', (CELL, CELL), (0, 0, 0, 0))
        paste_x = (CELL - new_w) // 2
        paste_y = (CELL - new_h) // 2
        frame.paste(cell, (paste_x, paste_y), cell)
        
        # Clear 2px gutter on all edges
        farr = np.array(frame)
        farr[:2, :, 3] = 0
        farr[-2:, :, 3] = 0
        farr[:, :2, 3] = 0
        farr[:, -2:, 3] = 0
        frame = Image.fromarray(farr)
        
        frames.append(frame)
        print(f'  Frame {len(frames)-1}: {new_w}×{new_h} (from src [{r},{c}])')

print(f'Extracted {len(frames)} clean frames')

frames = frames[:NUM_COLS]
while len(frames) < NUM_COLS:
    frames.append(frames[-1].copy())

# Load spritesheet and replace row
sheet = Image.open(sheet_path).convert('RGBA')
y_offset = ROW_IDX * CELL

# Clear entire row
clear_row = Image.new('RGBA', (sheet.width, CELL), (0, 0, 0, 0))
sheet.paste(clear_row, (0, y_offset))

for i, frame in enumerate(frames):
    x_offset = i * CELL
    sheet.paste(frame, (x_offset, y_offset), frame)

sheet.save(sheet_path)
print(f'✅ Saved')

# Verify
arr = np.array(sheet.crop((0, y_offset, sheet.width, y_offset + CELL)))
col_has = np.any(arr[:, :, 3] > 16, axis=0)
segments = []
start = None
for i in range(arr.shape[1]):
    if col_has[i] and start is None:
        start = i
    elif not col_has[i] and start is not None:
        segments.append((start, i))
        start = None
if start is not None:
    segments.append((start, arr.shape[1]))
print(f'\nVerification: Slicer detects {len(segments)} frames:')
for idx, (s, e) in enumerate(segments):
    w = e - s
    if w < 10:
        print(f'  ⚠️  Frame {idx}: x=[{s},{e}) width={w}px — STRAY PIXEL!')
    else:
        print(f'  ✅ Frame {idx}: x=[{s},{e}) width={w}px')
