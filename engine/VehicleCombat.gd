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
const VEHICLE_COUNTER := {
	"Jeep":          "FR-Jeep-A",
	"M3A1 Halftrack":"FR-M3a1",
	"M4A3 Sherman":  "FR-M4A3-A",
	"PzIVH":         "EN-PZIVH-A",
	"GMC 2.5t":      "FR-GMC-2.5t",
	"Opel Blitz":    "EN-Opel-Blitz-A",
}


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
		"bow_mg": "M1919",   # Rule 31.9.4b: bow MG del Co-Driver
		"coax_mg": "M1919",  # Rule 31.9.4c: MG coassiale del Gunner
		"side": D.Side.FRIENDLY,
	},
	"PzIVH": {
		"speed": Speed.FORWARD,
		"armor":   [9, 3, 2],   # Lower Hull Front 9/16 dal Vehicle Display PzIVH
		"armor_g": [16, 5, 4],
		"weapon": "KwK 7.5cm HE", "ws": 7, "tq": 7,
		"bow_mg": "MG34 Vehicle",
		"coax_mg": "MG34 Vehicle",
		"side": D.Side.ENEMY,
	},
	# Camion da trasporto soft-skin (Rule 31): nessuna corazza, nessun'arma
	# montata. I 12 posti passeggero del Vehicle Display non sono modellati.
	"GMC 2.5t": {
		"speed": Speed.FAST,
		"armor":   [0, 0, 0],
		"armor_g": [0, 0, 0],
		"weapon": "", "ws": 0, "tq": 6,
		"side": D.Side.FRIENDLY,
	},
	"Opel Blitz": {
		"speed": Speed.FAST,
		"armor":   [0, 0, 0],
		"armor_g": [0, 0, 0],
		"weapon": "", "ws": 0, "tq": 6,
		"side": D.Side.ENEMY,
	},
}

# AFV con torretta rotante (Rule 31.6). Jeep e Halftrack non hanno torretta.
const TURRETED := ["M4A3 Sherman", "PzIVH"]

# Armatura per-zona degli AFV (Rule 31.10), dai Vehicle Display ufficiali.
# Ogni voce: [valore NORMAL, valore GLANCING]. Le zone scafo hanno una variante
# Lower/Upper per fronte e lato; rear unica.
const AFV_ARMOR := {
	"M4A3 Sherman": {
		"turret_front": [8, 14], "turret_side": [7, 11], "turret_rear": [7, 11],
		"lower_hull_front": [10, 18], "upper_hull_front": [9, 16],
		"lower_hull_side": [4, 6], "upper_hull_side": [4, 6], "rear": [4, 6],
	},
	"PzIVH": {
		"turret_front": [6, 9], "turret_side": [5, 7], "turret_rear": [5, 7],
		"lower_hull_front": [9, 16], "upper_hull_front": [9, 12],
		"lower_hull_side": [3, 5], "upper_hull_side": [3, 5], "rear": [2, 4],
	},
}

