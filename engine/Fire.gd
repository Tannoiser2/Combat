## Fire Resolution (dal Fire Resolution Chart v1.1 e dall'Order/Terrain
## Chart "MODIFIES WS").
##
## Procedura per ogni attacco:
## 1. modificatori al WS (terreno x ordine del bersaglio, gittata
##    dell'arma, ordine del tiratore, ferite, morale; TODO fumo/notte/
##    meteo/filo spinato/effetti carta);
## 2. 1d10: 0 naturale = colpito (e morale tiratore +1 se l'esito e'
##    ferita o morte, mai fino a Berserk); <= WS = colpito; 9 naturale =
##    mancato + Low Ammo (poi No Ammo; pistole esenti);
## 3. ferita: si pesca una Friendly Card e si usa il timbro
##    (Close Call -> MC; Light/Bad Wound -> marker + Duck Back + WMC;
##    KIA -> morto). Fuoco di soppressione e celle "M" del chart: solo MC.
## 4. MC che riduce il morale -> l'ordine del bersaglio diventa Duck Back.
class_name Fire
extends RefCounted

const D := preload("res://engine/Domain.gd")

# Gruppi di ordini del bersaglio per la matrice WS (nota: diversi dallo
# Spotting Chart - Evade sta con Sneak, "no order" sta con le granate).
const WS_GROUP := {
	D.Order.HIDE: 0, D.Order.RALLY: 0, D.Order.RELOAD: 0,
	D.Order.SNEAK: 1, D.Order.EVADE: 1,
	D.Order.DUCK_BACK: 2, D.Order.AIMED_FIRE: 2, D.Order.RAPID_FIRE: 2,
	D.Order.SUPPRESSIVE_FIRE: 2, D.Order.GUARD: 2,
	D.Order.RUN_AND_GUN: 3, D.Order.SPRINT: 3, D.Order.CHARGE: 3,
	D.Order.GRENADE: 4, D.Order.RIFLE_GRENADE: 4, D.Order.SMOKE_GRENADE: 4,
	D.Order.PLAN: 5, D.Order.SEARCH: 5, D.Order.MELEE: 5,
	D.Order.MEDICAL_AID: 6, D.Order.CARRY_DRAG: 6,
}
const NO_ORDER_GROUP := 4

# Terreno del bersaglio x gruppo -> modificatore WS dell'attaccante.
const WS_MOD := {
	D.Terrain.OPEN_LEVEL_0: [-2, -1, 0, -1, 1, 0, 0],
	D.Terrain.OPEN_LEVEL_1: [-2, -1, 0, -1, 1, 0, 0],
	D.Terrain.OPEN_LEVEL_2: [-2, -1, 0, -1, 1, 0, 0],
	D.Terrain.OPEN_LEVEL_3: [-2, -1, 0, -1, 1, 0, 0],
	D.Terrain.STREAM: [-2, -1, 0, -1, 1, 0, 0],
	D.Terrain.ROCKS: [-5, -3, -2, -2, -2, -2, -2],
	D.Terrain.BUILDING: [-5, -3, -2, -2, -1, -2, -2],
	D.Terrain.MARSH: [-3, -2, -2, -1, -1, -2, -2],
	D.Terrain.TREES: [-4, -2, -2, -1, -1, -2, -2],
	D.Terrain.HEDGEROW: [-2, -2, -1, -1, -1, -1, -1],
	D.Terrain.BOCAGE: [-4, -3, -2, -2, -2, -2, -2],
	D.Terrain.WALL: [-4, -2, -2, -1, -1, -2, -2],
	D.Terrain.LONG_GRASS: [-2, -1, 0, 0, 0, 0, 0],
	D.Terrain.DEPRESSION: [-4, -2, -1, -1, -1, -1, -1],
	D.Terrain.ORCHARD: [-4, -2, -1, -1, -1, -1, -1],
	D.Terrain.LOGS: [-4, -2, -1, -1, -1, -1, -1],
	D.Terrain.CRATER: [-4, -2, -1, -1, -1, -1, -1],
	D.Terrain.FIELD: [-3, -1, 0, 0, 0, 0, 0],
	D.Terrain.RUBBLE: [-5, -3, -2, -2, -2, -2, -2],
	D.Terrain.FOXHOLE: [-4, -2, 0, 0, -1, -1, -1],
}

# Celle "M" del chart: un bersaglio con ordini Hide/Rally/Reload in
# copertura dura subisce solo un Morale Check, mai ferite.
const MC_ONLY := [
	[D.Terrain.ROCKS, 0], [D.Terrain.BUILDING, 0],
	[D.Terrain.WALL, 0], [D.Terrain.RUBBLE, 0],
]

const WOUND_MOD := {D.Wound.LIGHT: -1, D.Wound.BAD: -3}
const MORALE_WS_MOD := {
	D.Morale.BERSERK: 1,
	D.Morale.CAUTIOUS: -1,
	D.Morale.SHAKEN: -2,
}


# Il tiratore puo' ingaggiare il bersaglio? (arma, gittata, LOS, munizioni)
static func can_fire(state: GameState, firer: Character, target: Character, weapon: String) -> bool:
	if firer.no_ammo:
		return false
	var dist := Spotting.hex_distance(firer.position, target.position)
	if Weapons.range_ws_modifier(weapon, dist) == null:
		return false
	return LOS.clear(state, firer, target)


