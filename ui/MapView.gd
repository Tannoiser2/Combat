## Vista 2D della mappa: disegna la griglia esagonale e i segnalini
## leggendo il GameState. SOLO rappresentazione: nessuna logica di gioco.
##
## Due modalita':
## - con `board` (scansione della mappa come texture): disegna la mappa
##   vera e ci posiziona sopra i segnalini, usando la calibrazione della
##   griglia presa dal modulo Vassal (vedi BOARDS);
## - senza (es. build web: le scansioni non sono nel repo): la stessa
##   griglia viene disegnata proceduralmente, con feature generate a
##   runtime (chiome, solchi, sassi, acqua, siepi, tetti) dal terreno
##   classificato in Boards.gd. Nessun artwork protetto, solo codice.
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

# Colore di base (riempimento) di ogni hex in modalita' procedurale.
# Per i terreni "decorati" (alberi, sassi, edifici...) la base e' il
# suolo, le feature vengono disegnate sopra da _draw_feature().
const BASE_COLORS := {
	D.Terrain.OPEN_LEVEL_0: Color(0.52, 0.63, 0.37),
	D.Terrain.OPEN_LEVEL_1: Color(0.60, 0.64, 0.40),
	D.Terrain.OPEN_LEVEL_2: Color(0.68, 0.63, 0.42),
	D.Terrain.OPEN_LEVEL_3: Color(0.74, 0.64, 0.44),
	D.Terrain.ROCKS: Color(0.52, 0.63, 0.37),
	D.Terrain.BUILDING: Color(0.52, 0.63, 0.37),
	D.Terrain.TREES: Color(0.40, 0.52, 0.30),
	D.Terrain.MARSH: Color(0.46, 0.57, 0.50),
	D.Terrain.HEDGEROW: Color(0.50, 0.61, 0.36),
	D.Terrain.WALL: Color(0.52, 0.63, 0.37),
	D.Terrain.LONG_GRASS: Color(0.56, 0.66, 0.34),
	D.Terrain.DEPRESSION: Color(0.60, 0.61, 0.42),
	D.Terrain.STREAM: Color(0.50, 0.62, 0.40),
	D.Terrain.ORCHARD: Color(0.46, 0.58, 0.33),
	D.Terrain.LOGS: Color(0.52, 0.63, 0.37),
	D.Terrain.FIELD: Color(0.75, 0.68, 0.42),
	D.Terrain.FOXHOLE: Color(0.52, 0.63, 0.37),
	D.Terrain.RUBBLE: Color(0.58, 0.53, 0.47),
	D.Terrain.CRATER: Color(0.54, 0.47, 0.36),
	D.Terrain.BOCAGE: Color(0.48, 0.59, 0.34),
}

# Colori delle decorazioni procedurali.
const C_CANOPY := Color(0.20, 0.38, 0.19)
const C_CANOPY_HI := Color(0.29, 0.49, 0.26)
const C_HEDGE := Color(0.15, 0.31, 0.15)
const C_BOCAGE := Color(0.10, 0.25, 0.12)
const C_ROCK := Color(0.62, 0.62, 0.59)
const C_ROCK_HI := Color(0.75, 0.75, 0.72)
const C_ROOF := Color(0.56, 0.28, 0.22)
const C_WATER := Color(0.40, 0.58, 0.74)
const C_WALL := Color(0.56, 0.54, 0.49)
const C_LOG := Color(0.46, 0.32, 0.19)
const C_DIRT := Color(0.47, 0.39, 0.29)
const C_DIRT_DK := Color(0.36, 0.29, 0.21)
const C_FURROW := Color(0.64, 0.57, 0.33)
const C_GRASS_DK := Color(0.34, 0.46, 0.23)
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
var cue_hexes: Array[Vector2i] = []  # hex suggeriti (bersagli/mosse)
var cue_color := Color(0.95, 0.85, 0.2, 0.9)
var _counter_cache := {}            # id -> Texture2D oppure null (assente)

# Segnalino "retro"/dummy generico per team nemico (non identificato).
const DUMMY_BY_TEAM := {
	"Blue": "GE-BlueTeam-Dummy-1",
	"Red": "GE-RedTeam-Dummy-1",
	"White": "GE-WhiteTeam-Dummy-1",
	"Yellow": "GE-YellowTeam-Dummy-1",
}


