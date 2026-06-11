# Classificazione automatica del terreno dalle scansioni delle mappe.
#
# Campiona ogni hex per anelli concentrici e applica regole sui colori.
# Discriminatori chiave (tarati sulla palette delle mappe Compass):
# - croma dei pixel scuri: ombra d'albero verde profondo (g-b alto) vs
#   terra bruna dei solchi delle colture (g-b basso);
# - anello perimetrale verde scuro con centro pulito = siepe (HEDGEROW);
# - acqua = blu con rosso basso; sassi chiari = blu alto ma rosso alto;
# - arancio (r-g >= 35) = quota Livello 2 (mappa The Hill);
# - tan liscio = strada/sterrato -> OPEN (o Livello 1 sulla Hill con
#   tan_l1). Le vere Depression vanno marcate a mano in Boards.gd.
#
# Uso CLI: python3 tools/classify_terrain.py [mappa.jpg] [x0] [y0] [tan_l1]
# Origini (dal buildFile Vassal): farmhouse 72,106 - hill 73,109
#                                 village 77,110  - hedgerows 70,110
from PIL import Image, ImageDraw
import math, json, sys

DX, DY = 156.30026487501547, 180.48
R = DX / 1.5
COLS = 35


def hex_center(x0, y0, col, row):
    return (x0 + (col - 1) * DX, y0 + (row + (0.5 if col % 2 == 0 else 0.0)) * DY)


def last_row(col):
    return 19 if col % 2 == 1 else 18


