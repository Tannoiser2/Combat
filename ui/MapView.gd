## Vista 2D della mappa: disegna la griglia esagonale e i segnalini
## leggendo il GameState. SOLO rappresentazione: nessuna logica di gioco.
##
## Esagoni flat-top in colonne sfalsate, come le mappe di Combat!
## (numerazione col.riga, colonne pari piu' in alto). Finche' non abbiamo
## le scansioni delle mappe come texture, il terreno e' reso a colori;
## la geometria (hex -> pixel) restera' la stessa anche con la mappa vera.
class_name MapView
extends Node2D

const D := preload("res://engine/Domain.gd")

const HEX_SIZE := 46.0  # raggio centro-vertice
const SQRT3 := sqrt(3.0)

# Colori provvisori del terreno
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
}
const SIDE_COLORS := {
	D.Side.FRIENDLY: Color(0.18, 0.32, 0.60),
	D.Side.ENEMY: Color(0.55, 0.55, 0.52),  # feldgrau
}

var state: GameState


# Centro in pixel di una cella (col, row).
static func hex_center(col: int, row: int) -> Vector2:
	var x := HEX_SIZE * 1.5 * col
	# Colonne dispari mezzo passo piu' in basso (come le mappe stampate).
	var y := HEX_SIZE * SQRT3 * (row + (0.5 if col % 2 == 1 else 0.0))
	return Vector2(x, y)


func _draw() -> void:
	if state == null:
		return
	var font := ThemeDB.fallback_font
	# Terreno
	for key in state.map:
		var parts: PackedStringArray = key.split(",")
		var col := int(parts[0])
		var row := int(parts[1])
		var hex: GameState.MapHex = state.map[key]
		var center := hex_center(col, row)
		var points := _hex_points(center)
		draw_colored_polygon(points, TERRAIN_COLORS.get(hex.terrain, Color.MAGENTA))
		draw_polyline(points + PackedVector2Array([points[0]]), Color(0, 0, 0, 0.25), 1.5)
		draw_string(font, center + Vector2(-14, -HEX_SIZE * 0.55),
			"%02d.%02d" % [col, row], HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(0, 0, 0, 0.45))
	# Segnalini
	for c in state.characters:
		if c.is_dead():
			continue
		var center := hex_center(c.position.x, c.position.y)
		draw_circle(center, HEX_SIZE * 0.45, SIDE_COLORS[c.side])
		draw_circle(center, HEX_SIZE * 0.45, Color(0, 0, 0, 0.6), false, 2.0)
		draw_string(font, center + Vector2(-HEX_SIZE * 0.3, 5),
			c.display_name.substr(0, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		if c.has_order:
			draw_string(font, center + Vector2(-HEX_SIZE * 0.85, HEX_SIZE * 0.85),
				D.ORDER_NAMES[c.order], HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				Color(0.1, 0.1, 0.1))


# I sei vertici di un esagono flat-top attorno a un centro.
static func _hex_points(center: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(6):
		var angle := PI / 3.0 * i  # 0, 60, 120... gradi: vertice a destra
		points.append(center + Vector2(cos(angle), sin(angle)) * HEX_SIZE)
	return points