# Carica una delle 4 mappe (se la scansione e' presente in assets/maps).
# Ritorna true se la texture e' stata caricata; senza texture la stessa
# griglia si disegna in modalita' procedurale (terreno da Boards.gd).
func load_board(board_name: String) -> bool:
	assert(BOARDS.has(board_name), "Mappa sconosciuta: %s" % board_name)
	var info: Dictionary = BOARDS[board_name]
	first_col = 1
	if not ResourceLoader.exists(info["file"]):
		board = null
		origin = Vector2(HEX_SIZE, HEX_SIZE)
		cell = Vector2(1.5 * HEX_SIZE, SQRT3 * HEX_SIZE)
		return false
	board = load(info["file"])
	origin = info["origin"]
	cell = CELL
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


# Texture del segnalino "<id>-f.png" da assets/counters/, o null se manca
# (caricata una volta sola). Cosi' la build web senza i PNG ripiega sui
# cerchietti, mentre in locale compaiono le pedine vere.
func _counter_tex(counter_id: String) -> Texture2D:
	if counter_id.is_empty():
		return null
	if not _counter_cache.has(counter_id):
		var path := "res://assets/counters/%s-f.png" % counter_id
		_counter_cache[counter_id] = load(path) if ResourceLoader.exists(path) else null
	return _counter_cache[counter_id]


func _draw() -> void:
	if state == null:
		return
	var font := ThemeDB.fallback_font
	var radius := cell.x / 1.5  # raggio centro-vertice
	if board != null:
		draw_texture(board, Vector2.ZERO)
	else:
		_draw_procedural_terrain(font, radius)
	# Hex suggeriti (bersagli di fuoco in rosso, mosse in verde)
	for h in cue_hexes:
		var cc := hex_center(h.x, h.y)
		var pts := _hex_points(cc, radius * 0.9)
		draw_colored_polygon(pts, Color(cue_color.r, cue_color.g, cue_color.b, 0.22))
		draw_polyline(_closed(pts), cue_color, radius * 0.07)
	# Evidenziazione dell'hex selezionato
	if highlight_hex.x > -99:
		var hc := hex_center(highlight_hex.x, highlight_hex.y)
		draw_polyline(_closed(_hex_points(hc, radius * 0.96)),
			Color(1.0, 1.0, 0.3, 0.9), radius * 0.06)
	# Segnalini. Un Enemy non Known mostra il retro generico (dummy): il
	# giocatore sa che c'e' qualcosa, non chi sia ne' cosa fara'.
	for c in state.characters:
		if c.is_dead():
			continue
		var hidden := c.side == D.Side.ENEMY and not c.known
		var center := hex_center(c.position.x, c.position.y)
		if c == selected:
			draw_circle(center, radius * 0.62, Color(1.0, 1.0, 0.3, 0.85))
		# Segnalino vero se disponibile (dummy se nemico non identificato),
		# altrimenti cerchietto di ripiego (build web senza i PNG).
		var counter_id: String = DUMMY_BY_TEAM.get(c.team, "GE-RedTeam-Dummy-1") if hidden else c.counter
		var tex := _counter_tex(counter_id)
		if tex != null:
			var s := radius * 1.5
			draw_texture_rect(tex, Rect2(center - Vector2(s, s) * 0.5, Vector2(s, s)), false)
		else:
			draw_circle(center, radius * 0.45,
				Color(0.30, 0.30, 0.30) if hidden else SIDE_COLORS[c.side])
			draw_circle(center, radius * 0.45, Color(0, 0, 0, 0.6), false, radius * 0.04)
			draw_string(font, center + Vector2(-radius * 0.15, radius * 0.15),
				"?" if hidden else c.display_name.substr(0, 1),
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(radius * 0.42), Color.WHITE)
		if c.side == D.Side.FRIENDLY and c.spotted:
			draw_circle(center + Vector2(radius * 0.45, -radius * 0.45),
				radius * 0.12, Color(0.9, 0.15, 0.15))
		# Etichetta dell'ordine (finche' non useremo i segnalini ordine).
		if c.has_order and not hidden:
			var label: String = D.ORDER_NAMES[c.order]
			if not c.order_move.is_empty():
				label += " " + c.order_move
			draw_string(font, center + Vector2(-radius * 0.9, radius * 0.92),
				label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(radius * 0.3),
				Color(0.95, 0.95, 0.2))


