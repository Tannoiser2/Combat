## Rule 31-32: veicoli e fuoco anticarro.
##
## Gestisce: creazione personaggi-veicolo, dati armatura per faccia,
## risoluzione del fuoco AT (WS check + penetrazione + danno scafo),
## fuoco HE del cannone principale vs fanteria (come artiglieria).
class_name VehicleCombat
extends RefCounted

const D := preload("res://engine/Domain.gd")

# Faccia colpita in base alla posizione del tiratore rispetto al veicolo.
enum Face { FRONT, SIDE, REAR }

# Velocita' del veicolo: FAST = Jeep/Halftrack, FORWARD = carri armati.
enum Speed { FAST, FORWARD }

# Dati dei veicoli (dai Vehicle Display nel repo privato).
# armor[face] = valore NORMAL; armor_g[face] = valore GLANCING (piu' alto).
# Face: 0=FRONT, 1=SIDE, 2=REAR.
# weapon = arma montata principale; ws = WS base con quell'arma.
const VEHICLE_DATA := {
	"Jeep": {
		"speed": Speed.FAST,
		"armor":   [0, 0, 0],
		"armor_g": [0, 0, 0],
		"weapon": "M1919", "ws": 6, "tq": 6,
		"side": D.Side.FRIENDLY,
	},
	"M3A1 Halftrack": {
		"speed": Speed.FAST,
		"armor":   [2, 1, 1],
		"armor_g": [3, 2, 2],
		"weapon": "M2 .50cal", "ws": 6, "tq": 6,
		"side": D.Side.FRIENDLY,
	},
	"M4A3 Sherman": {
		"speed": Speed.FORWARD,
		"armor":   [10, 4, 4],
		"armor_g": [18,  6, 6],
		"weapon": "75mm L40 HE", "ws": 7, "tq": 7,
		"side": D.Side.FRIENDLY,
	},
	"PzIVH": {
		"speed": Speed.FORWARD,
		"armor":   [8, 3, 2],
		"armor_g": [16, 5, 4],
		"weapon": "KwK 7.5cm HE", "ws": 7, "tq": 7,
		"side": D.Side.ENEMY,
	},
}

# Terreni che i veicoli non possono attraversare.
const VEHICLE_BLOCKED := [
	D.Terrain.BUILDING, D.Terrain.FOXHOLE, D.Terrain.MARSH,
	D.Terrain.ABBEY_EXTERIOR, D.Terrain.ABBEY_INTERIOR,
	D.Terrain.FORTIFIED_BUILDING,
]

# Ordini consentiti ai veicoli (no mischia/granate/cure).
const VEHICLE_ORDERS := [
	D.Order.AIMED_FIRE, D.Order.RAPID_FIRE, D.Order.SUPPRESSIVE_FIRE,
	D.Order.RUN_AND_GUN, D.Order.SPRINT, D.Order.EVADE,
	D.Order.SNEAK, D.Order.HIDE, D.Order.GUARD, D.Order.DUCK_BACK,
	D.Order.RALLY,
]


# Crea un Character che rappresenta un veicolo dalla chiave VEHICLE_DATA.
# La weapon opzionale sovrascrive quella di default (es. Jeep con M2 .50cal).
static func make_vehicle(v_name: String, side: int, team: String,
		pos: Vector2i, facing := 4, weapon_override := "") -> Character:
	assert(VEHICLE_DATA.has(v_name), "Tipo veicolo sconosciuto: " + v_name)
	var vd: Dictionary = VEHICLE_DATA[v_name]
	var uid := "v_%s_%s" % [v_name.to_lower().replace(" ", "_"), team]
	var c := Character.new(uid, v_name, side, team)
	c.position = pos
	c.facing = facing
	c.is_vehicle = true
	c.vehicle_type = v_name
	c.troop_quality = int(vd["tq"])
	c.morale = D.Morale.BOLD
	var w: String = weapon_override if not weapon_override.is_empty() else str(vd["weapon"])
	c.weapon_skills[w] = int(vd["ws"])
	# I carri hanno anche l'arma AP nella propria lista.
	if w == "75mm L40 HE":
		c.weapon_skills["75mm L40 AP"] = int(vd["ws"])
	elif w == "KwK 7.5cm HE":
		c.weapon_skills["KwK 7.5cm AP"] = int(vd["ws"])
	return c


