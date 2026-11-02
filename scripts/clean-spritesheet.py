import os
from PIL import Image, ImageDraw
import numpy as np

# Resolve path to pandagirlassets.png
base_dir = '/Users/admin/Library/CloudStorage/OneDrive-lovenhu/Code/Antigravity/titroutine'
orig_path = os.path.join(base_dir, 'pandagirlassets.png')

print(f'Loading original spritesheet from {orig_path}...')
im = Image.open(orig_path).convert('RGBA')
bg_color = np.array([18, 22, 29])

sheet_w = 8 * 256
sheet_h = 9 * 256
sheet = Image.new('RGBA', (sheet_w, sheet_h), (0, 0, 0, 0))

# Mappings: (name, cell_w, cell_h, [(y_start, x_offset)])
specs = {
    0: ('idle', 128, 128, [(40, 424)]),
    1: ('working_laptop', 128, 128, [(296, 0), (424, 0)]),
    2: ('working_reading', 128, 128, [(296, 512), (424, 512)]),
    3: ('done', 96, 128, [(590, 384), (718, 384)]),
    4: ('celebrate', 96, 128, [(590, 768), (718, 768)]),
    5: ('sleepy', 96, 128, [(590, 1152), (718, 1152)]),
    6: ('waiting', 96, 128, [(590, 0), (718, 0)]),
    7: ('levelup', 96, 128, [(860, 0)]),
    8: ('working_writing', 128, 128, [(296, 1024), (424, 1024)])
}

for state, (name, cw, ch, rows) in specs.items():
    print(f'Processing animation {name} (state {state})...')
    frames = []
    
    # Exclude outer cell borders and labels
    if cw == 128:
        ix_start, ix_end = 20, 108
        iy_start, iy_end = 24, 112
    else:
        ix_start, ix_end = 12, 84
        iy_start, iy_end = 24, 112
        
    for r_idx, (y_start, x_offset) in enumerate(rows):
        cols_in_row = 8 if len(rows) == 1 else 4
        if name == 'levelup':
            cols_in_row = 6
            
        for c_idx in range(cols_in_row):
            x = x_offset + c_idx * cw
            y = y_start
            
            # Crop the inner region
            cell = im.crop((x + ix_start, y + iy_start, x + ix_end, y + iy_end))
            ccw, cch = cell.size
            
            cell_arr = np.array(cell).astype(int)
            
            # Sample background color dynamically from top-left corner
            sampled_bg = cell_arr[0, 0, :3]
            c_dist = np.sqrt(np.sum((cell_arr[:, :, :3] - sampled_bg)**2, axis=2))
            
            # Make background transparent
            cell_arr[c_dist <= 25, 3] = 0
            
            # Find largest component (the character) to discard borders/text residuals
            alpha = cell_arr[:, :, 3]
            binary_mask = np.where(alpha > 0, 255, 0).astype(np.uint8)
            mask_im = Image.fromarray(binary_mask)
            
            mask_copy = mask_im.copy()
            largest_size = 0
            largest_xy = None
            
            for cy in range(cch):
                for cx in range(ccw):
                    if mask_copy.getpixel((cx, cy)) == 255:
                        temp_fill = mask_copy.copy()
                        ImageDraw.floodfill(temp_fill, (cx, cy), 128)
                        arr_temp = np.array(temp_fill)
                        size = np.sum(arr_temp == 128)
                        if size > largest_size:
                            largest_size = size
                            largest_xy = (cx, cy)
                        ImageDraw.floodfill(mask_copy, (cx, cy), 0)
            
            if largest_xy is not None:
                fill_im = mask_im.copy()
                ImageDraw.floodfill(fill_im, largest_xy, 128)
                arr_fill = np.array(fill_im)
                cell_arr[arr_fill != 128, 3] = 0
            else:
                cell_arr[:, :, 3] = 0
                
            cleaned_cell = Image.fromarray(cell_arr.astype(np.uint8))
            
            # Center the cell inside a 256x256 frame
            frame = Image.new('RGBA', (256, 256), (0, 0, 0, 0))
            paste_x = (256 - ccw) // 2
            paste_y = (256 - cch) // 2
            frame.paste(cleaned_cell, (paste_x, paste_y))
            frames.append(frame)
            
    if name == 'levelup':
        while len(frames) < 8:
            frames.append(frames[-1].copy())
            
    for f_idx, frame in enumerate(frames):
        sheet.paste(frame, (f_idx * 256, state * 256))

out_path = '/Users/admin/.agentpet/pets/pandagirl/spritesheet.png'
os.makedirs(os.path.dirname(out_path), exist_ok=True)
sheet.save(out_path)
print(f'Successfully compiled cleaned spritesheet to {out_path}')
