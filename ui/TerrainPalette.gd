## Tavolozza terreni dell'editor mappa: un'unica immagine (assets/menu/
## palette_terrain.png) con sopra le tessere cliccabili. Niente pulsanti
## separati: il click viene mappato sulla tessera piu' vicina e l'evidenziazione
## (anello colorato) viene disegnata sopra l'immagine. Tre gruppi indipendenti:
##   - terreno  (esagoni + segnalini quadrati Foxhole/Rubble/Crater/Fortified/Trench)
##   - elevazione (colonna Level 0..3, imposta hex.level)
##   - filo spinato (Wire): ciclo none -> posa -> rimuovi
class_name TerrainPalette
extends Control

const D := preload("res://engine/Domain.gd")

# Dimensione nativa dell'immagine palette (px).
const NATIVE := Vector2(1182.0, 881.0)

signal terrain_picked(terrain: int)   # -1 = nessuno
signal level_picked(level: int)       # -1 = nessuno
signal wire_picked(mode: int)         # -1 nessuno, 1 posa, 0 rimuovi

var _tex: Texture2D
# Ogni tessera: {kind, value, shape, c (centro in px nativi)}.
var _tiles: Array = []

var sel_terrain: int = -1
var sel_level: int = -1
var sel_wire: int = -1   # -1 nessuno, 1 posa, 0 rimuovi


func _ready() -> void:
	_tex = load("res://assets/menu/palette_terrain.png")
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_tiles()
	queue_redraw()


func _build_tiles() -> void:
	# Segnalini quadrati (colonna sinistra).
	_add("terrain", D.Terrain.FOXHOLE, "square", 78, 86)
	_add("terrain", D.Terrain.RUBBLE, "square", 78, 228)
	_add("terrain", D.Terrain.CRATER, "square", 78, 370)
	_add("terrain", D.Terrain.FORTIFIED_BUILDING, "square", 78, 512)
	_add("terrain", D.Terrain.TRENCH, "square", 78, 654)
	_add("wire", 1, "square", 78, 796)
	# Esagoni terreno (colonne interne).
	_add("terrain", D.Terrain.ROCKS, "hex", 234, 110)
	_add("terrain", D.Terrain.BUILDING, "hex", 234, 322)
	_add("terrain", D.Terrain.TREES, "hex", 234, 533)
	_add("terrain", D.Terrain.MARSH, "hex", 234, 744)
	_add("terrain", D.Terrain.HEDGEROW, "hex", 477, 218)
	_add("terrain", D.Terrain.WALL, "hex", 477, 430)
	_add("terrain", D.Terrain.LONG_GRASS, "hex", 477, 641)
	_add("terrain", D.Terrain.DEPRESSION, "hex", 678, 110)
	_add("terrain", D.Terrain.STREAM, "hex", 678, 322)
	_add("terrain", D.Terrain.ORCHARD, "hex", 678, 533)
	_add("terrain", D.Terrain.LOGS, "hex", 678, 744)
	_add("terrain", D.Terrain.FIELD, "hex", 850, 218)
	_add("terrain", D.Terrain.FOUNTAIN, "hex", 850, 430)
	_add("terrain", D.Terrain.BOCAGE, "hex", 850, 641)
	# Colonna elevazione (Level 0..3).
	_add("level", 0, "hex", 1031, 110)
	_add("level", 1, "hex", 1031, 322)
	_add("level", 2, "hex", 1031, 533)
	_add("level", 3, "hex", 1031, 744)


func _add(kind: String, value: int, shape: String, px: float, py: float) -> void:
	_tiles.append({"kind": kind, "value": value, "shape": shape,
		"c": Vector2(px, py)})


# Dal centro nativo (px) alla posizione sul Control corrente.
func _to_local_px(c: Vector2) -> Vector2:
	return Vector2(c.x / NATIVE.x * size.x, c.y / NATIVE.y * size.y)


func _gui_input(event: InputEvent) -> void:
	var pos := Vector2.INF
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	elif event is InputEventScreenTouch and event.pressed:
		pos = event.position
	if pos == Vector2.INF:
		return
	var best := -1
	var best_d := INF
	for i in _tiles.size():
		var d2 := _to_local_px(_tiles[i]["c"]).distance_to(pos)
		if d2 < best_d:
			best_d = d2
			best = i
	# Soglia: ~mezza tessera (in px nativi -> scala media).
	var scale_avg := (size.x / NATIVE.x + size.y / NATIVE.y) * 0.5
	if best < 0 or best_d > 120.0 * scale_avg:
		return
	_apply(_tiles[best])
	accept_event()


func _apply(tile: Dictionary) -> void:
	match tile["kind"]:
		"terrain":
			sel_terrain = -1 if sel_terrain == tile["value"] else tile["value"]
			terrain_picked.emit(sel_terrain)
		"level":
			sel_level = -1 if sel_level == tile["value"] else tile["value"]
			level_picked.emit(sel_level)
		"wire":
			# Ciclo: nessuno -> posa (1) -> rimuovi (0) -> nessuno.
			sel_wire = 1 if sel_wire == -1 else (0 if sel_wire == 1 else -1)
			wire_picked.emit(sel_wire)
	queue_redraw()


func _draw() -> void:
	if _tex != null:
		draw_texture_rect(_tex, Rect2(Vector2.ZERO, size), false)
	for tile in _tiles:
		var col := Color.TRANSPARENT
		match tile["kind"]:
			"terrain":
				if tile["value"] == sel_terrain:
					col = Color(0.10, 0.85, 1.0)      # ciano
			"level":
				if tile["value"] == sel_level:
					col = Color(1.0, 0.85, 0.05)       # giallo
			"wire":
				if sel_wire == 1:
					col = Color(0.20, 1.0, 0.30)       # verde = posa
				elif sel_wire == 0:
					col = Color(1.0, 0.25, 0.25)       # rosso = rimuovi
		if col.a == 0.0:
			continue
		_draw_marker(tile, col)


func _draw_marker(tile: Dictionary, col: Color) -> void:
	var c := _to_local_px(tile["c"])
	var w := 0.18 * size.x   # mezza-larghezza tessera in px locali
	if tile["shape"] == "square":
		var hw := w * 0.55
		var r := Rect2(c - Vector2(hw, hw), Vector2(hw, hw) * 2.0)
		draw_rect(r, col, false, 4.0)
	else:
		var pts := PackedVector2Array()
		for k in 6:
			var ang := deg_to_rad(60.0 * k)
			pts.append(c + Vector2(cos(ang) * w, sin(ang) * w * 0.86))
		pts.append(pts[0])
		draw_polyline(pts, col, 4.0)
