# Genera engine/Boards.gd classificando le scansioni in assets/maps/.
# Uso: python3 tools/generate_boards.py   (dalla radice del progetto)
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from collections import Counter, defaultdict
from classify_terrain import Classifier, save_overlay

# Origini (dal buildFile Vassal):
#   farmhouse 72,106 - hill 73,109 - village 77,110 - hedgerows 70,110
#   woods 67,103 - town 73,104 - abbey 73,104 - hamlet 73,105
#   hedgerows2 73,104 - ridge 73,104
MAPS = {
    "farmhouse":  ("assets/maps/farmhouse.jpg",  72, 106, False),
    "hill":       ("assets/maps/hill.jpg",        73, 109, True),
    "village":    ("assets/maps/village.jpg",     77, 110, False),
    "hedgerows":  ("assets/maps/hedgerows.jpg",   70, 110, False),
    "woods":      ("assets/maps/woods.jpg",       67, 103, False),
    "town":       ("assets/maps/town.jpg",        73, 104, False),
    "abbey":      ("assets/maps/abbey.jpg",       73, 104, False),
    "hamlet":     ("assets/maps/hamlet.jpg",      73, 105, False),
    "hedgerows2": ("assets/maps/hedgerows2.jpg",  73, 104, False),
    "ridge":      ("assets/maps/ridge.jpg",       73, 104, True),
}

# classe del classificatore -> membro di Domain.Terrain
TERRAIN_NAME = {
    "TREES": "TREES", "FIELD": "FIELD", "ROCKS": "ROCKS",
    "BUILDING": "BUILDING", "STREAM": "STREAM", "MARSH": "MARSH",
    "HEDGEROW": "HEDGEROW", "LOGS": "LOGS",
    # Siepe/Muro/Bocage sono ESAGONI (Rule 11.05/11.06), non lati.
    "WALL": "WALL", "BOCAGE": "BOCAGE",
    "OPEN_L1": "OPEN_LEVEL_1", "OPEN_L2": "OPEN_LEVEL_2",
    # Terreni speciali Vol.2 (marcati a mano, vedi MANUAL): identita'.
    "FOUNTAIN": "FOUNTAIN", "FORTIFIED_BUILDING": "FORTIFIED_BUILDING",
    "TRENCH": "TRENCH", "ABBEY_EXTERIOR": "ABBEY_EXTERIOR",
    "ABBEY_INTERIOR": "ABBEY_INTERIOR",
}

# Terreni speciali del Volume 2 marcati A MANO dai collari/simboli sulle
# mappe ufficiali: il classificatore a colori (classify_terrain.py) li vede
# come ROCKS/BUILDING/OPEN. Questi override sono applicati DOPO la
# classificazione automatica e VINCONO su di essa (l'hex viene tolto dalla
# sua classe auto e messo in quella indicata qui).
#
# abbey: collari sul tabellone -> rosso = ABBEY_EXTERIOR, rosso+giallo =
# ABBEY_INTERIOR (Rule 27.5). Rilevati dai puntini con tools/detect_collars.py
# e validati sull'esempio del regolamento (18,10 e 21,11 interni, 22,10
# esterno).
MANUAL = {
    # town: fontana ornamentale della piazza (Rule 27.1, collare giallo sul
    # center-dot). Tutti gli hex collarati sono Fountain (Rough, ostacolo 1/2).
    # Rilevati con tools/detect_collars.py --fountain (giallo puro 255,255,0).
    "town": {
        "FOUNTAIN": [
            "15,13", "15,14", "15,15", "16,13", "16,14", "16,15",
            "17,13", "17,14", "17,15",
        ],
    },
    "abbey": {
        "ABBEY_EXTERIOR": [
            "17,9", "17,10", "17,11", "17,12", "17,13", "18,8", "18,12",
            "19,7", "19,9", "19,13", "20,6", "20,8", "20,12", "21,7", "21,9",
            "21,13", "22,8", "22,9", "22,10", "22,12", "23,10", "23,13",
            "24,8", "24,9", "24,10", "24,12", "25,9", "25,10", "25,11",
            "25,12", "25,13",
        ],
        "ABBEY_INTERIOR": [
            "18,9", "18,10", "18,11", "19,10", "19,11", "19,12", "20,9",
            "20,10", "20,11", "21,10", "21,11", "21,12", "22,11", "23,11",
            "23,12", "24,11",
        ],
    },
}


