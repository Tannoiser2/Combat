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
	# Volume 2, Rule 27 (Order/Terrain Chart). Trench = Depression.
	D.Terrain.FOUNTAIN: [-2, -2, -2, -1, -1, -1, -1],
	D.Terrain.FORTIFIED_BUILDING: [-5, -4, -3, -3, -2, -3, -3],
	D.Terrain.TRENCH: [-4, -2, -1, -1, -1, -1, -1],
}

# Celle "M" del chart: un bersaglio con ordini Hide/Rally/Reload in
# copertura dura subisce solo un Morale Check, mai ferite.
const MC_ONLY := [
	[D.Terrain.ROCKS, 0], [D.Terrain.BUILDING, 0],
	[D.Terrain.WALL, 0], [D.Terrain.RUBBLE, 0],
	[D.Terrain.FORTIFIED_BUILDING, 0],  # Rule 27.2: come Building
]

const WOUND_MOD := {D.Wound.LIGHT: -1, D.Wound.BAD: -3}
# Abbazia (Rule 27.5): la copertura di un bersaglio in un hex d'abbazia dipende
# da DOVE spara il tiratore (dentro o fuori dall'abbazia), non solo dal terreno.
const ABBEY_WS_OUTSIDE := [-5, -3, -3, -2, -1, -3, -3]
const ABBEY_WS_INSIDE := [-3, -2, -2, -1, -1, -2, -2]

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
	# Abbazia (Rule 27.5): da fuori si colpiscono solo gli hex esterni; chi e'
	# in un hex interno e' immune al fuoco proveniente da fuori dall'abbazia.
	var th := state.hex_at(target.position.x, target.position.y)
	if th != null and th.terrain == D.Terrain.ABBEY_INTERIOR and not _in_abbey(state, firer.position):
		return false
	return LOS.clear(state, firer, target)


# Il personaggio e' dentro l'abbazia (suo hex con collare rosso o rosso+giallo)?
static func _in_abbey(state: GameState, pos: Vector2i) -> bool:
	var h := state.hex_at(pos.x, pos.y)
	return h != null and Domain.is_abbey(h.terrain)


# Quanti hex d'abbazia attraversa la linea di tiro (estremi esclusi)?
static func _abbey_hexes_crossed(state: GameState, a: Vector2i, b: Vector2i) -> int:
	var n := 0
	for pos in LOS.hexes_between(a, b):
		var h := state.hex_at(pos.x, pos.y)
		if h != null and Domain.is_abbey(h.terrain):
			n += 1
	return n


# Un'azione di fuoco completa: ROF attacchi in sequenza sul bersaglio.
static func fire_action(state: GameState, firer: Character, target: Character, weapon: String) -> void:
	var dist := Spotting.hex_distance(firer.position, target.position)
	var rof := Weapons.rof_at(weapon, dist)
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
	state.audio_events.append({"type": "shot", "weapon": weapon,
		"outcome": outcome, "hex": firer.position})


# Coltello da lancio del Knife Expert (Rule 24): ROF 1, gittata 2,
# WS = TQ - gittata. Lanciando da un hex con copertura il lanciatore NON si
# rivela (resta nascosto); altrimenti si rivela ("flip"). E' un'azione
# esplicita (giocatore/campagna): i nemici usano la skill solo per il +1 TQ
# in mischia, quindi l'AI non chiama mai questa funzione. Ritorna true se
# il lancio e' avvenuto.
static func throw_knife(state: GameState, attacker: Character, target: Character) -> bool:
	if not attacker.has_skill(Character.SKILL_KNIFE_EXPERT):
		return false
	if not can_fire(state, attacker, target, "Thrown Knife"):
		return false
	fire_action(state, attacker, target, "Thrown Knife")
	if not _in_cover(state, attacker):
		if attacker.side == D.Side.ENEMY:
			attacker.known = true
		else:
			attacker.spotted = true
	return true


# Il personaggio e' in copertura (terreno o hexside) nel suo hex?
static func _in_cover(state: GameState, c: Character) -> bool:
	var hex := state.hex_at(c.position.x, c.position.y)
	return (hex != null and Domain.terrain_gives_cover(hex.terrain)) \
		or state.hex_has_hexside(c.position)


# WS finale del tiro per la sola fascia di scelta del bersaglio (helper di
# test/UI): solo il valore, senza tirare il dado. Usa la prima arma del
# tiratore.
static func _fire_ws(state: GameState, firer: Character, target: Character) -> int:
	var weapon: String = firer.weapon_skills.keys()[0]
	return int(_compute_ws(state, firer, target, weapon)["ws"])