# Vero se il tipo di veicolo e' FAST (Jeep, Halftrack).
static func is_fast(v_name: String) -> bool:
	var vd: Dictionary = VEHICLE_DATA.get(v_name, {})
	return int(vd.get("speed", Speed.FORWARD)) == Speed.FAST


# Hexagoni di movimento per impulse secondo l'ordine e la velocita' del veicolo.
# SPRINT / EVADE: veloce (FAST=2 hex, FORWARD=1 hex per impulse MUST_MOVE_2).
# RUN_AND_GUN / SNEAK: lento (1 hex per MUST_MOVE_1).
static func vehicle_hexes(v_name: String, is_must_move_2: bool) -> int:
	if not is_must_move_2:
		return 1
	return 2 if is_fast(v_name) else 1


# Faccia colpita in base alla posizione del tiratore e al facing del veicolo.
static func hit_face(vehicle: Character, firer_pos: Vector2i) -> int:
	var vdir: Vector3i = Move.CUBE_DIRS[(vehicle.facing - 1) % 6]
	var delta: Vector3i = Move.to_cube(firer_pos) - Move.to_cube(vehicle.position)
	var front_dot: int = vdir.x * delta.x + vdir.y * delta.y + vdir.z * delta.z
	var rear_dot: int = -vdir.x * delta.x + -vdir.y * delta.y + -vdir.z * delta.z
	if front_dot >= rear_dot and front_dot > 0:
		return Face.FRONT
	if rear_dot > front_dot and rear_dot > 0:
		return Face.REAR
	return Face.SIDE


# Penetrazione: pen_base + 1d{pen_die} (dalla Weapons.DATA).
static func roll_pen(rng: RandomNumberGenerator, weapon: String) -> int:
	var w := Weapons.info(weapon)
	return int(w.get("pen_base", 0)) + rng.randi_range(1, int(w.get("pen_die", 6)))


