## Vista 2D della mappa: disegna la griglia esagonale e i segnalini
## leggendo il GameState. SOLO rappresentazione: nessuna logica di gioco.
##
## Due modalita':
## - con `board` (scansione della mappa come texture): disegna la mappa
##   vera e ci posiziona sopra i segnalini, usando la calibrazione della
##   griglia presa dal modulo Vassal (vedi BOARDS);
## - senza: griglia procedurale a colori per terreno (banco di prova).
##
## Geometria delle mappe stampate: esagoni flat-top in colonne, numerati
## col.riga; le colonne PARI sono mezzo passo piu' in basso.
class_name MapView
extends Node2D

const D := preload("res://engine/Domain.gd")

# Calibrazione delle 4 mappe (dal buildFile del modulo Vassal: HexGrid
# dx/dy/x0/y0). origin = centro dell'hex 01.00; cell = passo (dx, dy).
const CELL := Vector2(156.30026487501547, 180.48)
const BOARDS := {
	"farmhouse": {"file": "res://assets/maps/farmhouse.jpg", "origin": Vector2(72, 106)},
	"hill": {"file": "res://assets/maps/hill.jpg", "origin": Vector2(73, 109)},
	"village": {"file": "res://assets/maps/village.jpg", "origin": Vector2(77, 110)},
	"hedgerows": {"file": "res://assets/maps/hedgerows.jpg", "origin": Vector2(70, 110)},
}

# Modalita' procedurale (nessuna texture)
const HEX_SIZE := 46.0  # raggio centro-vertice
const SQRT3 := sqrt(3.0)

# Colori provvisori del terreno (solo modalita' procedurale)
const TERRAIN_COLORS := {
	D.Terrain.OPEN_LEVEL_0: Color(0.62, 0.71, 0.47),
	D.Terrain.OPEN_LEVEL_1: Color(0.67, 0.69, 0.45),
	D.Terrain.OPEN_LEVEL_2: Color(0.71, 0.67, 0.44),
	D.Terrain.OPEN_LEVEL_3: Color(0.74, 0.64, 0.42),
	D.Terrain.ROCKS: Color(0.62, 0.62, 0.60),
	D.Terrain.BUILDING: Color(0.48, 0.33, 0.26),
	D.Terrain.TREES: Color(0.28, 0.45, 0.25),
	D.Terrain.MARSH: Color(0.45, 0.58, 0.52),
	D.Terrain.HEDGEROW: Color(0.22, 0.38, 0.20),
	D.Terrain.WALL: Color(0.52, 0.50, 0.46),
	D.Terrain.LONG_GRASS: Color(0.55, 0.66, 0.36),
	D.Terrain.DEPRESSION: Color(0.58, 0.56, 0.40),
	D.Terrain.STREAM: Color(0.42, 0.60, 0.74),
	D.Terrain.ORCHARD: Color(0.45, 0.58, 0.32),
	D.Terrain.LOGS: Color(0.45, 0.32, 0.20),
	D.Terrain.FIELD: Color(0.60, 0.55, 0.33),
	D.Terrain.FOXHOLE: Color(0.42, 0.36, 0.28),
	D.Terrain.RUBBLE: Color(0.55, 0.48, 0.42),
	D.Terrain.CRATER: Color(0.50, 0.42, 0.32),
	D.Terrain.BOCAGE: Color(0.18, 0.32, 0.16),
}
const SIDE_COLORS := {
	D.Side.FRIENDLY: Color(0.18, 0.32, 0.60),
	D.Side.ENEMY: Color(0.55, 0.55, 0.52),  # feldgrau
}

var state: GameState
var board: Texture2D = null
var origin := Vector2.ZERO          # centro dell'hex con etichetta (first_col, 0)
var cell := Vector2(1.5 * HEX_SIZE, SQRT3 * HEX_SIZE)
var first_col := 0                  # prima colonna etichettata (1 sulle mappe vere)
var selected: Character = null      # personaggio evidenziato
var highlight_hex := Vector2i(-99, -99)  # hex evidenziato (selezione a vuoto)


# Carica una delle 4 mappe (se la scansione e' presente in assets/maps).
# Ritorna true se la texture e' stata caricata.
func load_board(board_name: String) -> bool:
	assert(BOARDS.has(board_name), "Mappa sconosciuta: %s" % board_name)
	var info: Dictionary = BOARDS[board_name]
	if not ResourceLoader.exists(info["file"]):
		return false
	board = load(info["file"])
	origin = info["origin"]
	cell = CELL
	first_col = 1
	return true