# Calcolo del WS modificato con la scomposizione per il log (Fire Resolution
# Chart + "MODIFIES WS"). Estratto da _resolve_attack cosi' e' testabile a
# parte. Ritorna {"ws": int, "bits": Array[String]}.
static func _compute_ws(state: GameState, firer: Character, target: Character, weapon: String) -> Dictionary:
	var dist := Spotting.hex_distance(firer.position, target.position)
	var hex := state.hex_at(target.position.x, target.position.y)
	var terrain: int = hex.terrain if hex != null else D.Terrain.OPEN_LEVEL_0
	var group: int = WS_GROUP.get(target.order, NO_ORDER_GROUP) \
		if target.has_order else NO_ORDER_GROUP
	var suppressive := firer.has_order and firer.order == D.Order.SUPPRESSIVE_FIRE

	# WS base: dalle skill d'arma, oppure TQ - gittata per il coltello da
	# lancio del Knife Expert (Rule 24).
	var ws: int
	var bits: Array[String]
	if "knife" in Weapons.info(weapon)["flags"]:
		ws = Checks.effective_tq(firer) - dist
		bits = ["%d coltello (TQ %d - gittata %d)" % [ws, Checks.effective_tq(firer), dist]]
	else:
		ws = firer.weapon_skills[weapon]
		bits = ["%d base %s" % [ws, weapon]]
	var m: int = int(Weapons.range_ws_modifier(weapon, dist))
	if m != 0:
		bits.append("%+d gittata %d hex" % [m, dist])
	ws += m
	if not suppressive:
		var tmod: int
		var tname: String
		if Domain.is_abbey(terrain):
			# Abbazia (Rule 27.5): riga a seconda che il tiratore sia dentro o fuori.
			var inside := _in_abbey(state, firer.position)
			tmod = (ABBEY_WS_INSIDE if inside else ABBEY_WS_OUTSIDE)[group]
			tname = "abbazia (tiratore %s)" % ("dentro" if inside else "fuori")
		else:
			tmod = WS_MOD[terrain][group]
			tname = Domain.TERRAIN_NAMES[terrain]
			# Hexside sul bordo d'ingresso del tiro (siepe/bocage/muro davanti
			# al bersaglio): vale il modificatore piu' protettivo.
			var side := _entry_hexside(state, firer.position, target.position)
			if side >= 0 and WS_MOD[side][group] < tmod:
				tmod = WS_MOD[side][group]
				tname = Domain.TERRAIN_NAMES[side] + " (bordo)"
		if tmod != 0:
			bits.append("%+d bersaglio in %s" % [tmod, tname])
		ws += tmod
		# Abbazia: -1 per ogni hex d'abbazia attraversato dal tiro (Rule 27.5).
		var crossed := _abbey_hexes_crossed(state, firer.position, target.position)
		if crossed > 0:
			bits.append("-%d abbazia attraversata" % crossed)
			ws -= crossed
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
	# Filo spinato (Rule 27.7): -1 al WS sparando da un hex con filo spinato.
	if state.has_wire(firer.position):
		bits.append("-1 filo spinato")
		ws -= 1
	# Skill SS (Rule 24): Dodge del bersaglio in Evade, Sniper del tiratore.
	if target.has_order and target.order == D.Order.EVADE:
		if target.has_skill(Character.SKILL_DODGE_2):
			bits.append("-2 Dodge-2 (Evade)")
			ws -= 2
		elif target.has_skill(Character.SKILL_DODGE):
			bits.append("-1 Dodge (Evade)")
			ws -= 1
	if firer.has_skill(Character.SKILL_SNIPER) and firer.has_order \
			and firer.order == D.Order.AIMED_FIRE and state.impulse != 2:
		bits.append("+2 Sniper (Aimed)")
		ws += 2
	# Mirino (Rule 26, es. M1903 Springfield): +1 in Aimed Fire oltre i 3 hex.
	if "scoped" in Weapons.info(weapon)["flags"] and firer.has_order \
			and firer.order == D.Order.AIMED_FIRE and dist > 3:
		bits.append("+1 mirino (Aimed >3)")
		ws += 1
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
	# Ambiente: eventi/scenario, fumo lungo il tiro, notte, meteo (Rule 28).
	m = int(state.turn_fx.get("fire_env_mod", 0))
	m += _smoke_modifier(state, firer.position, target.position)
	if state.night and dist > 2 and not Area.illuminated(state, target.position):
		m += -2
	m += Weather.ws_modifier(state, firer, target, dist)
	if m != 0:
		bits.append("%+d ambiente (fumo/notte/meteo)" % m)
	ws += m
	# TODO: filo spinato per-hex.
	return {"ws": ws, "bits": bits}