# Fuoco anticarro: firer vs vehicle con weapon AT o main_gun AP.
# Ritorna {"hit": bool, "result": String} per il replay/log.
static func at_fire(state: GameState, firer: Character, vehicle: Character, weapon: String) -> Dictionary:
	var winfo := Weapons.info(weapon)
	var flags: Array = winfo["flags"]
	assert("at" in flags or "main_gun" in flags,
		"at_fire: arma non AT/main_gun: " + weapon)

	# 1. WS check (semplificato: ws base + gittata + ordine + ferite).
	var dist := Spotting.hex_distance(firer.position, vehicle.position)
	var rmod = Weapons.range_ws_modifier(weapon, dist)
	if rmod == null:
		state.log_event("%s: %s fuori gittata" % [firer.display_name, weapon])
		return {"hit": false, "result": "fuori_gittata"}
	var ws: int = firer.weapon_skills.get(weapon, firer.troop_quality - 2) + int(rmod)
	ws += firer.wound_tq_modifier()
	ws += int(Orders.FIRE_WS_MOD.get(firer.order if firer.has_order else -1, 0))
	var roll: int = Checks.roll_d10(state.rng)
	var hit: bool = (roll == 0 or roll <= ws) and roll != 9
	state.log_event("%s -> %s con %s (WS %d, d10: %d): %s" % [
		firer.display_name, vehicle.display_name, weapon, ws, roll,
		"COLPITO" if hit else "mancato"])
	state.shots.append({"from": firer.position, "to": vehicle.position,
		"hit": hit, "side": firer.side, "weapon": weapon,
		"outcome": "Colpito!" if hit else "Mancato"})
	Replay.shot(state, state.shots.back())
	state.audio_events.append({"type": "shot", "weapon": weapon,
		"outcome": "Colpito!" if hit else "Mancato", "hex": firer.position})
	if not hit:
		return {"hit": false, "result": "mancato"}

	# 2. Faccia e penetrazione.
	var face := hit_face(vehicle, firer.position)
	var pen  := roll_pen(state.rng, weapon)
	var vd: Dictionary = VEHICLE_DATA.get(vehicle.vehicle_type, {})
	var armor_n := int((vd.get("armor", [0,0,0]) as Array)[face])
	var armor_g := int((vd.get("armor_g", [0,0,0]) as Array)[face])
	const FACE_NAMES := ["frontale", "laterale", "posteriore"]

	var result: String
	if pen > armor_g:
		result = "penetrazione"
		vehicle.hull_damage += 1
		state.log_event("  Penetrazione (%s)! pen %d > arm_g %d -> hull_damage %d" % [
			FACE_NAMES[face], pen, armor_g, vehicle.hull_damage])
		if vehicle.hull_damage >= 2:
			state.log_event("  %s DISTRUTTO!" % vehicle.display_name)
			state.audio_events.append({"type": "explosion", "hex": vehicle.position})
		elif vehicle.hull_damage == 1:
			state.log_event("  %s immobilizzato (hull_damage 1)" % vehicle.display_name)
	elif pen > armor_n:
		result = "striscio"
		state.log_event("  Colpo di striscio (%s): pen %d in [%d..%d] -> MC equipaggio" % [
			FACE_NAMES[face], pen, armor_n, armor_g])
		var mc := Checks.morale_check(vehicle, state.rng)
		if not mc["passed"]:
			vehicle.morale = D.lower_morale(vehicle.morale, 1)
			state.log_event("  MC fallito: %s morale -> %s" % [
				vehicle.display_name, D.MORALE_NAMES[vehicle.morale]])
	else:
		result = "rimbalzo"
		state.log_event("  Rimbalzo (%s): pen %d <= armor %d" % [
			FACE_NAMES[face], pen, armor_n])
	return {"hit": true, "result": result}


# Fuoco HE del cannone principale vs fanteria: come un'esplosione di mortaio
# nell'hex bersaglio (Area.explode). weapon = "75mm L40 HE" o "KwK 7.5cm HE".
static func he_fire(state: GameState, firer: Character, target_pos: Vector2i, weapon: String) -> void:
	var winfo := Weapons.info(weapon)
	assert("he" in winfo["flags"], "he_fire: arma non HE: " + weapon)
	var dist := Spotting.hex_distance(firer.position, target_pos)
	var rmod = Weapons.range_ws_modifier(weapon, dist)
	if rmod == null:
		state.log_event("%s: HE fuori gittata (%s)" % [firer.display_name, weapon])
		return
	var ws: int = firer.weapon_skills.get(weapon, firer.troop_quality) + int(rmod)
	var roll: int = Checks.roll_d10(state.rng)
	var hit: bool = (roll == 0 or roll <= ws) and roll != 9
	state.log_event("%s spara HE su %02d.%02d con %s (WS %d, d10 %d): %s" % [
		firer.display_name, target_pos.x, target_pos.y, weapon, ws, roll,
		"colpito" if hit else "mancato"])
	state.shots.append({"from": firer.position, "to": target_pos,
		"hit": hit, "side": firer.side, "weapon": weapon,
		"outcome": "Colpito!" if hit else "Mancato"})
	Replay.shot(state, state.shots.back())
	state.audio_events.append({"type": "shot", "weapon": weapon,
		"outcome": "Colpito!" if hit else "Mancato", "hex": firer.position})
	if hit:
		Area._explode(state, {"type": Area.Type.MORTAR_81, "hex": target_pos,
			"placed_turn": state.turn})
		state.log_event("  Esplosione HE in %02d.%02d" % [target_pos.x, target_pos.y])