# Centro in pixel di una cella (col, riga). Colonne PARI mezzo passo giu'.
func hex_center(col: int, row: int) -> Vector2:
	var x := origin.x + cell.x * (col - first_col)
	var y := origin.y + cell.y * (row + (0.5 if col % 2 == 0 else 0.0))
	return Vector2(x, y)


# Hex piu' vicino a un punto in coordinate locali della mappa.
# Ritorna Vector2i(col, row), o (-99,-99) se il punto e' fuori griglia.
func pick_hex(pos: Vector2) -> Vector2i:
	var best := Vector2i(-99, -99)
	var best_d := INF
	var col_guess := int(round((pos.x - origin.x) / cell.x)) + first_col
	for col in range(col_guess - 1, col_guess + 2):
		var row_guess := int(round((pos.y - origin.y) / cell.y - (0.5 if col % 2 == 0 else 0.0)))
		for row in range(row_guess - 1, row_guess + 2):
			if state == null or not state.map.has(GameState.hex_key(col, row)):
				continue
			var d := hex_center(col, row).distance_to(pos)
			if d < best_d:
				best_d = d
				best = Vector2i(col, row)
	return best if best_d <= cell.x / 1.5 * 1.05 else Vector2i(-99, -99)


# Personaggio vivo in un dato hex, o null.
func character_at_hex(hex: Vector2i) -> Character:
	if state == null:
		return null
	var c := state.character_at(hex.x, hex.y)
	return null if c == null or c.is_dead() else c


func _draw() -> void:
	if state == null:
		return
	var font := ThemeDB.fallback_font
	var radius := cell.x / 1.5  # raggio centro-vertice
	if board != null:
		draw_texture(board, Vector2.ZERO)
	else:
		_draw_procedural_terrain(font, radius)
	# Evidenziazione dell'hex selezionato
	if highlight_hex.x > -99:
		var hc := hex_center(highlight_hex.x, highlight_hex.y)
		draw_polyline(_closed(_hex_points(hc, radius * 0.96)),
			Color(1.0, 1.0, 0.3, 0.9), radius * 0.06)
	# Segnalini. Un Enemy non Known si mostra come "?" senza ordine:
	# il giocatore sa che c'e' qualcosa, non chi sia ne' cosa fara'.
	for c in state.characters:
		if c.is_dead():
			continue
		var hidden := c.side == D.Side.ENEMY and not c.known
		var center := hex_center(c.position.x, c.position.y)
		if c == selected:
			draw_circle(center, radius * 0.58, Color(1.0, 1.0, 0.3, 0.85))
		draw_circle(center, radius * 0.45,
			Color(0.30, 0.30, 0.30) if hidden else SIDE_COLORS[c.side])
		draw_circle(center, radius * 0.45, Color(0, 0, 0, 0.6), false, radius * 0.04)
		draw_string(font, center + Vector2(-radius * 0.15, radius * 0.15),
			"?" if hidden else c.display_name.substr(0, 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(radius * 0.42), Color.WHITE)
		if c.side == D.Side.FRIENDLY and c.spotted:
			draw_circle(center + Vector2(radius * 0.38, -radius * 0.38),
				radius * 0.12, Color(0.9, 0.15, 0.15))
		if c.has_order and not hidden:
			var label: String = D.ORDER_NAMES[c.order]
			if not c.order_move.is_empty():
				label += " " + c.order_move
			draw_string(font, center + Vector2(-radius * 0.9, radius * 0.78),
				label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(radius * 0.3),
				Color(0.95, 0.95, 0.2))


func _draw_procedural_terrain(font: Font, radius: float) -> void:
	for key in state.map:
		var parts: PackedStringArray = key.split(",")
		var col := int(parts[0])
		var row := int(parts[1])
		var hex: GameState.MapHex = state.map[key]
		var center := hex_center(col, row)
		var points := _hex_points(center, radius)
		draw_colored_polygon(points, TERRAIN_COLORS.get(hex.terrain, Color.MAGENTA))
		draw_polyline(points + PackedVector2Array([points[0]]), Color(0, 0, 0, 0.25), 1.5)
		draw_string(font, center + Vector2(-14, -radius * 0.55),
			"%02d.%02d" % [col, row], HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(0, 0, 0, 0.45))


# I sei vertici di un esagono flat-top attorno a un centro.
static func _hex_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(6):
		var angle := PI / 3.0 * i  # 0, 60, 120... gradi: vertice a destra
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	return points + PackedVector2Array([points[0]])
