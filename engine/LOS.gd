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

# Portata massima di visibilita' notturna (Rule 18.1).
const NIGHT_LOS_MAX := 5

# Trincea trattata come Depression per la LOS (Rule 27.4 / 27.8).
const DEPRESSION_LIKE := [D.Terrain.DEPRESSION, D.Terrain.TRENCH]

# Terreni "infossati": il suolo sta mezzo livello sotto il nominale
# (elevazione -1/2 = -1 in mezzi livelli). Depression/Stream/Trench.
const SUNKEN_TERRAINS := [D.Terrain.DEPRESSION, D.Terrain.STREAM, D.Terrain.TRENCH]

# Terreni bassi: altezza 1/2 solo con ordini "low" in gioco.
const LOW_TERRAIN := [
	D.Terrain.LONG_GRASS, D.Terrain.DEPRESSION, D.Terrain.LOGS,
	D.Terrain.CRATER, D.Terrain.FIELD, D.Terrain.FOXHOLE,
	D.Terrain.TRENCH,
]

# Altezza del terreno bloccante, in mezzi livelli (chart, colonna HEIGHT).
# Fountain: ostacolo 1/2 (Rule 27.1). Fortified Building: come Building.
const HEIGHT2 := {
	D.Terrain.ROCKS: 1, D.Terrain.BUILDING: 2, D.Terrain.MARSH: 1,
	D.Terrain.TREES: 2, D.Terrain.HEDGEROW: 1, D.Terrain.BOCAGE: 2,
	D.Terrain.WALL: 1, D.Terrain.ORCHARD: 2, D.Terrain.RUBBLE: 1,
	D.Terrain.FOUNTAIN: 1, D.Terrain.FORTIFIED_BUILDING: 2,
	# Abbazia (Rule 27.5): muri che bloccano dall'esterno (eccezione interna sotto).
	D.Terrain.ABBEY_EXTERIOR: 2, D.Terrain.ABBEY_INTERIOR: 2,
}


static func _to_cube(h: Vector2i) -> Vector3i:
	var x := h.x
	var z := h.y - int((h.x + (h.x & 1)) / 2.0)
	return Vector3i(x, -x - z, z)


static func _from_cube(c: Vector3i) -> Vector2i:
	return Vector2i(c.x, c.z + int((c.x + (c.x & 1)) / 2.0))


