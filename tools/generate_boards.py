# Genera engine/Boards.gd classificando le 4 scansioni in assets/maps/.
# Uso: python3 tools/generate_boards.py   (dalla radice del progetto)
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from collections import Counter, defaultdict
from classify_terrain import Classifier, save_overlay

MAPS = {
    "farmhouse": ("assets/maps/farmhouse.jpg", 72, 106, False),
    "hill": ("assets/maps/hill.jpg", 73, 109, True),
    "village": ("assets/maps/village.jpg", 77, 110, False),
    "hedgerows": ("assets/maps/hedgerows.jpg", 70, 110, False),
}

# classe del classificatore -> membro di Domain.Terrain
TERRAIN_NAME = {
    "TREES": "TREES", "FIELD": "FIELD", "ROCKS": "ROCKS",
    "BUILDING": "BUILDING", "STREAM": "STREAM", "MARSH": "MARSH",
    "HEDGEROW": "HEDGEROW", "LOGS": "LOGS",
    "OPEN_L1": "OPEN_LEVEL_1", "OPEN_L2": "OPEN_LEVEL_2",
}


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


def emit_hexsides(lines, feats):
    # stringhe compatte "c1,r1|c2,r2|X" (H=siepe, B=bocage, W=muro)
    letter = {"HEDGEROW": "H", "BOCAGE": "B", "WALL": "W"}
    keys = sorted(feats)
    line = "\t\t"
    for k in keys:
        q = '"%s|%s",' % (k, letter[feats[k]])
        if len(line) + len(q) > 76:
            lines.append(line.rstrip())
            line = "\t\t"
        line += q + " "
    lines.append(line.rstrip())


def main():
    lines = []
    lines.append("## Terreno per hex delle 4 mappe, GENERATO da tools/generate_boards.py")
    lines.append("## (classificazione automatica dei colori delle scansioni; rifinibile")
    lines.append("## a mano: e' solo una tabella). Gli hex non elencati sono Open Level 0.")
    lines.append("## HEXSIDES: siepi/bocage/muri sui BORDI (\"c1,r1|c2,r2|H/B/W\").")
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
    all_feats = {}
    lines.append("const TERRAIN := {")
    for name, (path, x0, y0, tan_l1) in MAPS.items():
        clf = Classifier(path, x0, y0, tan_l1)
        result = clf.classify_all()
        feats = clf.edge_features()
        all_feats[name] = feats
        print(name, Counter(result.values()), "| hexsides:", Counter(feats.values()))
        save_overlay(clf, result, "/tmp/overlay_%s.png" % name, feats)
        lines.append('\t"%s": {' % name)
        emit_table(lines, result)
        lines.append("\t},")
    lines.append("}")
    lines.append("")
    lines.append("const HEXSIDES := {")
    for name in MAPS:
        lines.append('\t"%s": [' % name)
        emit_hexsides(lines, all_feats[name])
        lines.append("\t],")
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
    lines.append("\t# Hexside: siepi/bocage/muri sui bordi.")
    lines.append('\t_fill_hexsides(state, HEXSIDES[board_name])')
    lines.append("")
    lines.append("")
    lines.append("static func _fill_hexsides(state: GameState, entries: Array) -> void:")
    lines.append('\tvar types := {"H": D.Terrain.HEDGEROW, "B": D.Terrain.BOCAGE, "W": D.Terrain.WALL}')
    lines.append("\tfor e in entries:")
    lines.append('\t\tvar parts: PackedStringArray = String(e).split("|")')
    lines.append('\t\tstate.hexsides["%s|%s" % [parts[0], parts[1]]] = types[parts[2]]')
    out = os.path.join(os.path.dirname(__file__), "..", "engine", "Boards.gd")
    open(out, "w").write("\n".join(lines) + "\n")
    print("scritto", os.path.normpath(out))


if __name__ == "__main__":
    main()