# AFV Hit Location Table (Rule 31.10), trascritta dalla tabella ufficiale
# "AFV Hit Locations". Tiro d100; si prende la prima riga con roll <= max.
# Ogni riga: [max, kind, glancing, [crew MC]]. kind:
#  bounce, hull_mg, periscope, hatch, suspension, track, drive_wheel,
#  gun_barrel, turret_ring, coax, gunner_sight, lower_hull, upper_hull, turret.
# "turret" rimanda alla sotto-tabella torretta (per faccia della torretta).
const AFV_HULL_TABLE := {
	Face.FRONT: [
		[15, "bounce", false, []], [16, "hull_mg", false, ["CD"]],
		[20, "periscope", false, ["D"]], [22, "hatch", false, ["D"]],
		[31, "lower_hull", false, []], [39, "upper_hull", false, []],
		[44, "lower_hull", true, []], [54, "suspension", false, ["ALL"]],
		[70, "turret", true, []], [94, "turret", false, []],
		[100, "turret_ring", false, ["CM", "G", "L"]],
	],
	Face.SIDE: [
		[15, "bounce", false, []], [16, "gun_barrel", false, ["CD"]],
		[20, "periscope", false, ["D"]], [22, "drive_wheel", false, []],
		[24, "track", false, []], [32, "lower_hull", false, []],
		[39, "upper_hull", false, []], [44, "lower_hull", true, []],
		[64, "suspension", false, ["ALL"]], [70, "turret", true, []],
		[94, "turret", false, []], [100, "turret_ring", false, ["CM", "G", "L"]],
	],
	Face.REAR: [
		[10, "suspension", false, ["ALL"]], [75, "upper_hull", false, []],
		[95, "turret", false, []], [100, "turret_ring", false, ["CM", "G", "L"]],
	],
}
# Sotto-tabella torretta: "turret_armor" = colpo da risolvere con la penetrazione
# vs armatura torretta della faccia colpita.
const AFV_TURRET_TABLE := {
	Face.FRONT: [
		[7, "gun_barrel", false, []], [12, "coax", false, []],
		[16, "periscope", false, ["CM"]], [23, "periscope", false, ["L"]],
		[27, "hatch", false, ["L"]], [30, "gunner_sight", false, ["G"]],
		[35, "turret_ring", false, ["CM", "G", "L"]], [100, "turret_armor", false, []],
	],
	Face.SIDE: [
		[7, "gun_barrel", false, []], [11, "turret_ring", false, ["CM", "G", "L"]],
		[100, "turret_armor", false, []],
	],
	Face.REAR: [
		[100, "turret_armor", false, []],
	],
}


# Vero se il veicolo e' un AFV dotato di torretta (Rule 31.6).
static func has_turret(c: Character) -> bool:
	return c.is_vehicle and c.vehicle_type in TURRETED


# Rule 31.10: l'equipaggio e' esposto al fuoco leggero? I mezzi scoperti
# (Jeep/Halftrack) sempre; gli AFV solo col boccaporto aperto.
static func crew_exposed(v: Character) -> bool:
	if not v.is_vehicle:
		return false
	if not has_turret(v):
		return true
	return not v.is_buttoned_up


# Punta la torretta sul bersaglio (Rule 31.6). Se e' gia' allineata col
# bersaglio (front arc = la direzione esagonale del bersaglio) ritorna true:
# il cannone puo' sparare. Altrimenti ruota di 1 hex-side verso il bersaglio
# e ritorna false: la rotazione consuma l'impulso, niente fuoco.
static func turret_aim(state: GameState, vehicle: Character, target_pos: Vector2i) -> bool:
	if vehicle.turret_facing <= 0:
		vehicle.turret_facing = vehicle.facing
	var want := Move.dir_toward(vehicle.position, target_pos)
	# Rule 31.10: torretta inceppata -> non ruota; spara solo se gia' allineata.
	if vehicle.turret_jammed:
		return vehicle.turret_facing == want
	if vehicle.turret_facing == want:
		return true
	vehicle.turret_facing = Move.rotate_toward(vehicle.turret_facing, want)
	state.log_event("  la torretta del %s ruota verso direzione %d (bersaglio in %d)" % [
		vehicle.display_name, vehicle.turret_facing, want])
	return false


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

# Composizione dell'equipaggio per tipo di veicolo (Rule 31). L'ordine e'
# quello di attivazione del regolamento (Commander/Driver/Gunner/Loader/
# Co-driver). Estendibile: aggiungere ruoli o LOS per ruolo qui.
const VEHICLE_CREW := {
	"Jeep":            ["Driver", "Co-Driver"],
	"M3A1 Halftrack":  ["Driver", "Co-Driver", "Gunner"],
	"M4A3 Sherman":    ["Commander", "Driver", "Gunner", "Loader", "Co-Driver"],
	"PzIVH":           ["Commander", "Driver", "Gunner", "Loader", "Co-Driver"],
	"GMC 2.5t":        ["Driver", "Co-Driver"],
	"Opel Blitz":      ["Driver", "Co-Driver"],
}