# Gli hex attraversati dalla linea tra a e b, esclusi gli estremi.
# IMPORTANTE: il percorso e' canonicalizzato (si traccia sempre dallo
# stesso estremo) perche' con linee esattamente sui bordi degli esagoni
# l'arrotondamento float di A->B e B->A puo' divergere di un hex,
# rendendo la LOS asimmetrica (X vede Y ma Y non vede X).
static func hexes_between(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	if b.x < a.x or (b.x == a.x and b.y < a.y):
		var tmp := a
		a = b
		b = tmp
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


# Livello del suolo di un hex (in mezzi livelli): nominale level*2, meno
# 1/2 livello se il terreno e' infossato (Depression/Stream/Trench).
static func _ground_level2(hex: GameState.MapHex) -> int:
	if hex == null:
		return 0
	var lv := hex.level * 2
	if hex.terrain in SUNKEN_TERRAINS:
		lv -= 1
	return lv


# Livello del suolo di un personaggio, in mezzi livelli.
static func _unit_level2(state: GameState, c: Character) -> int:
	return _ground_level2(state.hex_at(c.position.x, c.position.y))


# Livello del suolo di un hex, in mezzi livelli.
static func _hex_level2_at(state: GameState, pos: Vector2i) -> int:
	return _ground_level2(state.hex_at(pos.x, pos.y))


# Altezza efficace di un hex interposto, in mezzi livelli.
static func _hex_height2(state: GameState, pos: Vector2i, low_active: bool, both_abbey: bool = false) -> int:
	var hex := state.hex_at(pos.x, pos.y)
	if hex == null:
		return 0
	var base := _ground_level2(hex)
	if hex.terrain in SUNKEN_TERRAINS:
		return base  # infossata: suolo gia' -1/2, nessun ostacolo sopra
	# Abbazia (Rule 27.5): tra due hex d'abbazia la LOS non e' bloccata dai
	# muri dell'abbazia (vale il -1/hex sul WS, non un blocco).
	if both_abbey and Domain.is_abbey(hex.terrain):
		return base
	if hex.terrain in LOW_TERRAIN:
		return base + (1 if low_active else 0)
	return base + int(HEIGHT2.get(hex.terrain, 0))


static func _has_low_order(c: Character) -> bool:
	return c.has_order and c.order in LOW_ORDERS


# La LOS tra i due personaggi e' libera?
static func clear(state: GameState, ca: Character, cb: Character) -> bool:
	var low_active := _has_low_order(ca) or _has_low_order(cb)
	# Nota Depression del flowchart, per ciascun soldato.
	if _depression_blocked(state, ca, cb) or _depression_blocked(state, cb, ca):
		return false
	return clear_positions(state, ca.position, cb.position,
		_unit_level2(state, ca), _unit_level2(state, cb), low_active)


# LOS tra due HEX arbitrari (per lo strumento di verifica): livelli dal
# suolo, senza la regola della Depression che dipende dagli ordini.
static func clear_hexes(state: GameState, a: Vector2i, b: Vector2i) -> bool:
	return clear_positions(state, a, b,
		_hex_level2_at(state, a), _hex_level2_at(state, b), false)


static func clear_positions(state: GameState, a: Vector2i, b: Vector2i,
		l1: int, l2: int, low_active: bool) -> bool:
	# Limite di visibilita' del meteo (Rule 28.1): oltre il raggio, niente LOS.
	if state.max_los > 0 and Spotting.hex_distance(a, b) > state.max_los:
		return false
	# Notte (Rule 18.1): LOS max 5 hex fuori dalla luce.
	if state.night and Spotting.hex_distance(a, b) > NIGHT_LOS_MAX:
		if not Area.illuminated(state, a) and not Area.illuminated(state, b):
			return false
	var between := hexes_between(a, b)
	# Abbazia (Rule 27.5): tra due hex d'abbazia i muri non bloccano la LOS.
	var ha := state.hex_at(a.x, a.y)
	var hb := state.hex_at(b.x, b.y)
	var both_abbey := ha != null and hb != null \
		and Domain.is_abbey(ha.terrain) and Domain.is_abbey(hb.terrain)
	# H: ostacolo piu' alto; a parita', l'hex piu' lontano dal piu' alto.
	var t2 := maxi(l1, l2)
	var s2 := mini(l1, l2)
	var taller_pos := a if l1 >= l2 else b
	var shorter_pos := b if l1 >= l2 else a
	var h2 := -1000
	var h_pos := taller_pos
	for pos in between:
		var hh := _hex_height2(state, pos, low_active, both_abbey)
		var farther := Spotting.hex_distance(taller_pos, pos) \
			>= Spotting.hex_distance(taller_pos, h_pos)
		if hh > h2 or (hh == h2 and farther):
			h2 = hh
			h_pos = pos
	if between.is_empty():
		return true  # adiacenti: nessun esagono interposto, niente blocco
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
	if hex == null or hex.terrain not in DEPRESSION_LIKE or not _has_low_order(unit):
		return false
	var dist := Spotting.hex_distance(unit.position, other.position)
	if dist <= int(_unit_level2(state, other) / 2.0) + 1:
		return false
	var run := 0
	for pos in hexes_between(unit.position, other.position):
		var h := state.hex_at(pos.x, pos.y)
		if h != null and h.terrain in DEPRESSION_LIKE:
			run += 1
			if run >= 2:
				return false
		else:
			run = 0
	return true