# Elevazione marcata A MANO: i terreni erbosi in quota sfuggono al
# classificatore a colori (vedi nota sulla Hill/Ridge), quindi la quota del
# crinale va indicata qui. Per mappa: {"col,row": livello}. Applicata in fill()
# DOPO il terreno (vince sulla quota dedotta da OPEN_LEVEL_1/2). Riempire con
# l'export dell'editor (sezione MANUAL_LEVELS del file map_export_<mappa>.txt).
MANUAL_LEVELS = {
    # "ridge": {"12,5": 1, "13,5": 2, ...},
}


# Mappe su cui NON applicare la conversione lati->esagoni (fold_edges_to_hexes):
# il classificatore vede i bordi dei boschetti come "siepi" e su mappe boschive
# senza siepi vere questo crea esagoni-siepe spuri. Si aggiungono qui le mappe
# man mano che si rivedono (revisione visiva). woods: nessuna siepe vera.
SKIP_EDGE_FOLD = {"woods"}


def apply_manual(name, result):
    """Sovrascrive la classificazione automatica con i terreni speciali
    marcati a mano per la mappa `name`."""
    for tname, hexes in MANUAL.get(name, {}).items():
        for h in hexes:
            result[h] = tname


def emit_levels(lines, name):
    """Tabella LEVELS[<mappa>] = { 'c,r': livello } dai MANUAL_LEVELS."""
    lvl = MANUAL_LEVELS.get(name, {})
    lines.append('\t"%s": {' % name)
    line = "\t\t"
    for k in sorted(lvl, key=hex_sort_key):
        q = '"%s": %d, ' % (k, int(lvl[k]))
        if len(line) + len(q) > 76:
            lines.append(line.rstrip())
            line = "\t\t"
        line += q
    if line.strip():
        lines.append(line.rstrip())
    lines.append("\t},")


def hex_sort_key(k):
    c, r = k.split(",")
    return (int(c), int(r))


def emit_table(lines, result):
    groups = defaultdict(list)
    for k, v in result.items():
        if v != "OPEN":
            groups[v].append(k)
    for t in sorted(groups):
        lines.append("\t\tD.Terrain.%s: [" % TERRAIN_NAME[t])
        line = "\t\t\t"
        for k in sorted(groups[t], key=hex_sort_key):
            q = '"%s",' % k
            if len(line) + len(q) > 76:
                lines.append(line.rstrip())
                line = "\t\t\t"
            line += q + " "
        lines.append(line.rstrip())
        lines.append("\t\t],")


def fold_edges_to_hexes(result, feats):
    """Rule 11.05/11.06: siepi/muri/bocage sono ESAGONI, non lati. Il
    classificatore li rileva sui bordi (edge_features); qui li riportiamo sugli
    esagoni adiacenti. Euristica (rifinibile a mano in editor): entrambi gli hex
    del bordo diventano quel terreno, ma solo se attualmente Open (non si
    sovrascrivono edifici/alberi/ecc.). Ritorna quanti hex sono stati marcati."""
    added = 0
    for edge, tname in feats.items():
        for h in edge.split("|"):
            if result.get(h, "OPEN") == "OPEN":
                result[h] = tname
                added += 1
    return added