# Pedine equipaggio per lato e ruolo (file in assets/counters/<id>-f.png). Il
# ruolo e' STAMPATO sulla pedina, quindi ogni lista contiene solo pedine di
# quel ruolo (verificate sui segnalini). Piu' voci danno varieta' fra veicoli
# diversi nello stesso scenario; l'indice deriva dall'id del mezzo
# (vedi populate_crew).
const CREW_COUNTERS := {
	"FRIENDLY": {
		"Commander": ["US-Crew-Lt-White", "US-Crew-Sgt-Truscott", "US-Crew-Cpt-Murphy"],
		"Gunner":    ["US-Crew-Cpl-Pierce", "US-Crew-Cpl-Blackl", "US-Crew-Cpl-George"],
		"Driver":    ["US-Crew-Cpl-Smith", "US-Crew-Cpl-Butler", "US-Crew-Cpl-Hamilton"],
		"Loader":    ["US-Crew-Pvt-Barrettt", "US-Crew-Pvt-Gregory", "US-Crew-Pvt-Lucas"],
		"Co-Driver": ["US-Crew-Pvt-Cross", "US-Crew-Pvt-Garner", "US-Crew-Pvt-Newman"],
	},
	"ENEMY": {
		"Commander": ["GE-Crew-UO-Graf", "GE-Crew-UO-Otto", "GE-Crew-UO-Riedel"],
		"Gunner":    ["GE-Crew-UBSH-Kern", "GE-Crew-UBSH-Voss", "GE-Crew-UBSH-Nagel"],
		"Driver":    ["GE-Crew-UBG-Barth", "GE-Crew-UBG-Grimm", "GE-Crew-UBG-Kessler"],
		"Loader":    ["GE-Crew-UBSH-Bender", "GE-Crew-UBSH-Breuer", "GE-Crew-UBSH-Froehlich"],
		"Co-Driver": ["GE-Crew-OBSH-Bayer", "GE-Crew-OBSH-Herzog", "GE-Crew-OBSH-Rose"],
	},
}


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
	c.turret_facing = facing if v_name in TURRETED else 0
	c.is_vehicle = true
	c.vehicle_type = v_name
	# Rule 31.7/31.10: gli AFV partono col boccaporto chiuso (al sicuro dal
	# fuoco leggero, ma -2 allo spotting). I mezzi scoperti restano esposti.
	c.is_buttoned_up = v_name in TURRETED
	c.counter = VEHICLE_COUNTER.get(v_name, "")
	c.troop_quality = int(vd["tq"])
	c.morale = D.Morale.BOLD
	var w: String = weapon_override if not weapon_override.is_empty() else str(vd["weapon"])
	# I camion soft-skin non hanno arma montata (w == "").
	if not w.is_empty():
		c.weapon_skills[w] = int(vd["ws"])
	# I carri hanno anche l'arma AP nella propria lista.
	if w == "75mm L40 HE":
		c.weapon_skills["75mm L40 AP"] = int(vd["ws"])
	elif w == "KwK 7.5cm HE":
		c.weapon_skills["KwK 7.5cm AP"] = int(vd["ws"])
	populate_crew(c)
	return c


# Crea i Character dell'equipaggio dentro vehicle.crew (Rule 31). I crew
# ereditano TQ e morale del veicolo e una pistola per il bail-out. Restano
# "imbarcati" (embarked_in = vehicle), fuori da state.characters finche' non
# abbandonano: cosi' non vengono attivati/spottati separatamente (livello
# intermedio). Il Commander porta una Leadership di comando (Rule 31.11.6).
static func populate_crew(vehicle: Character) -> void:
	var roles: Array = VEHICLE_CREW.get(vehicle.vehicle_type, [])
	var vd: Dictionary = VEHICLE_DATA.get(vehicle.vehicle_type, {})
	var tq := int(vd.get("tq", 6))
	var pistol := "M1911" if vehicle.side == D.Side.FRIENDLY else "P38"
	vehicle.crew = []
	var side_key := "FRIENDLY" if vehicle.side == D.Side.FRIENDLY else "ENEMY"
	var pools: Dictionary = CREW_COUNTERS.get(side_key, {})
	var off := absi(vehicle.id.hash())
	for role in roles:
		var uid := "%s_%s" % [vehicle.id, String(role).to_lower().replace("-", "")]
		var cm := Character.new(uid, "%s del %s" % [role, vehicle.vehicle_type],
			vehicle.side, vehicle.team)
		cm.troop_quality = tq
		cm.morale = vehicle.morale
		cm.crew_role = role
		# Pedina nominata per il ruolo (mostrata nel Vehicle Display).
		var pool: Array = pools.get(role, [])
		if not pool.is_empty():
			cm.counter = String(pool[off % pool.size()])
		cm.embarked = true
		cm.position = vehicle.position
		cm.weapon_skills[pistol] = maxi(2, tq - 3)
		# Rule 31.9.4b: il Co-Driver serve la bow MG. Senza assistente il fuoco
		# usa la TQ -3 al posto del WS (l'MG va Low/No Ammo sul singolo 9).
		if role == "Co-Driver" and vd.has("bow_mg"):
			cm.weapon_skills[String(vd["bow_mg"])] = maxi(2, tq - 3)
		# Rule 31.9.4c: il Gunner puo' sparare la MG coassiale (con la TQ piena,
		# e' allineata col cannone dalla torretta).
		if role == "Gunner" and vd.has("coax_mg"):
			cm.weapon_skills[String(vd["coax_mg"])] = tq
		if role == "Commander":
			cm.leadership = 1
		vehicle.crew.append(cm)


