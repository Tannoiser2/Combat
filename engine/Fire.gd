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
	D.Morale.BERSERK: 3,
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
	var any_hit := false
	var nines := 0
	var wounds_before := target.wounds.size()
	var dead_before := target.is_dead()
	var morale_before := target.morale
	for i in range(rof):
		if target.is_dead() or firer.no_ammo:
			break
		var res := _resolve_attack(state, firer, target, weapon)
		if res["hit"]:
			any_hit = true
		if res["nine"]:
			nines += 1
	# Munizioni: un 9 naturale le intacca; le belt-fed con assistente
	# richiedono due 9 nello stesso fuoco (nota 3 del chart).
	var belt: bool = "belt" in Weapons.info(weapon)["flags"]
	if nines >= (2 if belt else 1):
		_spend_ammo(state, firer, weapon)
	# Esito sintetico per la UI (balloon sul bersaglio).
	var outcome := "Mancato"
	if target.is_dead() and not dead_before:
		outcome = "Ucciso!"
	elif target.wounds.size() > wounds_before:
		outcome = "Ferito!"
	elif any_hit and target.morale > morale_before:
		outcome = "Soppresso!"  # colpito senza danni ma il morale cede
	elif any_hit:
		outcome = "Colpito!"
	# Registra il colpo come dato per la visualizzazione (linea di fuoco)
	# e per il replay.
	state.shots.append({
		"from": firer.position, "to": target.position,
		"hit": any_hit, "side": firer.side, "outcome": outcome,
		"weapon": weapon,
	})
	Replay.shot(state, state.shots.back())
	state.audio_events.append({"type": "shot", "weapon": weapon, "hex": firer.position})


# Ritorna {hit: bool, nine: bool}.
static func _resolve_attack(state: GameState, firer: Character, target: Character, weapon: String) -> Dictionary:
	var dist := Spotting.hex_distance(firer.position, target.position)
	var hex := state.hex_at(target.position.x, target.position.y)
	var terrain: int = hex.terrain if hex != null else D.Terrain.OPEN_LEVEL_0
	var group: int = WS_GROUP.get(target.order, NO_ORDER_GROUP) \
		if target.has_order else NO_ORDER_GROUP
	var suppressive := firer.has_order and firer.order == D.Order.SUPPRESSIVE_FIRE

	# Il WS modificato, con la SCOMPOSIZIONE per il log di combattimento.
	var ws: int = firer.weapon_skills[weapon]
	var bits: Array[String] = ["%d base %s" % [ws, weapon]]
	var m: int = int(Weapons.range_ws_modifier(weapon, dist))
	if m != 0:
		bits.append("%+d gittata %d hex" % [m, dist])
	ws += m
	if not suppressive:
		var tmod: int = WS_MOD[terrain][group]
		var tname: String = Domain.TERRAIN_NAMES[terrain]
		# Hexside sul bordo d'ingresso del tiro (siepe/bocage/muro davanti
		# al bersaglio): vale il modificatore piu' protettivo.
		var side := _entry_hexside(state, firer.position, target.position)
		if side >= 0 and WS_MOD[side][group] < tmod:
			tmod = WS_MOD[side][group]
			tname = Domain.TERRAIN_NAMES[side] + " (bordo)"
		if tmod != 0:
			bits.append("%+d bersaglio in %s" % [tmod, tname])
		ws += tmod
	if firer.has_order:
		m = int(Orders.FIRE_WS_MOD.get(firer.order, 0))
		if m != 0:
			bits.append("%+d ordine %s" % [m, Domain.ORDER_NAMES[firer.order]])
		ws += m
	m = 0
	for w in firer.wounds:
		m += WOUND_MOD[w]
	if m != 0:
		bits.append("%+d ferite" % m)
	ws += m
	m = int(MORALE_WS_MOD.get(firer.morale, 0))
	if m != 0:
		bits.append("%+d morale %s" % [m, Domain.MORALE_NAMES[firer.morale]])
	ws += m
	# Modificatori della carta di turno (solo per i Friendly).
	if firer.side == D.Side.FRIENDLY:
		m = int(state.turn_fx.get("ws_all", 0)) \
			+ int(state.turn_fx.get("ws_team", {}).get(firer.team, 0))
		if state.turn_fx.has("ws_cover_self"):
			var fhex := state.hex_at(firer.position.x, firer.position.y)
			if fhex != null and Domain.terrain_gives_cover(fhex.terrain):
				m += int(state.turn_fx["ws_cover_self"])
		if m != 0:
			bits.append("%+d carta" % m)
		ws += m
	# Ambiente: eventi/scenario, fumo lungo il tiro, notte.
	m = int(state.turn_fx.get("fire_env_mod", 0))
	m += _smoke_modifier(state, firer.position, target.position)
	if state.night and dist > 2 and not Area.illuminated(state, target.position):
		m += -2
	if m != 0:
		bits.append("%+d ambiente (fumo/notte)" % m)
	ws += m
	# TODO: filo spinato per-hex.

	var roll := Checks.roll_d10(state.rng)
	# Riga di dettaglio (prefisso "·"): la formula completa del tiro.
	# La UI puo' nasconderla/mostrarla (log collassabile).
	_log(state, "· WS %d = %s | d10: %d" % [ws, ", ".join(bits), roll])
	if roll == 9:
		_log(state, "%s spara a %s con %s: 9 naturale, mancato!" % [
			firer.display_name, target.display_name, weapon])
		return {"hit": false, "nine": true}
	# Colpito se 0 naturale o roll <= WS. Con WS < 0 il colpo (solo da 0
	# naturale) va confermato con un TQC, la cui TQ e' ridotta del valore
	# per cui il WS era sotto zero (nota 2 del chart).
	var is_hit := roll == 0 or roll <= ws
	# Carte "Good Shot"/"Lucky": un tiro mancato del giocatore si ritira.
	if not is_hit and firer.side == D.Side.FRIENDLY \
			and FriendlyCards.use_from_hand(state, FriendlyCards.REROLL_WS,
				"ritira il tiro mancato di %s" % firer.display_name):
		roll = Checks.roll_d10(state.rng)
		_log(state, "· nuovo tiro: %d (WS %d)" % [roll, ws])
		is_hit = roll != 9 and (roll == 0 or roll <= ws)
	if not is_hit:
		_log(state, "%s spara a %s con %s: tira %d > WS %d, mancato" % [
			firer.display_name, target.display_name, weapon, roll, ws])
		return {"hit": false, "nine": false}
	if ws < 0:
		var thr := Checks.effective_tq(firer) + ws
		var roll2 := Checks.roll_d10(state.rng)
		if roll2 > thr:
			_log(state, "%s spara a %s: 0 naturale ma TQC di conferma fallito (tira %d > %d)" % [
				firer.display_name, target.display_name, roll2, thr])
			return {"hit": false, "nine": false}

	_log(state, "%s COLPISCE %s con %s (tira %d, WS %d)" % [
		firer.display_name, target.display_name, weapon, roll, ws])
	var mc_only := suppressive or [terrain, group] in MC_ONLY
	var wounded_or_killed := false
	if mc_only:
		_hit_morale_check(state, target)
	elif target.side == D.Side.FRIENDLY \
			and FriendlyCards.use_from_hand(state, FriendlyCards.KEEP_HEAD_DOWN,
				"il colpo su %s diventa solo Duck Back" % target.display_name):
		# "Keep Your Head Down": niente pesca ferita, solo testa giu'.
		target.set_order(D.Order.DUCK_BACK)
	elif target.side == D.Side.ENEMY and _crack_shot_worthy(target) \
			and FriendlyCards.use_from_hand(state, FriendlyCards.CRACK_SHOT,
				"%s e' ucciso sul colpo" % target.display_name):
		# "Crack Shot": il colpo riuscito uccide automaticamente.
		while not target.is_dead():
			target.wounds.append(D.Wound.BAD)
		target.clear_order()
		wounded_or_killed = true
	else:
		wounded_or_killed = _resolve_wound(state, target)
	# 0 naturale: il tiratore si esalta se ha fatto danno (mai Berserk).
	if roll == 0 and wounded_or_killed:
		firer.morale = D.raise_morale(firer.morale, 1, D.Morale.AGGRESSIVE)
		_log(state, "%s si esalta: morale %s" % [
			firer.display_name, D.MORALE_NAMES[firer.morale]])
	return {"hit": true, "nine": false}