class Classifier:
    def __init__(self, img_path, x0, y0, tan_l1=False):
        self.img = Image.open(img_path).convert("RGB")
        self.W, self.H = self.img.size
        self.px = self.img.load()
        self.x0, self.y0 = x0, y0
        self.tan_l1 = tan_l1

    def _ring(self, cx, cy, r_in, r_out, step):
        vals = []
        for ix in range(int(cx - r_out), int(cx + r_out), step):
            for iy in range(int(cy - r_out), int(cy + r_out), step):
                if 0 <= ix < self.W and 0 <= iy < self.H:
                    d2 = (ix - cx) ** 2 + (iy - cy) ** 2
                    if r_in * r_in <= d2 < r_out * r_out:
                        vals.append(self.px[ix, iy])
        return vals

    @staticmethod
    def _stats(vals):
        n = len(vals)
        r = sum(v[0] for v in vals) / n
        g = sum(v[1] for v in vals) / n
        b = sum(v[2] for v in vals) / n
        sd = math.sqrt(sum((v[0] - r) ** 2 + (v[1] - g) ** 2 + (v[2] - b) ** 2 for v in vals) / n)
        return r, g, b, sd

    @staticmethod
    def _darkinfo(vals):
        dark = [v for v in vals if v[0] + v[1] + v[2] < 290]
        if not dark:
            return 0.0, 0.0
        dn = len(dark)
        dgb = sum(v[1] for v in dark) / dn - sum(v[2] for v in dark) / dn
        return len(dark) / len(vals), dgb

    def classify(self, col, row):
        cx, cy = hex_center(self.x0, self.y0, col, row)
        core = self._ring(cx, cy, 0, R * 0.30, 3)
        mid = self._ring(cx, cy, 0, R * 0.45, 3)
        ring = self._ring(cx, cy, R * 0.45, R * 0.72, 4)
        r, g, b, sd = self._stats(mid)
        gr = g - r
        gb = g - b
        dfc, dgbc = self._darkinfo(core)
        dfr, dgbr = self._darkinfo(ring)
        if r - g >= 35 and sd < 55:
            return "OPEN_L2"  # pendii arancio della Hill
        if r - g < 10 and b >= 115 and gb < 25:
            return "STREAM" if r < 110 else "ROCKS"
        if r - g >= 10 and sd > 60 and b >= 85:
            return "BUILDING"
        if r - g >= 8 and sd > 60:
            return "LOGS"
        if g >= 110 and gr < 12 and sd >= 55 and dfc < 0.45:
            return "ROCKS"
        if dfc >= 0.40:
            return "TREES" if dgbc >= 25 else "FIELD"
        # (niente piu' classe HEDGEROW sul riempimento: le siepi sono
        # rilevate sui BORDI degli hex da edge_features)
        if sd >= 55:
            return "FIELD"
        if gr >= 30 and sd < 30 and g < 152:
            return "MARSH"
        if gr < 3 and r > 125 and sd < 50:
            # tan liscio: sterrato/strada (Open) o altopiano (Hill L1)
            return "OPEN_L1" if self.tan_l1 else "OPEN"
        return "OPEN"

    def classify_all(self):
        result = {}
        for col in range(1, COLS + 1):
            for row in range(0, last_row(col) + 1):
                result["%d,%d" % (col, row)] = self.classify(col, row)
        return result

    # ----------------------------------------------------- hexside

    def _pixel_to_hex(self, x, y):
        col = round((x - self.x0) / DX) + 1
        row = round((y - self.y0) / DY - (0.5 if col % 2 == 0 else 0.0))
        return col, row

    def _band(self, ax, ay, bx, by, off_lo, off_hi, n=9):
        """Campiona una banda lungo il segmento a-b, a offset perpendicolari
        [off_lo, off_hi] da ENTRAMBI i lati."""
        import math as m
        dx, dy = bx - ax, by - ay
        ln = m.hypot(dx, dy)
        px_, py_ = -dy / ln, dx / ln  # perpendicolare
        vals = []
        for i in range(n):
            t = 0.15 + 0.7 * i / (n - 1)
            sx, sy = ax + dx * t, ay + dy * t
            for off in (off_lo, (off_lo + off_hi) / 2, off_hi):
                for sgn in (1, -1):
                    qx, qy = int(sx + px_ * off * sgn), int(sy + py_ * off * sgn)
                    if 0 <= qx < self.W and 0 <= qy < self.H:
                        vals.append(self.px[qx, qy])
        return vals

    @staticmethod
    def _frac(vals, pred):
        if not vals:
            return 0.0
        return sum(1 for v in vals if pred(v)) / len(vals)

    def edge_features(self):
        """Siepi/bocage/muri sui BORDI degli hex.
        Ritorna {"c1,r1|c2,r2": "HEDGEROW"|"BOCAGE"|"WALL"}.
        Ogni bordo e' esaminato una sola volta (direzioni 30/90/150 gradi)."""
        import math as m
        feats = {}
        hedge = lambda v: v[1] > v[0] + 8 and v[1] - v[2] > 16 and v[1] < 115
        dark_hedge = lambda v: hedge(v) and v[1] < 85
        wall = lambda v: abs(int(v[0]) - int(v[1])) < 14 and \
            abs(int(v[1]) - int(v[2])) < 18 and 88 < v[1] < 175 and v[1] - v[2] < 16
        for col in range(1, COLS + 1):
            for row in range(0, last_row(col) + 1):
                cx, cy = hex_center(self.x0, self.y0, col, row)
                for k in range(3):  # bordi verso il basso: 30, 90, 150 gradi
                    ang = m.radians(30 + 60 * k)
                    ncx = cx + DY * m.cos(ang)
                    ncy = cy + DY * m.sin(ang)
                    ncol, nrow = self._pixel_to_hex(ncx, ncy)
                    if not (1 <= ncol <= COLS and 0 <= nrow <= last_row(ncol)):
                        continue
                    # vertici del bordo condiviso (a 30 gradi dal centro-bordo)
                    v1 = (cx + R * m.cos(ang - m.radians(30)),
                          cy + R * m.sin(ang - m.radians(30)))
                    v2 = (cx + R * m.cos(ang + m.radians(30)),
                          cy + R * m.sin(ang + m.radians(30)))
                    band = self._band(v1[0], v1[1], v2[0], v2[1], 4, 14)
                    h = self._frac(band, hedge)
                    w = self._frac(band, wall)
                    if h < 0.45 and w < 0.55:
                        continue
                    # guardia anti-chioma: se anche BEN DENTRO entrambi gli
                    # hex e' quasi tutto scuro, e' un bosco che sborda (le
                    # siepi, anche grasse, lasciano l'interno piu' chiaro).
                    inner = self._band(v1[0], v1[1], v2[0], v2[1], 30, 46)
                    if h >= 0.45 and self._frac(inner, hedge) > 0.75:
                        continue
                    key = "%d,%d|%d,%d" % ((col, row, ncol, nrow)
                        if (col, row) <= (ncol, nrow) else (ncol, nrow, col, row))
                    if h >= 0.45:
                        feats[key] = "BOCAGE" if self._frac(band, dark_hedge) > 0.5 \
                            else "HEDGEROW"
                    else:
                        feats[key] = "WALL"
        return feats


