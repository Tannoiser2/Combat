from PIL import Image, ImageDraw
import math, json

import sys
# Uso: python3 tools/classify_terrain.py [mappa.jpg] [x0] [y0]
# Origini (dal buildFile Vassal): farmhouse 72,106 - hill 73,109
#                                 village 77,110  - hedgerows 70,110
IMG = sys.argv[1] if len(sys.argv) > 1 else "assets/maps/hedgerows.jpg"
x0 = float(sys.argv[2]) if len(sys.argv) > 2 else 70.0
y0 = float(sys.argv[3]) if len(sys.argv) > 3 else 110.0
dx, dy = 156.30026487501547, 180.48
R = dx/1.5
img = Image.open(IMG).convert("RGB")
W, H = img.size
px = img.load()

def center(col, row):
    return (x0+(col-1)*dx, y0+(row+(0.5 if col%2==0 else 0.0))*dy)

def ring_pixels(cx, cy, r_in, r_out, step):
    vals = []
    for ix in range(int(cx-r_out), int(cx+r_out), step):
        for iy in range(int(cy-r_out), int(cy+r_out), step):
            if 0 <= ix < W and 0 <= iy < H:
                d2 = (ix-cx)**2+(iy-cy)**2
                if r_in*r_in <= d2 < r_out*r_out:
                    vals.append(px[ix, iy])
    return vals

def stats(vals):
    n = len(vals)
    r = sum(v[0] for v in vals)/n; g = sum(v[1] for v in vals)/n; b = sum(v[2] for v in vals)/n
    sd = math.sqrt(sum((v[0]-r)**2+(v[1]-g)**2+(v[2]-b)**2 for v in vals)/n)
    return r, g, b, sd

def darkinfo(vals):
    dark = [v for v in vals if v[0]+v[1]+v[2] < 290]
    if not dark:
        return 0.0, 0.0
    dn = len(dark)
    dgb = sum(v[1] for v in dark)/dn - sum(v[2] for v in dark)/dn
    return len(dark)/len(vals), dgb

def classify(col, row):
    cx, cy = center(col, row)
    core = ring_pixels(cx, cy, 0, R*0.30, 3)
    mid = ring_pixels(cx, cy, 0, R*0.45, 3)
    ring = ring_pixels(cx, cy, R*0.45, R*0.72, 4)
    r, g, b, sd = stats(mid)
    rr_, rg, rb, _ = stats(ring)
    gr = g - r; gb = g - b
    dfc, dgbc = darkinfo(core)
    dfr, dgbr = darkinfo(ring)
    if b >= 115 and gb < 25:
        return "STREAM" if r < 110 else "ROCKS"
    if r - g >= 10 and sd > 60 and b >= 85:
        return "BUILDING"
    if r - g >= 8 and sd > 60:
        return "LOGS"
    if g >= 110 and gr < 12 and sd >= 55 and dfc < 0.45:
        return "ROCKS"
    if dfc >= 0.40:
        return "TREES" if dgbc >= 25 else "FIELD"
    if dfr >= 0.25 and dgbr >= 25:
        return "HEDGEROW"
    if sd >= 55:
        return "FIELD"
    if gr >= 30 and sd < 30 and g < 152:
        return "MARSH"
    if gr < 2 and g > 130 and sd < 40:
        # tan: chiazza (anello pure tan) o strada (anello d'erba)?
        return "OPEN" if rg - rr_ >= 12 else "DEPRESSION"
    return "OPEN"

COLORS = {"OPEN": None, "TREES": (0,200,0), "FIELD": (255,200,0),
          "ROCKS": (160,160,160), "BUILDING": (255,0,0), "STREAM": (0,120,255),
          "MARSH": (0,255,255), "DEPRESSION": (200,120,40),
          "HEDGEROW": (0,90,0), "LOGS": (140,70,20)}

result = {}
for col in range(1, 36):
    last = 19 if col % 2 == 1 else 18
    for row in range(0, last+1):
        result["%d,%d" % (col, row)] = classify(col, row)
json.dump(result, open("/tmp/terrain.json", "w"))
from collections import Counter
print(Counter(result.values()))

ov = img.copy()
d = ImageDraw.Draw(ov, "RGBA")
for key, t in result.items():
    if COLORS[t] is None: continue
    col, row = map(int, key.split(","))
    cx, cy = center(col, row)
    pts = [(cx+math.cos(a*math.pi/3)*R*0.92, cy+math.sin(a*math.pi/3)*R*0.92) for a in range(6)]
    d.polygon(pts, fill=COLORS[t]+(110,))
ov.resize((W//4, H//4)).save("/tmp/overlay.png")
print("overlay: /tmp/overlay.png  dati: /tmp/terrain.json")
