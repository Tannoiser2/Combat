# Rileva i "collari" colorati stampati negli hex delle mappe Vol.2 e li
# classifica per colore. Serve a ricavare i terreni speciali (Rule 27) che
# il classificatore a colori (classify_terrain.py) non distingue:
#   - Abbazia (27.5): collare ROSSO = ABBEY_EXTERIOR, ROSSO+GIALLO =
#     ABBEY_INTERIOR.
# I valori trovati vanno trascritti nel dizionario MANUAL di
# generate_boards.py (che li applica sopra la classificazione automatica).
#
# Uso: python3 tools/detect_collars.py <mappa> [c0 c1 r0 r1]
#   (dalla radice del progetto; la regione limita i falsi positivi)
import sys, math, os
sys.path.insert(0, os.path.dirname(__file__))
from PIL import Image, ImageDraw
from classify_terrain import hex_center, last_row, COLS, R

Image.MAX_IMAGE_PIXELS = None

# origini (px) di ogni mappa, dal buildFile Vassal (vedi generate_boards.py)
ORIG = {
    "farmhouse": (72, 106), "hill": (73, 109), "village": (77, 110),
    "hedgerows": (70, 110), "woods": (67, 103), "town": (73, 104),
    "abbey": (73, 104), "hamlet": (73, 105), "hedgerows2": (73, 104),
    "ridge": (73, 104),
}


def is_red(r, g, b):
    return r >= 150 and g <= 95 and b <= 95 and r - g >= 70 and r - b >= 70


def is_yellow(r, g, b):
    return r >= 180 and g >= 150 and b <= 120 and g - b >= 55


def detect(name, c0, c1, r0, r1):
    x0, y0 = ORIG[name]
    img = Image.open("assets/maps/%s.jpg" % name).convert("RGB")
    px = img.load()
    W, H = img.size
    red_hexes, yellow_hexes = [], []
    for col in range(c0, c1 + 1):
        for row in range(r0, r1 + 1):
            if row > last_row(col):
                continue
            cx, cy = hex_center(x0, y0, col, row)
            rr = int(R * 0.82)
            reds = []
            for ix in range(int(cx - rr), int(cx + rr)):
                for iy in range(int(cy - rr), int(cy + rr)):
                    if 0 <= ix < W and 0 <= iy < H and \
                            (ix - cx) ** 2 + (iy - cy) ** 2 <= rr * rr:
                        if is_red(*px[ix, iy]):
                            reds.append((ix, iy))
            if len(reds) < 14:  # nessun collare rosso -> hex non speciale
                continue
            # giallo vicino al centroide del rosso = collare rosso+giallo
            rcx = sum(p[0] for p in reds) / len(reds)
            rcy = sum(p[1] for p in reds) / len(reds)
            ys = 0
            for ix in range(int(rcx - 30), int(rcx + 30)):
                for iy in range(int(rcy - 30), int(rcy + 30)):
                    if 0 <= ix < W and 0 <= iy < H and is_yellow(*px[ix, iy]):
                        ys += 1
            (yellow_hexes if ys >= 8 else red_hexes).append("%d,%d" % (col, row))
    return img, x0, y0, red_hexes, yellow_hexes


def main():
    name = sys.argv[1]
    if len(sys.argv) >= 6:
        c0, c1, r0, r1 = map(int, sys.argv[2:6])
    else:
        c0, c1, r0, r1 = 1, COLS, 0, 19
    img, x0, y0, red, yellow = detect(name, c0, c1, r0, r1)
    print("ROSSO  (es. ABBEY_EXTERIOR):", red)
    print("R+GIALLO (es. ABBEY_INTERIOR):", yellow)
    ov = img.copy()
    d = ImageDraw.Draw(ov, "RGBA")
    for hexes, col in ((red, (255, 0, 0, 110)), (yellow, (255, 200, 0, 120))):
        for key in hexes:
            cc, rr = map(int, key.split(","))
            cx, cy = hex_center(x0, y0, cc, rr)
            pts = [(cx + math.cos(a * math.pi / 3) * R * 0.9,
                    cy + math.sin(a * math.pi / 3) * R * 0.9) for a in range(6)]
            d.polygon(pts, fill=col)
    out = "/tmp/collars_%s.png" % name
    ov.resize((ov.width // 4, ov.height // 4)).save(out)
    print("overlay:", out)


if __name__ == "__main__":
    main()
