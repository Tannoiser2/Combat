## Spotting (Rule 12), trascritto dallo Spotting Chart.
##
## Il check e' una prova di TQ dello spotter: 1d10 <= TQ effettiva
## + modificatore del bersaglio (terreno x gruppo di ordini, dal chart)
## + modificatore di gittata. Se riesce: un Enemy diventa Known, un
## Friendly diventa Spotted.
## La LOS e' implementata in LOS.gd (clear_positions).
class_name Spotting
extends RefCounted

const D := preload("res://engine/Domain.gd")

# Colonne del chart: gruppo di ordini del BERSAGLIO.
# 0: Hide/Rally/Reload   1: Sneak
# 2: Duck Back/Aimed-Rapid Fire/Suppressive/No Order
# 3: Run & Gun/Sprint/Berserk Charge
# 4: Grenade/Evade/Rifle Grenade/Smoke Grenade
# 5: Plan/Search/Melee   6: Medical Aid/Carry-Drag
const ORDER_GROUP := {
	D.Order.HIDE: 0, D.Order.RALLY: 0, D.Order.RELOAD: 0,
	D.Order.SNEAK: 1,
	D.Order.DUCK_BACK: 2, D.Order.AIMED_FIRE: 2, D.Order.RAPID_FIRE: 2,
	D.Order.SUPPRESSIVE_FIRE: 2, D.Order.GUARD: 2,
	D.Order.RUN_AND_GUN: 3, D.Order.SPRINT: 3, D.Order.CHARGE: 3,
	D.Order.GRENADE: 4, D.Order.EVADE: 4,
	D.Order.RIFLE_GRENADE: 4, D.Order.SMOKE_GRENADE: 4,
	D.Order.PLAN: 5, D.Order.SEARCH: 5, D.Order.MELEE: 5,
	D.Order.MEDICAL_AID: 6, D.Order.CARRY_DRAG: 6,
}
const NO_ORDER_GROUP := 2

# Abbazia (Rule 27.5): spotting di un bersaglio in abbazia, a seconda che
# l'osservatore sia dentro o fuori. Ultima colonna stimata (manca dal chart).
const ABBEY_SPOT_OUTSIDE := [-5, -4, -3, -2, -2, -3, -3]
const ABBEY_SPOT_INSIDE := [-3, -2, -1, 0, 0, 0, 0]

# Righe del chart: terreno del bersaglio -> modificatori per gruppo.
# I livelli Open usano tutti la riga OPEN; Stream non e' nel chart
# (trattato come Open, TODO verificare col regolamento).
const TERRAIN_MOD := {
	D.Terrain.OPEN_LEVEL_0: [-2, -1, 0, 2, 1, 0, 0],
	D.Terrain.OPEN_LEVEL_1: [-2, -1, 0, 2, 1, 0, 0],
	D.Terrain.OPEN_LEVEL_2: [-2, -1, 0, 2, 1, 0, 0],
	D.Terrain.OPEN_LEVEL_3: [-2, -1, 0, 2, 1, 0, 0],
	D.Terrain.STREAM: [-2, -1, 0, 2, 1, 0, 0],
	D.Terrain.ROCKS: [-5, -4, -3, -1, -2, -2, -2],
	D.Terrain.BUILDING: [-5, -4, -3, -2, -1, -2, -2],
	D.Terrain.MARSH: [-4, -3, -2, -1, -1, -2, -2],
	D.Terrain.TREES: [-3, -2, -2, 0, -1, -2, -2],
	D.Terrain.HEDGEROW: [-3, -2, -1, 0, -1, -1, -1],
	D.Terrain.BOCAGE: [-4, -3, -2, -1, -1, -2, -2],
	D.Terrain.WALL: [-4, -3, -2, -1, -1, -2, -2],
	D.Terrain.LONG_GRASS: [-2, -1, 0, 0, 0, 0, 0],
	D.Terrain.DEPRESSION: [-4, -3, -2, -1, -1, -1, -1],
	D.Terrain.ORCHARD: [-4, -3, -2, -1, -1, -1, -1],
	D.Terrain.LOGS: [-4, -3, -2, -1, -1, -1, -1],
	D.Terrain.CRATER: [-4, -3, -2, -1, -1, -1, -1],
	D.Terrain.FIELD: [-3, -2, -1, 0, 0, 0, 0],
	D.Terrain.RUBBLE: [-5, -4, -3, -1, -2, -2, -2],
	D.Terrain.FOXHOLE: [-4, -3, -2, -1, -1, -1, -1],
	# Volume 2, Rule 27 (Spotting Chart). Fortified = Building, Trench = Depression.
	# NOTA: sullo Spotting Chart ufficiale la riga Fortified pare avere la colonna
	# Evade a -2 (non -1 come Building) e la riga Trench valori piu' duri della
	# Depression; il regolamento (27.2/27.4) rimanda pero' a Building/Depression,
	# quindi qui si segue il testo delle regole. Da riverificare sul chart fisico.
	D.Terrain.FOUNTAIN: [-2, -2, -1, 0, -1, -1, -1],
	D.Terrain.FORTIFIED_BUILDING: [-5, -4, -3, -2, -1, -2, -2],
	D.Terrain.TRENCH: [-4, -3, -2, -1, -1, -1, -1],
}