# Nome dell'arma bow MG del veicolo (Rule 31.9.4b), o "" se non ne ha.
static func bow_mg_weapon(vehicle: Character) -> String:
	if vehicle.bow_mg_wrecked:  # Rule 31.10: distrutta da un colpo precedente
		return ""
	return String(VEHICLE_DATA.get(vehicle.vehicle_type, {}).get("bow_mg", ""))


# Nome dell'arma coassiale del veicolo (Rule 31.9.4c), o "" se non ne ha.
static func coax_mg_weapon(vehicle: Character) -> String:
	if vehicle.coax_wrecked:  # Rule 31.10: distrutta da un colpo precedente
		return ""
	return String(VEHICLE_DATA.get(vehicle.vehicle_type, {}).get("coax_mg", ""))


# Sincronizza il morale dei crew imbarcati con quello del veicolo (a inizio
# scenario, quando lo scenario imposta il morale del mezzo).
static func sync_crew_morale(vehicle: Character) -> void:
	for cm in vehicle.crew:
		if not cm.is_dead():
			cm.morale = vehicle.morale


# I crew vivi ancora a bordo.
static func _embarked_alive(vehicle: Character) -> Array:
	var out: Array = []
	for cm in vehicle.crew:
		if cm.embarked and not cm.is_dead():
			out.append(cm)
	return out


# Uccide un Character (crew) accumulando ferite gravi finche' e' fuori gioco.
static func _kill(victim: Character) -> void:
	victim.wounds.append(D.Wound.BAD)
	while not victim.is_dead():
		victim.wounds.append(D.Wound.BAD)
	victim.clear_order()


# Una scheggia/penetrazione ferisce un crew a caso ancora a bordo (Rule
# 31.10.8). Pesca una Friendly Card per la gravita' (come la fanteria).
static func _crew_casualty(state: GameState, vehicle: Character) -> void:
	var alive := _embarked_alive(vehicle)
	if alive.is_empty():
		return
	var victim: Character = alive[state.rng.randi_range(0, alive.size() - 1)]
	var serial := state.draw_friendly_card()
	state.friendly_discard.append(serial)
	var wound: int = FriendlyCards.wound_of(serial)
	match wound:
		FriendlyCards.WoundDraw.CLOSE_CALL:
			state.log_event("  %s: scheggia di striscio, regge" % victim.display_name)
		FriendlyCards.WoundDraw.KIA:
			_kill(victim)
			state.log_event("  %s UCCISO nel mezzo" % victim.display_name)
		_:
			var w: int = D.Wound.LIGHT if wound == FriendlyCards.WoundDraw.LIGHT_WOUND else D.Wound.BAD
			victim.wounds.append(w)
			state.log_event("  %s ferito (%s)" % [victim.display_name,
				"Light Wound" if w == D.Wound.LIGHT else "Bad Wound"])
			if victim.is_dead():
				_kill(victim)
				state.log_event("  le ferite uccidono %s" % victim.display_name)