OVERLAY_COLORS = {
    "OPEN": None, "TREES": (0, 200, 0), "FIELD": (255, 200, 0),
    "ROCKS": (160, 160, 160), "BUILDING": (255, 0, 0), "STREAM": (0, 120, 255),
    "MARSH": (0, 255, 255), "HEDGEROW": (0, 90, 0), "LOGS": (140, 70, 20),
    "OPEN_L1": (230, 230, 120), "OPEN_L2": (255, 120, 0),
}


EDGE_COLORS = {"HEDGEROW": (0, 230, 60), "BOCAGE": (170, 0, 230),
               "WALL": (255, 255, 255)}


def save_overlay(clf, result, path, feats=None):
    ov = clf.img.copy()
    d = ImageDraw.Draw(ov, "RGBA")
    for key, t in result.items():
        if OVERLAY_COLORS[t] is None:
            continue
        col, row = map(int, key.split(","))
        cx, cy = hex_center(clf.x0, clf.y0, col, row)
        pts = [(cx + math.cos(a * math.pi / 3) * R * 0.92,
                cy + math.sin(a * math.pi / 3) * R * 0.92) for a in range(6)]
        d.polygon(pts, fill=OVERLAY_COLORS[t] + (110,))
    # hexside rilevati: segmento spesso sul bordo condiviso
    for key, t in (feats or {}).items():
        a, b = key.split("|")
        c1, r1 = map(int, a.split(","))
        c2, r2 = map(int, b.split(","))
        x1, y1 = hex_center(clf.x0, clf.y0, c1, r1)
        x2, y2 = hex_center(clf.x0, clf.y0, c2, r2)
        mx, my = (x1 + x2) / 2, (y1 + y2) / 2
        # bordo perpendicolare alla congiungente, lungo R
        dx, dy = x2 - x1, y2 - y1
        ln = math.hypot(dx, dy)
        px_, py_ = -dy / ln, dx / ln
        d.line([(mx - px_ * R / 2, my - py_ * R / 2),
                (mx + px_ * R / 2, my + py_ * R / 2)],
               fill=EDGE_COLORS[t] + (230,), width=10)
    ov.resize((clf.W // 4, clf.H // 4)).save(path)


if __name__ == "__main__":
    img = sys.argv[1] if len(sys.argv) > 1 else "assets/maps/hedgerows.jpg"
    x0 = float(sys.argv[2]) if len(sys.argv) > 2 else 70.0
    y0 = float(sys.argv[3]) if len(sys.argv) > 3 else 110.0
    tan_l1 = len(sys.argv) > 4 and sys.argv[4] == "tan_l1"
    clf = Classifier(img, x0, y0, tan_l1)
    result = clf.classify_all()
    from collections import Counter
    print(Counter(result.values()))
    json.dump(result, open("/tmp/terrain.json", "w"))
    save_overlay(clf, result, "/tmp/overlay.png")
    print("overlay: /tmp/overlay.png  dati: /tmp/terrain.json")