# La Crack Shot si spende solo su bersagli di valore (leader, mitragliere,
# truppa d'elite), non sul primo soldato semplice colpito.
static func _crack_shot_worthy(target: Character) -> bool:
	return target.leadership > 0 or target.troop_quality >= 6 \
		or target.weapon_skills.has("MG42")


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
			state.audio_events.append({"type": "scream", "hex": target.position})
			Replay.sfx(state, "scream")
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


# Pesca della ferita in mischia (Rule 15): niente Duck Back, ma MC + WMC.
static func _resolve_wound_melee(state: GameState, target: Character) -> bool:
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
			state.audio_events.append({"type": "scream", "hex": target.position})
			Replay.sfx(state, "scream")
			return true
		_:
			var w: int = D.Wound.LIGHT if wound == FriendlyCards.WoundDraw.LIGHT_WOUND else D.Wound.BAD
			target.wounds.append(w)
			_log(state, "  pesca carta %d: %s per %s (niente Duck Back in mischia)" % [serial,
				"Light Wound" if w == D.Wound.LIGHT else "Bad Wound",
				target.display_name])
			if target.is_dead():
				_log(state, "  le ferite uccidono %s" % target.display_name)
				target.clear_order()
				return true
			# In mischia non si riceve Duck Back, ma MC e WMC come al solito.
			var mc := Checks.morale_check(target, state.rng)
			_log(state, "  MC mischia: tira %d -> %s" % [mc["roll"], D.MORALE_NAMES[mc["after"]]])
			var wmc := Checks.wound_morale_check(target, state.rng)
			_log(state, "  WMC mischia: tira %d -> %s" % [wmc["roll"], D.MORALE_NAMES[wmc["after"]]])
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


# Hexside attraversato entrando nell'hex del bersaglio (l'ultimo bordo
# del percorso di tiro), o -1.
static func _entry_hexside(state: GameState, from: Vector2i, to: Vector2i) -> int:
	var between := LOS.hexes_between(from, to)
	var prev := from
	if not between.is_empty():
		# hexes_between e' canonicalizzato: l'estremo adiacente a `to`
		# e' la fine o l'inizio a seconda della direzione.
		prev = between.back() if Spotting.hex_distance(between.back(), to) == 1 \
			else between[0]
	if Spotting.hex_distance(prev, to) != 1:
		return -1
	return state.hexside_between(prev, to)


# Penalita' del fumo lungo la linea di tiro (-4 pieno / -2 fading per hex).
static func _smoke_modifier(state: GameState, a: Vector2i, b: Vector2i) -> int:
	var mod := 0
	var line: Array[Vector2i] = [a, b]
	line.append_array(LOS.hexes_between(a, b))
	for hex in line:
		match Area.smoke_level(state, hex):
			2: mod -= 4
			1: mod -= 2
	return mod


static func _log(state: GameState, msg: String) -> void:
	state.log_event(msg)