# Un'azione di fuoco completa: ROF attacchi in sequenza sul bersaglio.
static func fire_action(state: GameState, firer: Character, target: Character, weapon: String) -> void:
	var rof := int(Weapons.info(weapon)["rof"])
	for i in range(rof):
		if target.is_dead() or firer.no_ammo:
			return
		_resolve_attack(state, firer, target, weapon)


static func _resolve_attack(state: GameState, firer: Character, target: Character, weapon: String) -> void:
	var dist := Spotting.hex_distance(firer.position, target.position)
	var hex := state.hex_at(target.position.x, target.position.y)
	var terrain: int = hex.terrain if hex != null else D.Terrain.OPEN_LEVEL_0
	var group: int = WS_GROUP.get(target.order, NO_ORDER_GROUP) \
		if target.has_order else NO_ORDER_GROUP
	var suppressive := firer.has_order and firer.order == D.Order.SUPPRESSIVE_FIRE

	var ws: int = firer.weapon_skills[weapon]
	ws += int(Weapons.range_ws_modifier(weapon, dist))
	if not suppressive:
		ws += WS_MOD[terrain][group]
	if firer.has_order:
		ws += int(Orders.FIRE_WS_MOD.get(firer.order, 0))
	for w in firer.wounds:
		ws += WOUND_MOD[w]
	ws += int(MORALE_WS_MOD.get(firer.morale, 0))
	# TODO: fumo, notte, meteo, filo spinato, effetti delle carte.

	var roll := Checks.roll_d10(state.rng)
	if roll == 9:
		_log(state, "%s spara a %s con %s: 9 naturale, mancato!" % [
			firer.display_name, target.display_name, weapon])
		_spend_ammo(state, firer, weapon)
		return
	# TODO nota 2 del chart: WS modificato < 0 richiede un TQC di conferma.
	if roll != 0 and roll > ws:
		_log(state, "%s spara a %s con %s: tira %d > WS %d, mancato" % [
			firer.display_name, target.display_name, weapon, roll, ws])
		return

	_log(state, "%s COLPISCE %s con %s (tira %d, WS %d)" % [
		firer.display_name, target.display_name, weapon, roll, ws])
	var mc_only := suppressive or [terrain, group] in MC_ONLY
	var wounded_or_killed := false
	if mc_only:
		_hit_morale_check(state, target)
	else:
		wounded_or_killed = _resolve_wound(state, target)
	# 0 naturale: il tiratore si esalta se ha fatto danno (mai Berserk).
	if roll == 0 and wounded_or_killed:
		firer.morale = D.raise_morale(firer.morale, 1, D.Morale.AGGRESSIVE)
		_log(state, "%s si esalta: morale %s" % [
			firer.display_name, D.MORALE_NAMES[firer.morale]])


# Pesca della ferita con una Friendly Card. Ritorna true se ferito/ucciso.
static func _resolve_wound(state: GameState, target: Character) -> bool:
	var serial := state.draw_friendly_card()
	state.friendly_discard.append(serial)
	var wound: int = FriendlyCards.wound_of(serial)
	match wound:
		FriendlyCards.WoundDraw.CLOSE_CALL:
			_log(state, "  pesca carta %d: Close Call" % serial)
			_hit_morale_check(state, target)
			return false
		FriendlyCards.WoundDraw.KIA:
			_log(state, "  pesca carta %d: K.I.A. - %s e' morto" % [
				serial, target.display_name])
			target.wounds.append(D.Wound.BAD)
			while not target.is_dead():
				target.wounds.append(D.Wound.BAD)
			target.clear_order()
			return true
		_:
			var w: int = D.Wound.LIGHT if wound == FriendlyCards.WoundDraw.LIGHT_WOUND else D.Wound.BAD
			target.wounds.append(w)
			_log(state, "  pesca carta %d: %s per %s" % [serial,
				"Light Wound" if w == D.Wound.LIGHT else "Bad Wound",
				target.display_name])
			if target.is_dead():
				_log(state, "  le ferite uccidono %s" % target.display_name)
				target.clear_order()
				return true
			target.set_order(D.Order.DUCK_BACK)
			var res := Checks.wound_morale_check(target, state.rng)
			_log(state, "  WMC: tira %d -> %s, Duck Back" % [
				res["roll"], D.MORALE_NAMES[res["after"]]])
			return true


# MC da colpo senza ferita: se il morale scende, il bersaglio si butta giu'.
static func _hit_morale_check(state: GameState, target: Character) -> void:
	var res := Checks.morale_check(target, state.rng)
	var ducked := ""
	if res["delta"] < 0:
		target.set_order(D.Order.DUCK_BACK)
		ducked = ", Duck Back"
	_log(state, "  MC: tira %d -> %s%s" % [
		res["roll"], D.MORALE_NAMES[res["after"]], ducked])


# 9 naturale: Low Ammo, poi No Ammo (pistole esenti).
# TODO nota 3: le armi belt-fed con assistente richiedono doppio 9.
static func _spend_ammo(state: GameState, firer: Character, weapon: String) -> void:
	if "pistol" in Weapons.info(weapon)["flags"]:
		return
	if firer.low_ammo:
		firer.no_ammo = true
		_log(state, "  %s e' SENZA munizioni" % firer.display_name)
	else:
		firer.low_ammo = true
		_log(state, "  %s e' a corto di munizioni" % firer.display_name)


static func _log(state: GameState, msg: String) -> void:
	state.log_event(msg)
