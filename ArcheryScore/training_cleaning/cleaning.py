import json
import os
import glob
import random
import numpy as np
import yaml
from PIL import Image

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ARCHIVE_DIR = os.path.join(BASE_DIR, 'archive')
NEW_DIR = os.path.join(BASE_DIR, 'new')
ANN_JSON = os.path.join(NEW_DIR, 'annotation.json')
OUT_BASE = os.path.join(BASE_DIR, 'yolo_data')


#archive has consistent image sizes whilew new folder images have different sizes
FALLBACK_BOX_FRAC = 0.12   # was 0.08 — larger box gives model more shaft context near tip
RANDOM_SEED = 42

def resize_and_copy(src, dst, max_size=1280):
    img = Image.open(src)
    if max(img.size) > max_size:
        img.thumbnail((max_size, max_size), Image.LANCZOS)
    img.save(dst)

#clamps everything to meet the YOLO normalization [0-1]
def clamp_bbox(cx, cy, bw, bh):
    bw = min(max(bw, 1e-4), 1.0)
    bh = min(max(bh, 1e-4), 1.0)
    cx = float(np.clip(cx, bw / 2, 1 - bw / 2))
    cy = float(np.clip(cy, bh / 2, 1 - bh / 2))
    return cx, cy, bw, bh


#the archive annotations has polygon instead of a rectangle
#takes the tightest rectangle that fits around the polygon
def bbox_from_polygon(points, img_w, img_h):
    pts = np.array(points)
    pts[:, 0] = np.clip(pts[:, 0], 0, img_w)
    pts[:, 1] = np.clip(pts[:, 1], 0, img_h)
    x_min, y_min = pts[:, 0].min(), pts[:, 1].min()
    x_max, y_max = pts[:, 0].max(), pts[:, 1].max()
    cx = (x_min + x_max) / 2 / img_w
    cy = (y_min + y_max) / 2 / img_h
    bw = (x_max - x_min) / img_w
    bh = (y_max - y_min) / img_h
    return cx, cy, bw, bh


def make_split(items):
    shuffled = list(items)
    random.seed(RANDOM_SEED)
    random.shuffle(shuffled)
    n      = len(shuffled)
    n_val  = max(1, int(0.10 * n))
    n_test = max(1, int(0.10 * n))
    val_set  = set(shuffled[n - n_val - n_test : n - n_test])
    test_set = set(shuffled[n - n_test:])
    def get_split(x):
        if x in val_set:  return 'val'
        if x in test_set: return 'test'
        return 'train'
    return get_split, val_set, test_set


#makes the directories to train
def make_dirs():
    for split in ('train', 'val', 'test'):
        os.makedirs(os.path.join(OUT_BASE, split, 'images'), exist_ok=True)
        os.makedirs(os.path.join(OUT_BASE, split, 'labels'), exist_ok=True)

#We do an 80/20 split (80% for train and 20% for eval+test)
def convert_archive():

    dirs = sorted([int(d) for d in os.listdir(ARCHIVE_DIR)
                   if os.path.isdir(os.path.join(ARCHIVE_DIR, d)) and d.isdigit()])
    
    get_split, val_folders, test_folders = make_split(dirs)

    annotated = 0
    background = 0

    for folder in dirs:
        split = get_split(folder)
        dir_path = os.path.join(ARCHIVE_DIR, str(folder))
        all_pngs = sorted(
            glob.glob(os.path.join(dir_path, '*.png')),
            key=lambda x: int(os.path.splitext(os.path.basename(x))[0])
        ) #get all images sorted based on their number

        for img_path in all_pngs:
            stem = os.path.splitext(os.path.basename(img_path))[0]
            json_path = os.path.join(dir_path, stem + '.json')
            dst_img = os.path.join(OUT_BASE, split, 'images', f'archive_{folder}_{stem}.png')
            dst_label = os.path.join(OUT_BASE, split, 'labels', f'archive_{folder}_{stem}.txt')

            if not os.path.exists(dst_img):
                resize_and_copy(img_path, dst_img)

            #each json already contains all arrows visible in that frame (cumulative by design)
            if os.path.exists(json_path):
                with open(json_path) as f:
                    d = json.load(f)
                img_w = d['imageWidth']
                img_h = d['imageHeight']
                impacts = [s for s in d['shapes'] if s['label'] == 'impact']

                if not impacts:
                    #the 00 pngs don't actually have any arrows, but I kept it to see if it would detect ghost arrows
                    open(dst_label, 'w').close()
                    background += 1
                else:
                    arrows = [s for s in d['shapes'] if s['label'] == 'arrow']
                    lines = []
                    for impact in impacts:
                        kp_x = float(np.clip(impact['points'][0][0] / img_w, 0, 1))
                        kp_y = float(np.clip(impact['points'][0][1] / img_h, 0, 1))
                        #use full arrow for training
                        #keypoint is at the tip/impact point
                        #match each impact to its arrow polygon by nearest centroid

                        if arrows:
                            impact_px = impact['points'][0]
                            matched = min(arrows, key=lambda a: (
                                (np.mean([p[0] for p in a['points']]) - impact_px[0]) ** 2 +
                                (np.mean([p[1] for p in a['points']]) - impact_px[1]) ** 2
                            ))
                            cx, cy, bw, bh = bbox_from_polygon(matched['points'], img_w, img_h)
                            cx, cy, bw, bh = clamp_bbox(cx, cy, bw, bh)
                        else:
                            cx, cy, bw, bh = clamp_bbox(kp_x, kp_y, FALLBACK_BOX_FRAC, FALLBACK_BOX_FRAC)
                        lines.append(f"0 {cx:.6f} {cy:.6f} {bw:.6f} {bh:.6f} {kp_x:.6f} {kp_y:.6f} 2")
                    with open(dst_label, 'w') as f:
                        f.write('\n'.join(lines) + '\n')
                    annotated += 1
            else:
                #no json means no arrows in this frame yet
                open(dst_label, 'w').close()
                background += 1

    print(f"  Folders : {len(dirs)}  (train {len(dirs)-len(val_folders)-len(test_folders)} / "
          f"val {len(val_folders)} / test {len(test_folders)})")
    print(f"  Labels  : {annotated} annotated, {background} background (empty target)")