func _draw_procedural_terrain(font: Font, radius: float) -> void:
	# Tre passate: prima tutti i riempimenti, poi le decorazioni (cosi'
	# cio' che sborda da un hex non viene coperto dal vicino), infine i
	# bordi e le etichette delle coordinate.
	for key in state.map:
		var hex: GameState.MapHex = state.map[key]
		var c := _key_to_cell(key)
		draw_colored_polygon(_hex_points(hex_center(c.x, c.y), radius),
			BASE_COLORS.get(hex.terrain, Color.MAGENTA))
	for key in state.map:
		var hex2: GameState.MapHex = state.map[key]
		var c2 := _key_to_cell(key)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(key)
		_draw_feature(hex_center(c2.x, c2.y), radius, hex2.terrain, rng)
	for key in state.map:
		var c3 := _key_to_cell(key)
		var center := hex_center(c3.x, c3.y)
		draw_polyline(_closed(_hex_points(center, radius)), Color(0, 0, 0, 0.18), 1.0)
		draw_string(font, center + Vector2(-radius * 0.42, -radius * 0.60),
			"%02d.%02d" % [c3.x, c3.y], HORIZONTAL_ALIGNMENT_LEFT, -1,
			maxi(8, int(radius * 0.22)), Color(0, 0, 0, 0.32))


# Decorazione procedurale di un hex secondo il terreno. Il rng e' seminato
# da (col,row), quindi le feature sono stabili tra un redraw e l'altro.
func _draw_feature(center: Vector2, radius: float, terrain: int, rng: RandomNumberGenerator) -> void:
	match terrain:
		D.Terrain.TREES: _draw_canopies(center, radius, rng, 5)
		D.Terrain.ORCHARD: _draw_canopies(center, radius, rng, 3)
		D.Terrain.HEDGEROW: _draw_hedge(center, radius, rng, C_HEDGE, radius * 0.40)
		D.Terrain.BOCAGE: _draw_hedge(center, radius, rng, C_BOCAGE, radius * 0.55)
		D.Terrain.ROCKS: _draw_rocks(center, radius, rng, 5)
		D.Terrain.RUBBLE: _draw_rocks(center, radius, rng, 7)
		D.Terrain.BUILDING: _draw_building(center, radius, rng)
		D.Terrain.STREAM: _draw_band(center, radius, rng, C_WATER, radius * 0.5)
		D.Terrain.WALL: _draw_band(center, radius, rng, C_WALL, radius * 0.2)
		D.Terrain.LOGS: _draw_logs(center, radius, rng)
		D.Terrain.MARSH: _draw_marsh(center, radius, rng)
		D.Terrain.DEPRESSION: _draw_rings(center, radius)
		D.Terrain.CRATER: _draw_crater(center, radius)
		D.Terrain.FOXHOLE: _draw_foxhole(center, radius)
		D.Terrain.FIELD: _draw_furrows(center, radius, rng)
		D.Terrain.LONG_GRASS: _draw_grass(center, radius, rng)


func _draw_canopies(center: Vector2, radius: float, rng: RandomNumberGenerator, n: int) -> void:
	for i in n:
		var off := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * radius * 0.42
		var rad := radius * rng.randf_range(0.30, 0.44)
		draw_circle(center + off, rad, C_CANOPY)
		draw_circle(center + off - Vector2(rad, rad) * 0.22, rad * 0.55, C_CANOPY_HI)


func _draw_hedge(center: Vector2, radius: float, rng: RandomNumberGenerator, col: Color, width: float) -> void:
	var ang := rng.randi_range(0, 2) * PI / 3.0  # orientata come un lato hex
	var dir := Vector2(cos(ang), sin(ang))
	var perp := Vector2(-dir.y, dir.x)
	var f := center - dir * radius * 0.95
	var t := center + dir * radius * 0.95
	draw_line(f, t, col, width)
	for i in 3:
		var p := f.lerp(t, (i + 0.5) / 3.0) + perp * rng.randf_range(-1, 1) * width * 0.25
		draw_circle(p, width * 0.6, col)