# Uccide tutti i crew ancora a bordo (esplosione/distruzione, Rule 31.10.8
# "Vehicle Explodes - All crew still in the Vehicle are killed").
static func _kill_embarked_crew(state: GameState, vehicle: Character) -> void:
	for cm in _embarked_alive(vehicle):
		_kill(cm)
		state.log_event("  %s muore con il mezzo" % cm.display_name)


# Hex libero piu' vicino dove far scendere un crew (il mezzo o un adiacente).
static func _free_hex_near(state: GameState, pos: Vector2i) -> Vector2i:
	if state.character_at(pos.x, pos.y) == null:
		return pos
	for n in Move.neighbors(state, pos):
		if state.character_at(n.x, n.y) == null:
			return n
	return pos


# Mount Up: un personaggio a piedi sale sul veicolo come passeggero.
# Il passeggero sparisce dalla mappa (embarked=true) e viene aggiunto a vehicle.crew
# con ruolo "Passenger". Scende normalmente con bail_out alla distruzione/selezione.
static func mount_up(state: GameState, passenger: Character, vehicle: Character) -> void:
	passenger.crew_role = "Passenger"
	passenger.embarked = true
	passenger.position = vehicle.position
	passenger.clear_order()
	vehicle.crew.append(passenger)
	state.log_event("%s sale sul %s in %02d.%02d" % [
		passenger.display_name, vehicle.display_name,
		vehicle.position.x, vehicle.position.y])


# Bail Out (Rule 31.9.3): i crew vivi a bordo scendono nell'hex del mezzo
# (o adiacente), diventano fanteria normale e si aggiungono a state.characters.
# Scendono scossi (sotto il fuoco) e senza ordine.
static func bail_out(state: GameState, vehicle: Character) -> void:
	for cm in vehicle.crew:
		if not cm.embarked or cm.is_dead():
			continue
		cm.embarked = false
		cm.position = _free_hex_near(state, vehicle.position)
		cm.clear_order()
		cm.morale = D.lower_morale(cm.morale, 1)
		if cm.side == D.Side.ENEMY:
			cm.known = true
			cm.alerted = true
		else:
			cm.spotted = true
		state.characters.append(cm)
		state.log_event("%s abbandona il %s su %02d.%02d" % [
			cm.display_name, vehicle.display_name, cm.position.x, cm.position.y])


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


# Faccia colpita data una direzione di facing (1..6) e la posizione del tiratore.
static func face_from(facing: int, vehicle_pos: Vector2i, firer_pos: Vector2i) -> int:
	var vdir: Vector3i = Move.CUBE_DIRS[(facing - 1) % 6]
	var delta: Vector3i = Move.to_cube(firer_pos) - Move.to_cube(vehicle_pos)
	var front_dot: int = vdir.x * delta.x + vdir.y * delta.y + vdir.z * delta.z
	var rear_dot: int = -vdir.x * delta.x + -vdir.y * delta.y + -vdir.z * delta.z
	if front_dot >= rear_dot and front_dot > 0:
		return Face.FRONT
	if rear_dot > front_dot and rear_dot > 0:
		return Face.REAR
	return Face.SIDE


# Faccia dello SCAFO colpita (in base al facing del veicolo).
static func hit_face(vehicle: Character, firer_pos: Vector2i) -> int:
	return face_from(vehicle.facing, vehicle.position, firer_pos)


# Faccia della TORRETTA colpita (in base al turret_facing; ripiego sullo scafo).
static func turret_hit_face(vehicle: Character, firer_pos: Vector2i) -> int:
	var tf: int = vehicle.turret_facing if vehicle.turret_facing > 0 else vehicle.facing
	return face_from(tf, vehicle.position, firer_pos)


# Tira sulla tabella (lista [max, kind, glancing, mc]) con un d100 (1..100).
static func _roll_loc(rng: RandomNumberGenerator, table: Array) -> Array:
	var roll := rng.randi_range(1, 100)
	for row in table:
		if roll <= int(row[0]):
			return row
	return table.back()


