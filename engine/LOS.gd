## Line of Sight (dal LOS Flowchart e dalle colonne Blocking/Height
## dell'Order-Terrain Chart).
##
## Tutte le altezze sono in MEZZI livelli (interi: 1 = mezzo livello,
## 2 = un livello) per evitare i float dove possibile.
##
## Schema: confronta i livelli dei due soldati (L1, L2) con l'altezza H
## del terreno interposto piu' alto; se i livelli differiscono, la
## formula dei blind hexes decide se il piu' basso e' nascosto:
##   blind = (H - S) / (T - H) + D
## con D che cresce con la distanza tra il piu' alto e l'ostacolo.
##
## Terreni "bassi" (S nel chart): bloccano (altezza 1/2) solo se uno dei
## due soldati ha ordine Sneak/Hide/Rally/Reload, altrimenti altezza 0.
## Depression: vale la nota dedicata del flowchart (vedi _depression_blocked).
class_name LOS
extends RefCounted

const D := preload("res://engine/Domain.gd")

const LOW_ORDERS := [D.Order.SNEAK, D.Order.HIDE, D.Order.RALLY, D.Order.RELOAD]

# Terreni bassi: altezza 1/2 solo con ordini "low" in gioco.
const LOW_TERRAIN := [
	D.Terrain.LONG_GRASS, D.Terrain.DEPRESSION, D.Terrain.LOGS,
	D.Terrain.CRATER, D.Terrain.FIELD, D.Terrain.FOXHOLE,
]

# Altezza del terreno bloccante, in mezzi livelli (chart, colonna HEIGHT).
const HEIGHT2 := {
	D.Terrain.ROCKS: 1, D.Terrain.BUILDING: 2, D.Terrain.MARSH: 1,
	D.Terrain.TREES: 2, D.Terrain.HEDGEROW: 1, D.Terrain.BOCAGE: 2,
	D.Terrain.WALL: 1, D.Terrain.ORCHARD: 2, D.Terrain.RUBBLE: 1,
}


static func _to_cube(h: Vector2i) -> Vector3i:
	var x := h.x
	var z := h.y - int((h.x + (h.x & 1)) / 2.0)
	return Vector3i(x, -x - z, z)


static func _from_cube(c: Vector3i) -> Vector2i:
	return Vector2i(c.x, c.z + int((c.x + (c.x & 1)) / 2.0))


# Gli hex attraversati dalla linea tra a e b, esclusi gli estremi.
static func hexes_between(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var ca := _to_cube(a)
	var cb := _to_cube(b)
	var n := Spotting.hex_distance(a, b)
	if n <= 1:
		return result
	for i in range(1, n):
		var t := float(i) / float(n)
		# nudge per non cadere esattamente sui bordi tra hex
		var fx := lerpf(ca.x + 1e-4, cb.x + 1e-4, t)
		var fy := lerpf(ca.y + 2e-4, cb.y + 2e-4, t)
		var fz := lerpf(ca.z - 3e-4, cb.z - 3e-4, t)
		result.append(_from_cube(_cube_round(fx, fy, fz)))
	return result


static func _cube_round(fx: float, fy: float, fz: float) -> Vector3i:
	var rx := roundf(fx)
	var ry := roundf(fy)
	var rz := roundf(fz)
	var dx := absf(rx - fx)
	var dy := absf(ry - fy)
	var dz := absf(rz - fz)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector3i(int(rx), int(ry), int(rz))


# Livello del suolo di un personaggio, in mezzi livelli.
static func _unit_level2(state: GameState, c: Character) -> int:
	var hex := state.hex_at(c.position.x, c.position.y)
	return (hex.level if hex != null else 0) * 2


# Altezza efficace di un hex interposto, in mezzi livelli.
static func _hex_height2(state: GameState, pos: Vector2i, low_active: bool) -> int:
	var hex := state.hex_at(pos.x, pos.y)
	if hex == null:
		return 0
	var base := hex.level * 2
	if hex.terrain == D.Terrain.DEPRESSION:
		return base  # interposta: "exists at level 0"
	if hex.terrain in LOW_TERRAIN:
		return base + (1 if low_active else 0)
	return base + int(HEIGHT2.get(hex.terrain, 0))


static func _has_low_order(c: Character) -> bool:
	return c.has_order and c.order in LOW_ORDERS


# La LOS tra i due personaggi e' libera?
static func clear(state: GameState, ca: Character, cb: Character) -> bool:
	var a := ca.position
	var b := cb.position
	var low_active := _has_low_order(ca) or _has_low_order(cb)
	# Nota Depression del flowchart, per ciascun soldato.
	if _depression_blocked(state, ca, cb) or _depression_blocked(state, cb, ca):
		return false
	var l1 := _unit_level2(state, ca)
	var l2 := _unit_level2(state, cb)
	var between := hexes_between(a, b)
	# H: ostacolo piu' alto; a parita', l'hex piu' lontano dal piu' alto.
	var t2 := maxi(l1, l2)
	var s2 := mini(l1, l2)
	var taller_pos := a if l1 >= l2 else b
	var shorter_pos := b if l1 >= l2 else a
	var h2 := -1000
	var h_pos := taller_pos
	for pos in between:
		var hh := _hex_height2(state, pos, low_active)
		var farther := Spotting.hex_distance(taller_pos, pos) \
			>= Spotting.hex_distance(taller_pos, h_pos)
		if hh > h2 or (hh == h2 and farther):
			h2 = hh
			h_pos = pos
	if between.is_empty():
		return true
	if l1 == l2:
		return l1 >= h2
	if h2 >= t2:
		return false
	if s2 >= h2:
		return true
	# Blind hexes = (H-S)/(T-H) + D
	var dist_th := Spotting.hex_distance(taller_pos, h_pos)
	var extra_d := maxi(0, int((dist_th - 1) / 5.0))
	var blind := int(floor(float(h2 - s2) / float(t2 - h2))) + extra_d
	return Spotting.hex_distance(h_pos, shorter_pos) > blind


# Nota Depression: un soldato in Depression con ordine "low" e' fuori
# LOS, salvo che l'osservatore sia abbastanza vicino per il suo livello
# (range <= livello+1) o che la LOS corra dentro una gola (2+ hex di
# Depression contigui sul percorso).
static func _depression_blocked(state: GameState, unit: Character, other: Character) -> bool:
	var hex := state.hex_at(unit.position.x, unit.position.y)
	if hex == null or hex.terrain != D.Terrain.DEPRESSION or not _has_low_order(unit):
		return false
	var dist := Spotting.hex_distance(unit.position, other.position)
	if dist <= int(_unit_level2(state, other) / 2.0) + 1:
		return false
	var run := 0
	for pos in hexes_between(unit.position, other.position):
		var h := state.hex_at(pos.x, pos.y)
		if h != null and h.terrain == D.Terrain.DEPRESSION:
			run += 1
			if run >= 2:
				return false
		else:
			run = 0
	return true