func _draw_rocks(center: Vector2, radius: float, rng: RandomNumberGenerator, n: int) -> void:
	for i in n:
		var off := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * radius * 0.5
		var rad := radius * rng.randf_range(0.14, 0.26)
		draw_circle(center + off, rad, C_ROCK)
		draw_circle(center + off - Vector2(rad, rad) * 0.25, rad * 0.5, C_ROCK_HI)
		draw_arc(center + off, rad, 0, TAU, 10, Color(0, 0, 0, 0.30), 1.0)


func _draw_building(center: Vector2, radius: float, rng: RandomNumberGenerator) -> void:
	var ang := rng.randf_range(-0.3, 0.3)
	var hw := radius * 0.60
	var hh := radius * 0.45
	var pts := PackedVector2Array()
	for corner in [Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)]:
		pts.append(center + corner.rotated(ang))
	draw_colored_polygon(pts, C_ROOF)
	draw_polyline(_closed(pts), Color(0, 0, 0, 0.55), 2.0)
	draw_line(center + Vector2(-hw, 0).rotated(ang), center + Vector2(hw, 0).rotated(ang),
		Color(0, 0, 0, 0.35), 1.5)


func _draw_band(center: Vector2, radius: float, rng: RandomNumberGenerator, col: Color, width: float) -> void:
	var ang := rng.randi_range(0, 2) * PI / 3.0
	var dir := Vector2(cos(ang), sin(ang))
	draw_line(center - dir * radius, center + dir * radius, col, width)


func _draw_logs(center: Vector2, radius: float, rng: RandomNumberGenerator) -> void:
	var ang := rng.randf_range(0, PI)
	var dir := Vector2(cos(ang), sin(ang))
	var perp := Vector2(-dir.y, dir.x)
	for i in 3:
		var o := perp * (i - 1) * radius * 0.28
		draw_line(center + o - dir * radius * 0.55, center + o + dir * radius * 0.55,
			C_LOG, radius * 0.12)


func _draw_marsh(center: Vector2, radius: float, rng: RandomNumberGenerator) -> void:
	for i in 4:
		var off := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * radius * 0.45
		draw_circle(center + off, radius * rng.randf_range(0.12, 0.20), C_WATER)
	for i in 5:
		var b := center + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * radius * 0.5
		draw_line(b, b + Vector2(0, -radius * 0.25), C_GRASS_DK, 1.5)


func _draw_rings(center: Vector2, radius: float) -> void:
	for s in [0.70, 0.45]:
		draw_arc(center, radius * s, 0, TAU, 20, C_DIRT_DK, 2.0)


func _draw_crater(center: Vector2, radius: float) -> void:
	draw_circle(center, radius * 0.55, C_DIRT)
	draw_circle(center, radius * 0.32, C_DIRT_DK)
	draw_arc(center, radius * 0.55, 0, TAU, 20, Color(0, 0, 0, 0.30), 1.5)


func _draw_foxhole(center: Vector2, radius: float) -> void:
	draw_circle(center, radius * 0.30, C_DIRT)
	draw_circle(center, radius * 0.18, C_DIRT_DK)


func _draw_furrows(center: Vector2, radius: float, rng: RandomNumberGenerator) -> void:
	var ang := rng.randf_range(0, PI)
	var dir := Vector2(cos(ang), sin(ang))
	var perp := Vector2(-dir.y, dir.x)
	for i in range(-2, 3):
		var o := perp * (i * radius * 0.22)
		draw_line(center + o - dir * radius * 0.70, center + o + dir * radius * 0.70,
			C_FURROW, 1.5)


func _draw_grass(center: Vector2, radius: float, rng: RandomNumberGenerator) -> void:
	for i in 8:
		var b := center + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * radius * 0.55
		draw_line(b, b + Vector2(rng.randf_range(-0.2, 0.2), -1) * radius * 0.22, C_GRASS_DK, 1.5)


static func _key_to_cell(key: String) -> Vector2i:
	var p := key.split(",")
	return Vector2i(int(p[0]), int(p[1]))


# I sei vertici di un esagono flat-top attorno a un centro.
static func _hex_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(6):
		var angle := PI / 3.0 * i  # 0, 60, 120... gradi: vertice a destra
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	return points + PackedVector2Array([points[0]])