# Chiave d'armatura (AFV_ARMOR) per una zona scafo e la faccia colpita.
static func _hull_armor_key(kind: String, face: int) -> String:
	if face == Face.REAR:
		return "rear"
	var side := "front" if face == Face.FRONT else "side"
	return "%s_%s" % [kind, side]  # es. lower_hull_front / upper_hull_side


# Faccia torretta -> chiave armatura torretta.
static func _turret_armor_key(face: int) -> String:
	match face:
		Face.FRONT: return "turret_front"
		Face.REAR: return "turret_rear"
		_: return "turret_side"


# MC dei crew indicati dalle lettere della tabella (CM/G/L/D/CD/ALL, Rule 31.10.6).
const _MC_ROLE := {"CM": "Commander", "G": "Gunner", "L": "Loader",
	"D": "Driver", "CD": "Co-Driver"}
static func _crew_mc_letters(state: GameState, vehicle: Character, letters: Array) -> void:
	if letters.is_empty():
		return
	if "ALL" in letters:
		_crew_morale_checks(state, vehicle)
		return
	for L in letters:
		var role: String = _MC_ROLE.get(L, "")
		for cm in _embarked_alive(vehicle):
			if cm.crew_role == role:
				var mc := Checks.morale_check(cm, state.rng)
				if int(mc["delta"]) < 0:
					state.log_event("  %s (%s): MC fallito -> %s" % [
						cm.display_name, role, D.MORALE_NAMES[cm.morale]])


# Risoluzione fedele del colpo su un AFV (Rule 31.10): tira la hit location,
# applica guasti/MC e, per le zone corazzate, il check di penetrazione
# (pen DEVE superare l'armatura della zona; glancing usa il valore Glancing).
static func _resolve_afv_hit(state: GameState, firer: Character, vehicle: Character,
		weapon: String, hull_face: int) -> String:
	var row := _roll_loc(state.rng, AFV_HULL_TABLE[hull_face])
	var kind: String = row[1]
	var glancing: bool = row[2]
	var armor_face := hull_face
	# "turret": rimanda alla sotto-tabella torretta (faccia della torretta).
	if kind == "turret":
		armor_face = turret_hit_face(vehicle, firer.position)
		var trow := _roll_loc(state.rng, AFV_TURRET_TABLE[armor_face])
		kind = trow[1]
		glancing = glancing or bool(trow[2])
		_crew_mc_letters(state, vehicle, trow[3])
	else:
		_crew_mc_letters(state, vehicle, row[3])
	match kind:
		"bounce":
			state.log_event("  Rimbalzo: nessun effetto")
			return "rimbalzo"
		"suspension", "track", "drive_wheel":
			vehicle.immobilized = true
			state.log_event("  %s immobilizzato (%s)" % [vehicle.display_name, kind])
			return "immobilizzato"
		"gun_barrel":
			vehicle.main_gun_wrecked = true
			state.log_event("  Cannone del %s distrutto!" % vehicle.display_name)
			return "cannone_ko"
		"turret_ring":
			vehicle.turret_jammed = true
			state.log_event("  Torretta del %s inceppata (non ruota piu')" % vehicle.display_name)
			return "torretta_inceppata"
		"coax":
			vehicle.coax_wrecked = true
			state.log_event("  Coassiale del %s distrutta" % vehicle.display_name)
			return "coax_ko"
		"hull_mg":
			vehicle.bow_mg_wrecked = true
			state.log_event("  Bow MG del %s distrutta" % vehicle.display_name)
			return "bowmg_ko"
		"periscope", "hatch", "gunner_sight":
			state.log_event("  Colpo a %s (MC equipaggio)" % kind)
			return "componente"
		_:
			# Zona corazzata (lower_hull/upper_hull/turret_armor): penetrazione.
			var akey := _turret_armor_key(armor_face) if kind == "turret_armor" \
				else _hull_armor_key(kind, armor_face)
			var arm: Array = AFV_ARMOR.get(vehicle.vehicle_type, {}).get(akey, [99, 99])
			var armor := int(arm[1] if glancing else arm[0])
			var pen := roll_pen(state.rng, weapon)
			if pen > armor:  # Rule 31.10.4: deve SUPERARE l'armatura della zona
				# Una penetrazione netta di scafo/torretta mette KO il mezzo
				# (equipaggio colpito, possibile incendio/esplosione munizioni).
				vehicle.hull_damage = 2
				state.log_event("  Penetrazione (%s%s)! pen %d > arm %d -> %s DISTRUTTO!" % [
					akey, " glancing" if glancing else "", pen, armor, vehicle.display_name])
				state.audio_events.append({"type": "explosion", "hex": vehicle.position})
				_kill_embarked_crew(state, vehicle)
				return "penetrazione"
			state.log_event("  Mancata penetrazione (%s%s): pen %d <= arm %d" % [
				akey, " glancing" if glancing else "", pen, armor])
			return "non_penetrato"