# Ritorna {hit: bool, nine: bool}.
static func _resolve_attack(state: GameState, firer: Character, target: Character, weapon: String) -> Dictionary:
	var hex := state.hex_at(target.position.x, target.position.y)
	var terrain: int = hex.terrain if hex != null else D.Terrain.OPEN_LEVEL_0
	var group: int = WS_GROUP.get(target.order, NO_ORDER_GROUP) \
		if target.has_order else NO_ORDER_GROUP
	var suppressive := firer.has_order and firer.order == D.Order.SUPPRESSIVE_FIRE
	var computed := _compute_ws(state, firer, target, weapon)
	var ws: int = computed["ws"]
	var bits: Array = computed["bits"]

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
		wounded_or_killed = _resolve_wound(state, firer, target)
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


# Pesca la carta-ferita tenendo conto delle skill SS (Rule 24): Deadly del
# tiratore pesca 2 e applica la PIU' dannosa, Tough del bersaglio pesca 2 e
# applica la MENO dannosa; se valgono entrambe (Deadly vs Tough) si annullano
# e si pesca una sola carta. Logga il pescaggio e ritorna il serial scelto.
static func _draw_wound(state: GameState, firer: Character, target: Character) -> int:
	var bias := 0
	if firer != null and firer.has_skill(Character.SKILL_DEADLY):
		bias += 1
	if target.has_skill(Character.SKILL_TOUGH):
		bias -= 1
	var s1 := state.draw_friendly_card()
	state.friendly_discard.append(s1)
	if bias == 0:
		return s1
	var s2 := state.draw_friendly_card()
	state.friendly_discard.append(s2)
	var sev1: int = FriendlyCards.wound_of(s1)
	var sev2: int = FriendlyCards.wound_of(s2)
	if bias > 0:
		_log(state, "  Deadly: pesca %d e %d, applica la peggiore" % [s1, s2])
		return s1 if sev1 >= sev2 else s2
	_log(state, "  Tough: pesca %d e %d, applica la meno grave" % [s1, s2])
	return s1 if sev1 <= sev2 else s2


# Rule 30.1: alla morte o ferita GRAVE di un Medico friendly, ogni friendly
# con LOS reagisce (Injured/KIA Medic Morale Check): nat 0 +2, <=TQ +1,
# nat 9 -1 (cap Berserk). Si attiva solo per i medici friendly.
static func _medic_shock(state: GameState, medic: Character) -> void:
	if medic.side != D.Side.FRIENDLY or not medic.is_medic:
		return
	_log(state, "%s (medico) e' caduto: i compagni con LOS reagiscono" % medic.display_name)
	for c in state.characters:
		if c.side != D.Side.FRIENDLY or c == medic or c.is_dead():
			continue
		if not LOS.clear(state, c, medic):
			continue
		var roll := Checks.roll_d10(state.rng)
		var before := c.morale
		if roll == 0:
			c.morale = D.raise_morale(c.morale, 2, D.Morale.BERSERK)
		elif roll == 9:
			c.morale = D.lower_morale(c.morale, 1)
		elif roll <= Checks.effective_tq(c):
			c.morale = D.raise_morale(c.morale, 1, D.Morale.BERSERK)
		if c.morale != before:
			_log(state, "  %s: tira %d -> %s" % [c.display_name, roll, D.MORALE_NAMES[c.morale]])


# Pesca della ferita con una Friendly Card. Ritorna true se ferito/ucciso.
static func _resolve_wound(state: GameState, firer: Character, target: Character) -> bool:
	var serial := _draw_wound(state, firer, target)
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
			# Niente urlo qui: per il fuoco lo suona l'esito "Ucciso!" di
			# fire_action; per le esplosioni ci pensa Area._blast_check.
			_medic_shock(state, target)
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
				_medic_shock(state, target)
				return true
			if w == D.Wound.BAD:
				_medic_shock(state, target)
			target.set_order(D.Order.DUCK_BACK)
			var res := Checks.wound_morale_check(target, state.rng)
			_log(state, "  WMC: tira %d -> %s, Duck Back" % [
				res["roll"], D.MORALE_NAMES[res["after"]]])
			return true


# Pesca della ferita in mischia (Rule 15): niente Duck Back, ma MC + WMC.
static func _resolve_wound_melee(state: GameState, firer: Character, target: Character) -> bool:
	var serial := _draw_wound(state, firer, target)
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
			_medic_shock(state, target)
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
				_medic_shock(state, target)
				return true
			if w == D.Wound.BAD:
				_medic_shock(state, target)
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


# Penalita' di fumo e incendi lungo la linea di tiro (numero di fumo per hex,
# Rule 29.2: gli incendi contano come fumo e ostacolano il tiro).
static func _smoke_modifier(state: GameState, a: Vector2i, b: Vector2i) -> int:
	var mod := 0
	var line: Array[Vector2i] = [a, b]
	line.append_array(LOS.hexes_between(a, b))
	for hex in line:
		mod += Area.smoke_penalty(state, hex)
	return mod


static func _log(state: GameState, msg: String) -> void:
	state.log_event(msg)