def convert_new():
    with open(ANN_JSON) as f:
        data = json.load(f)

    records = {}
    for item in data:
        filename = item['file_upload'].split('-', 1)[1]  #"30ecd498-1.jpeg" → "1.jpeg"
        if not os.path.exists(os.path.join(NEW_DIR, filename)):
            continue
        keypoints = []
        for ann in item['annotations']:
            for r in ann['result']:
                if r['type'] != 'keypointlabels':
                    continue
                v = r['value']
                #normalize keypointlabels to [0-1] YOLO
                kp_x = float(np.clip(v['x'] / 100.0, 0.0, 1.0))
                kp_y = float(np.clip(v['y'] / 100.0, 0.0, 1.0))
                keypoints.append((kp_x, kp_y))
        records[filename] = keypoints #hash map of the file names and their keypoints to easily 
        #each tuple is a different arrow and keypoints are the pixel locations of the arrow tips


    all_filenames = sorted(records.keys(), key=lambda f: int(os.path.splitext(f)[0]))
    get_split, val_set, test_set = make_split(all_filenames)

    annotated = 0
    no_kp = 0 #in case like archive there's no arrows

    for filename, keypoints in records.items():
        split = get_split(filename)
        stem = os.path.splitext(filename)[0]
        src = os.path.abspath(os.path.join(NEW_DIR, filename))
        dst_img = os.path.join(OUT_BASE, split, 'images', f'new_{filename}')
        dst_lbl = os.path.join(OUT_BASE, split, 'labels', f'new_{stem}.txt')

        if not os.path.exists(dst_img):
            resize_and_copy(src, dst_img) #should be like yolo_data/split/images/new_1.jpeg

        if not keypoints:
            open(dst_lbl, 'w').close()
            no_kp += 1
            continue

        lines = []
        for (kp_x, kp_y) in keypoints:
            cx, cy, bw, bh = clamp_bbox(kp_x, kp_y, FALLBACK_BOX_FRAC, FALLBACK_BOX_FRAC)
            lines.append(f"0 {cx:.6f} {cy:.6f} {bw:.6f} {bh:.6f} {kp_x:.6f} {kp_y:.6f} 2")
        with open(dst_lbl, 'w') as f:
            f.write('\n'.join(lines) + '\n')
        annotated += 1

    print(f"  Images  : {len(records)}  (train {len(records)-len(val_set)-len(test_set)} / "
          f"val {len(val_set)} / test {len(test_set)})")
    print(f"  Labels  : {annotated} annotated, {no_kp} no keypoints")

def write_yaml():
    cfg = {
        'path':      '/content/drive/MyDrive/Archery/yolo_data', #this was just whatever I named the thing change as needed
        'train':     'train/images',
        'val':       'val/images',
        'test':      'test/images',
        'kpt_shape': [1, 3],
        'flip_idx':  [0],
        'nc':        1,
        'names':     ['arrow'],
    }
    path = os.path.join(OUT_BASE, 'dataset.yaml')
    with open(path, 'w') as f:
        yaml.dump(cfg, f, default_flow_style=False, sort_keys=False)
    return path

if __name__ == '__main__':
    make_dirs()
    convert_archive()
    convert_new()
    yaml_path = write_yaml()
    print(f"\nDataset YAML : {yaml_path}")
    #model is model=yolov8s-pose.pt with an image size of 1280x1280px