# Rule 31.9.4: bonus al colpo (TQ/WS) per la faccia bersagliata. Il fianco
# offre il profilo piu' ampio (+2); fronte e retro +1.
static func face_to_hit_bonus(face: int) -> int:
	return 2 if face == Face.SIDE else 1


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
	# Rule 31.6 Emergency Stop: +1 WS per chi spara al carro fermo, -2 al carro stesso.
	if vehicle.emergency_stop:
		ws += 1
	if firer.is_vehicle and firer.emergency_stop:
		ws -= 2
	# Rule 31.9.4: bonus al colpo secondo la faccia bersagliata (il fianco offre
	# il profilo piu' ampio): +2 di lato, +1 frontale o posteriore.
	var face := hit_face(vehicle, firer.position)
	ws += face_to_hit_bonus(face)
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

	# 2a. AFV con tabella ufficiale (Rule 31.10): hit-location + penetrazione fedele.
	if AFV_ARMOR.has(vehicle.vehicle_type):
		return {"hit": true, "result": _resolve_afv_hit(state, firer, vehicle, weapon, face)}

	# 2b. Jeep/Halftrack/Truck: modello a bande (prossime fette del rework).
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
		# Il colpo penetrante ferisce un membro dell'equipaggio (Rule 31.10.8).
		_crew_casualty(state, vehicle)
		if vehicle.hull_damage >= 2:
			state.log_event("  %s DISTRUTTO!" % vehicle.display_name)
			state.audio_events.append({"type": "explosion", "hex": vehicle.position})
			# Esplosione: tutti i crew ancora a bordo muoiono (Rule 31.10.8).
			_kill_embarked_crew(state, vehicle)
		elif vehicle.hull_damage == 1:
			state.log_event("  %s immobilizzato (hull_damage 1)" % vehicle.display_name)
			# Immobilizzato: l'equipaggio superstite abbandona il mezzo.
			bail_out(state, vehicle)
	elif pen > armor_n:
		result = "striscio"
		state.log_event("  Colpo di striscio (%s): pen %d in [%d..%d] -> MC equipaggio" % [
			FACE_NAMES[face], pen, armor_n, armor_g])
		# Ogni crew a bordo fa un MC individuale (Rule 31.10.6/31.10.9).
		_crew_morale_checks(state, vehicle)
	else:
		result = "rimbalzo"
		state.log_event("  Rimbalzo (%s): pen %d <= armor %d" % [
			FACE_NAMES[face], pen, armor_n])
	return {"hit": true, "result": result}


# MC individuali dei crew a bordo (colpo di striscio). Il morale del veicolo
# segue quello peggiore dell'equipaggio (usato da AI e display).
static func _crew_morale_checks(state: GameState, vehicle: Character) -> void:
	var alive := _embarked_alive(vehicle)
	if alive.is_empty():
		# Veicolo senza crew modellato: ripiego sul MC del mezzo (morale_check
		# applica gia' l'eventuale calo).
		Checks.morale_check(vehicle, state.rng)
		return
	var worst: int = vehicle.morale
	for cm in alive:
		# morale_check applica gia' il calo (delta < 0 = MC fallito).
		var mc := Checks.morale_check(cm, state.rng)
		if int(mc["delta"]) < 0:
			state.log_event("  %s: MC fallito -> %s" % [
				cm.display_name, D.MORALE_NAMES[cm.morale]])
		worst = maxi(worst, cm.morale)
	vehicle.morale = worst


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