def main():
    lines = []
    lines.append("## Terreno per hex delle 4 mappe, GENERATO da tools/generate_boards.py")
    lines.append("## (classificazione automatica dei colori delle scansioni; rifinibile")
    lines.append("## a mano: e' solo una tabella). Gli hex non elencati sono Open Level 0.")
    lines.append("## Siepe/Muro/Bocage sono ESAGONI (Rule 11.05/11.06): i lati rilevati dal")
    lines.append("## classificatore sono riportati sugli hex adiacenti (rifinibili in editor).")
    lines.append("## Limiti noti: sulla Hill i livelli di quota valgono solo dove il")
    lines.append("## colore li mostra (tan=L1, arancio=L2), le zone erbose in quota")
    lines.append("## risultano L0; le Depression vanno marcate a mano.")
    lines.append("class_name Boards")
    lines.append("extends RefCounted")
    lines.append("")
    lines.append('const D := preload("res://engine/Domain.gd")')
    lines.append("")
    lines.append("# Tutte le mappe: 35 colonne; le righe arrivano a 19 (dispari) / 18 (pari).")
    lines.append("const COLS := 35")
    lines.append("const LAST_ROW_ODD := 19")
    lines.append("const LAST_ROW_EVEN := 18")
    lines.append("")
    lines.append("const TERRAIN := {")
    for name, (path, x0, y0, tan_l1) in MAPS.items():
        clf = Classifier(path, x0, y0, tan_l1)
        result = clf.classify_all()
        apply_manual(name, result)
        # Rule 11.05/11.06: siepi/muri/bocage rilevati sui bordi -> esagoni.
        # Saltata sulle mappe boschive senza siepi vere (SKIP_EDGE_FOLD).
        added = 0
        if name not in SKIP_EDGE_FOLD:
            feats = clf.edge_features()
            added = fold_edges_to_hexes(result, feats)
        print(name, Counter(result.values()), "| lati->hex siepe/muro:", added)
        save_overlay(clf, result, "/tmp/overlay_%s.png" % name, {})
        lines.append('\t"%s": {' % name)
        emit_table(lines, result)
        lines.append("\t},")
    lines.append("}")
    lines.append("")
    lines.append("# Elevazione marcata a mano (col,row -> livello): i terreni in quota che")
    lines.append("# il classificatore a colori vede come L0. Applicata in fill() dopo il")
    lines.append("# terreno. Sorgente: MANUAL_LEVELS in tools/generate_boards.py.")
    lines.append("const LEVELS := {")
    for name in MAPS:
        emit_levels(lines, name)
    lines.append("}")
    lines.append("")
    lines.append("")
    lines.append("# Riempie state.map con la griglia completa della mappa richiesta.")
    lines.append("static func fill(state: GameState, board_name: String) -> void:")
    lines.append('\tassert(TERRAIN.has(board_name), "Mappa sconosciuta: %s" % board_name)')
    lines.append("\tfor col in range(1, COLS + 1):")
    lines.append("\t\tvar last_row := LAST_ROW_ODD if col % 2 == 1 else LAST_ROW_EVEN")
    lines.append("\t\tfor row in range(0, last_row + 1):")
    lines.append("\t\t\tstate.map[GameState.hex_key(col, row)] = GameState.MapHex.new(D.Terrain.OPEN_LEVEL_0, 0)")
    lines.append("\tvar tables: Dictionary = TERRAIN[board_name]")
    lines.append("\tfor terrain in tables:")
    lines.append("\t\tfor key in tables[terrain]:")
    lines.append("\t\t\tvar hex: GameState.MapHex = state.map[key]")
    lines.append("\t\t\thex.terrain = terrain")
    lines.append("\t\t\tmatch terrain:")
    lines.append("\t\t\t\tD.Terrain.OPEN_LEVEL_1: hex.level = 1")
    lines.append("\t\t\t\tD.Terrain.OPEN_LEVEL_2: hex.level = 2")
    lines.append("\t# Elevazione marcata a mano (vince sulla quota dedotta dal terreno).")
    lines.append("\tfor lkey in LEVELS.get(board_name, {}):")
    lines.append("\t\tif state.map.has(lkey):")
    lines.append("\t\t\tstate.map[lkey].level = int(LEVELS[board_name][lkey])")
    out = os.path.join(os.path.dirname(__file__), "..", "engine", "Boards.gd")
    open(out, "w").write("\n".join(lines) + "\n")
    print("scritto", os.path.normpath(out))


if __name__ == "__main__":
    main()