# Distanza in hex sulla griglia (flat-top, colonne pari mezzo passo giu':
# offset "even-q" -> coordinate cubiche).
static func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var ax := a.x
	var az := a.y - int((a.x + (a.x & 1)) / 2.0)
	var bx := b.x
	var bz := b.y - int((b.x + (b.x & 1)) / 2.0)
	var ay := -ax - az
	var by := -bx - bz
	return int((abs(ax - bx) + abs(ay - by) + abs(az - bz)) / 2.0)


# Modificatore di gittata: +2 adiacente, a scalare; -1 ogni 10 hex extra.
static func range_modifier(dist: int) -> int:
	if dist <= 1:
		return 2
	if dist <= 4:
		return 1
	if dist <= 10:
		return 0
	return -1 - int((dist - 11) / 10.0)


# Modificatore del bersaglio: terreno x gruppo di ordini. Se l'osservatore
# guarda attraverso un hexside (siepe/muro) sul bordo del bersaglio, vale
# il modificatore piu' protettivo.
static func target_modifier(state: GameState, target: Character, spotter: Character = null) -> int:
	var hex := state.hex_at(target.position.x, target.position.y)
	var terrain: int = hex.terrain if hex != null else D.Terrain.OPEN_LEVEL_0
	var group: int = ORDER_GROUP.get(target.order, NO_ORDER_GROUP) \
		if target.has_order else NO_ORDER_GROUP
	# Abbazia (Rule 27.5): copertura allo spotting a seconda che l'osservatore
	# sia dentro o fuori dall'abbazia.
	if D.is_abbey(terrain):
		var inside := spotter != null and Fire._in_abbey(state, spotter.position)
		return (ABBEY_SPOT_INSIDE if inside else ABBEY_SPOT_OUTSIDE)[group]
	var mod: int = TERRAIN_MOD[terrain][group]
	if spotter != null:
		var side := Fire._entry_hexside(state, spotter.position, target.position)
		if side >= 0:
			mod = mini(mod, TERRAIN_MOD[side][group])
	return mod


# Tentativo di spotting. Applica l'esito (Known/Spotted) e ritorna
# {roll, threshold, dist, success}; senza LOS non c'e' tentativo.
static func attempt(state: GameState, spotter: Character, target: Character) -> Dictionary:
	if not LOS.clear(state, spotter, target):
		return {"roll": -1, "threshold": -1, "dist": -1, "success": false, "blocked": true}
	var dist := hex_distance(spotter.position, target.position)
	# Eagle Eyes (Rule 24): +1 alla TQ effettiva per lo spotting, max 8.
	var tq := Checks.effective_tq(spotter)
	if spotter.has_skill(Character.SKILL_EAGLE_EYES):
		tq = mini(tq + 1, 8)
	# Rule 31.7: boccaporto chiuso -> -2 TQ E spotting solo nel front arc del veicolo.
	if spotter.is_vehicle and spotter.is_buttoned_up:
		tq -= 2
		var vdir: Vector3i = Move.CUBE_DIRS[(spotter.facing - 1) % 6]
		var delta: Vector3i = Move.to_cube(target.position) - Move.to_cube(spotter.position)
		if vdir.x * delta.x + vdir.y * delta.y + vdir.z * delta.z <= 0:
			return {"roll": -1, "threshold": -1, "dist": -1, "success": false}
	var threshold := tq \
		+ target_modifier(state, target, spotter) + range_modifier(dist)
	# Winter Camouflage (Rule 28.2): -1 a individuare il bersaglio sulla neve.
	if target.has_skill(Character.SKILL_WINTER_CAMO) \
			and state.ground in [Weather.Ground.SNOW, Weather.Ground.DEEP_SNOW]:
		threshold -= 1
	threshold += Fire._smoke_modifier(state, spotter.position, target.position)
	var roll := Checks.roll_d10(state.rng)
	var success := roll <= threshold
	if success:
		if target.side == D.Side.ENEMY:
			target.known = true
			target.alerted = true
		else:
			target.spotted = true
	return {"roll": roll, "threshold": threshold, "dist": dist, "success": success}
