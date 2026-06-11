## Scenari dal Combat! Scenario Book: dati puri + costruzione del GameState.
##
## Ogni scenario e' un Dictionary dichiarativo (mappa, forze, schieramento,
## regole speciali). build() lo traduce in una partita pronta da giocare.
## Si aggiungono nuovi scenari aggiungendo voci a SCENARIOS: e' solo dati.
##
## Valori di TQ per ruolo PROVVISORI (vanno letti dai segnalini Vassal):
## sono ragionevoli ma da rifinire. I numeri accanto ai ruoli nel libro
## sono gli ID dei segnalini, non la TQ.
class_name Scenario
extends RefCounted

const D := preload("res://engine/Domain.gd")

# Profilo per ruolo: TQ, leadership, arma, WS. Approssimazioni da rifinire.
# Valori calibrati leggendo i segnalini Vassal (TQ rossa in alto, WS
# accanto alle armi). Variano un po' per pedina: questi sono tipici.
const ROLE := {
	"Recruit": {"tq": 4, "ldr": 0, "weapon": "KAR 98K", "ws": 3},
	"Rifleman": {"tq": 5, "ldr": 0, "weapon": "KAR 98K", "ws": 4},
	"Veteran": {"tq": 6, "ldr": 0, "weapon": "KAR 98K", "ws": 5},
	"NCO": {"tq": 5, "ldr": 1, "weapon": "MP40", "ws": 5},
	"Sniper": {"tq": 5, "ldr": 0, "weapon": "KAR 98K", "ws": 8},
	# Friendly
	"Leader": {"tq": 6, "ldr": 3, "weapon": "M3 Grease Gun", "ws": 7},
	"US Rifleman": {"tq": 5, "ldr": 0, "weapon": "M1 Garand", "ws": 5},
	"BAR Gunner": {"tq": 5, "ldr": 0, "weapon": "BAR", "ws": 5},
	"MG Gunner": {"tq": 5, "ldr": 0, "weapon": "M1919", "ws": 5},
	# Pedina-esca: valori minimi, non combatte mai.
	"Dummy": {"tq": 1, "ldr": 0, "weapon": "", "ws": 0},
}

# Nome ordine -> enum, per le tabelle testuali degli scenari.
const ORDER_BY_NAME := {
	"EVADE": D.Order.EVADE, "SNEAK": D.Order.SNEAK, "HIDE": D.Order.HIDE,
	"RUN_AND_GUN": D.Order.RUN_AND_GUN, "SPRINT": D.Order.SPRINT,
}

const SCENARIOS := {
	"intro1": {
		"name": "A Meeting of Patrols",
		"map": "hedgerows",
		"turns": 7,
		"hand_limit": 3,
		"desc": "Normandia, giugno 1944. Una pattuglia di sei uomini avanza\ntra le siepi per scoprire posizioni e forze del nemico.",
		# Pattuglia di 6 uomini (Opzione 1), schierata nel triangolo
		# 18.14/18.19/28.19.
		"friendly": [
			{"name": "Sgt Taylor", "role": "Leader", "team": "Able",
				"pos": "20,17", "counter": "US-Able-Sgt-Taylor"},
			{"name": "Pvt Brubaker", "role": "US Rifleman", "team": "Able",
				"pos": "19,17", "counter": "US-Able-Pvt-Brubaker"},
			{"name": "Pvt Cragg", "role": "US Rifleman", "team": "Able",
				"pos": "21,17", "counter": "US-Able-Pvt-Cragg"},
			{"name": "Pvt Butterman", "role": "US Rifleman", "team": "Charlie",
				"pos": "19,18", "counter": "US-Charlie-Pvt-Butterman"},
			{"name": "Pvt Connor", "role": "US Rifleman", "team": "Charlie",
				"pos": "20,18", "counter": "US-Charlie-Pvt-Connor"},
			{"name": "Pvt Douglas", "role": "US Rifleman", "team": "Charlie",
				"pos": "21,18", "counter": "US-Charlie-Pvt-Douglas"},
		],
		# La "Coppa": personaggi reali mescolati e piazzati coperti nei
		# 12 hex di setup (i Dummy del libro sono un TODO).
		"enemy_cup": [
			{"name": "Soldat Abbas", "role": "Recruit", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Abbas"},
			{"name": "Soldat Abend", "role": "Recruit", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Abend"},
			{"name": "Soldat Arnold", "role": "Recruit", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Arnold"},
			{"name": "Soldat Bach", "role": "Recruit", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Bach"},
			{"name": "Soldat Hahn", "role": "Rifleman", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Hahn"},
			{"name": "Soldat Horn", "role": "Rifleman", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Horn"},
			{"name": "Soldat Pfeiffer", "role": "Rifleman", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Pfeiffer"},
			{"name": "Obfr Sauer", "role": "NCO", "team": "Blue", "counter": "GE-BlueTeam-Obfr-Sauer"},
			{"name": "Obfr Franke", "role": "NCO", "team": "Red", "counter": "GE-RedTeam-Obfr-Franke"},
			{"name": "Obfr Gunther", "role": "Veteran", "team": "Red", "counter": "GE-RedTeam-Obfr-Gunther"},
			{"name": "Soldat Jung", "role": "Rifleman", "team": "Red", "counter": "GE-RedTeam-Soldat-Jung"},
			{"name": "Soldat Roth", "role": "Rifleman", "team": "Red", "counter": "GE-RedTeam-Soldat-Roth"},
			{"name": "Soldat Berger", "role": "Rifleman", "team": "Red", "counter": "GE-RedTeam-Soldat-Berger"},
			{"name": "Soldat Engel", "role": "Recruit", "team": "Red", "counter": "GE-RedTeam-Soldat-Engel"},
			{"name": "Soldat Friedrich", "role": "Recruit", "team": "Red", "counter": "GE-RedTeam-Soldat-Friedrich"},
			{"name": "Soldat Graf", "role": "Recruit", "team": "Red", "counter": "GE-RedTeam-Soldat-Graf"},
			{"name": "Soldat Haas", "role": "Sniper", "team": "Red", "counter": "GE-RedTeam-Soldat-Haas"},
		],
		"enemy_setup": [
			"22,5", "23,5", "24,5", "24,6", "27,4", "28,3",
			"29,4", "30,4", "29,8", "30,8", "30,9", "31,8",
		],
		# Pedine-esca aggiunte alla Coppa (SR del libro: Blue x5, Red x4).
		"dummies": 9,
		# SR1: nessun Event quando esce una carta Event (si rimescola).
		"no_events": true,
		# SR10: al PRIMO ordine (turno 1, e i rinforzi al turno 4) l'ordine
		# nemico non viene dal lookup ma da un 1D6 (0..9 -> qui 1..6).
		"first_order_d6": ["EVADE 5/6", "EVADE 6/5", "EVADE 5",
			"EVADE 6", "SNEAK 5", "SNEAK 6"],
		# SR11: rinforzi al turno 4, 4 pedine dalla Coppa.
		"waves": [{"turn": 4, "hexes": ["35,8", "35,7", "35,6", "35,5"]}],
		# SR13: i nemici possono uscire dalla mappa da qualsiasi bordo.
		"enemy_may_exit": true,
	},

	"intro2": {
		"name": "Rendezvous",
		"map": "village",
		"turns": 5,
		"hand_limit": 2,
		"desc": "La squadra divisa deve raggiungere la chiesa del paese.\nMa i tedeschi sono arrivati prima.",
		"friendly": [
			{"name": "Sgt Taylor", "role": "Leader", "team": "Able",
				"pos": "11,3", "counter": "US-Able-Sgt-Taylor"},
			{"name": "Pvt Brubaker", "role": "US Rifleman", "team": "Able",
				"pos": "11,4", "counter": "US-Able-Pvt-Brubaker"},
			{"name": "Pvt Cragg", "role": "US Rifleman", "team": "Able",
				"pos": "11,5", "counter": "US-Able-Pvt-Cragg"},
			{"name": "Pvt Johnson", "role": "US Rifleman", "team": "Baker",
				"pos": "11,8", "counter": "US-Baker-Pvt-Johnson"},
			{"name": "Pvt Miller", "role": "US Rifleman", "team": "Baker",
				"pos": "11,9", "counter": "US-Baker-Pvt-Miller"},
			{"name": "Pvt Peters", "role": "US Rifleman", "team": "Baker",
				"pos": "11,10", "counter": "US-Baker-Pvt-Peters"},
		],
		"enemy_cup": [
			{"name": "Soldat Abbas", "role": "Recruit", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Abbas"},
			{"name": "Soldat Abend", "role": "Recruit", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Abend"},
			{"name": "Soldat Arnold", "role": "Recruit", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Arnold"},
			{"name": "Soldat Bach", "role": "Recruit", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Bach"},
			{"name": "Soldat Hahn", "role": "Recruit", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Hahn"},
			{"name": "Cecchino Blue", "role": "Sniper", "team": "Blue"},
			{"name": "Soldat Engel", "role": "Recruit", "team": "Red", "counter": "GE-RedTeam-Soldat-Engel"},
			{"name": "Soldat Friedrich", "role": "Recruit", "team": "Red", "counter": "GE-RedTeam-Soldat-Friedrich"},
			{"name": "Soldat Graf", "role": "Recruit", "team": "Red", "counter": "GE-RedTeam-Soldat-Graf"},
			{"name": "Soldat Jung", "role": "Recruit", "team": "Red", "counter": "GE-RedTeam-Soldat-Jung"},
			{"name": "Soldat Roth", "role": "Recruit", "team": "Red", "counter": "GE-RedTeam-Soldat-Roth"},
			{"name": "Soldat Haas", "role": "Sniper", "team": "Red", "counter": "GE-RedTeam-Soldat-Haas"},
		],
		"dummies": 6,
		"enemy_setup": ["19,5", "20,3", "24,7", "25,9", "28,4", "28,10"],
		"no_events": true,
		# SR12: nemico Alerted in un edificio: TQC -> Aimed Fire automatico.
		"building_tqc_aimed": true,
		# SR13: esca rivelata -> 1D10 (0 carte, 1-6 un uomo di Charlie, 7-9 via).
		"dummy_roll": true,
		"waves": [{"turn": 3, "hexes": ["29,1", "29,2", "29,3"],
			"forced": "RUN_AND_GUN 5"}],
		# Vittoria a VP (chiesa = 24.06/24.07).
		"vp": {"enemy_killed": 1, "friendly_killed": -2, "friendly_wounded": -1,
			"church_hexes": ["24,6", "24,7"], "church_each": 3,
			"no_enemy_in_building": 5},
	},

	"intro3": {
		"name": "Get That Gun",
		"map": "farmhouse",
		"turns": 7,
		"hand_limit": 2,
		"desc": "Un pezzo d'artiglieria martella il C.P. della compagnia.\nCharlie Team avanza con le cariche C4.",
		"friendly_morale": 2,  # Bold
		"friendly": [
			{"name": "Cpl Thomas", "role": "Leader", "team": "Charlie", "pos": "11,13"},
			{"name": "Pvt Butterman", "role": "US Rifleman", "team": "Charlie",
				"pos": "11,14", "counter": "US-Charlie-Pvt-Butterman"},
			{"name": "Pvt Connor", "role": "US Rifleman", "team": "Charlie",
				"pos": "11,15", "counter": "US-Charlie-Pvt-Connor"},
			{"name": "Pvt Douglas", "role": "US Rifleman", "team": "Charlie",
				"pos": "11,16", "counter": "US-Charlie-Pvt-Douglas"},
			{"name": "Pvt Kowalski", "role": "US Rifleman", "team": "Charlie",
				"pos": "11,17", "counter": "US-Charlie-Pvt-Kowalski"},
			{"name": "Pvt Stubbs", "role": "BAR Gunner", "team": "Charlie",
				"pos": "11,18", "counter": "US-Charlie-Pvt-Stubbs"},
		],
		"enemy_cup": [
			{"name": "Obfr Sauer", "role": "NCO", "team": "Blue", "counter": "GE-BlueTeam-Obfr-Sauer"},
			{"name": "Soldat Hahn", "role": "Rifleman", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Hahn"},
			{"name": "Soldat Horn", "role": "Rifleman", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Horn"},
			{"name": "Soldat Pfeiffer", "role": "Rifleman", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Pfeiffer"},
			{"name": "Soldat Abbas", "role": "Recruit", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Abbas"},
			{"name": "Soldat Abend", "role": "Recruit", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Abend"},
			{"name": "Soldat Arnold", "role": "Recruit", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Arnold"},
			{"name": "Soldat Bach", "role": "Recruit", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Bach"},
			{"name": "Obfr Gunther", "role": "Veteran", "team": "Red", "counter": "GE-RedTeam-Obfr-Gunther"},
			{"name": "Soldat Haas", "role": "Sniper", "team": "Red", "counter": "GE-RedTeam-Soldat-Haas"},
			{"name": "Soldat Engel", "role": "Recruit", "team": "Red", "counter": "GE-RedTeam-Soldat-Engel"},
			{"name": "Soldat Friedrich", "role": "Recruit", "team": "Red", "counter": "GE-RedTeam-Soldat-Friedrich"},
			{"name": "Soldat Graf", "role": "Recruit", "team": "Red", "counter": "GE-RedTeam-Soldat-Graf"},
			{"name": "Soldat Jung", "role": "Recruit", "team": "Red", "counter": "GE-RedTeam-Soldat-Jung"},
			{"name": "Soldat Roth", "role": "Recruit", "team": "Red", "counter": "GE-RedTeam-Soldat-Roth"},
		],
		"dummies": 10,
		"enemy_setup": ["19,14", "17,11", "19,12", "20,17", "17,10", "22,14",
			"16,16", "22,10", "21,18", "20,18", "22,19"],
		"no_events": true,
		# Il cannone da distruggere e le cariche C4 (Plan = piazza C4).
		"gun_hex": "20,15",
		"c4": true,
		"vp": {"enemy_killed": 1, "friendly_killed": -2, "friendly_wounded": -1,
			"gun_destroyed_required": true},
	},

	"intro4": {
		"name": "Here They Come!",
		"map": "hill",
		"turns": 7,
		"hand_limit": 3,
		"desc": "Notte. Charlie Team e' di vedetta quando un ramo si spezza.\nUn grido: \"Eccoli, arrivano!\"",
		"night": true,
		"friendly": [
			{"name": "Cpl Thomas", "role": "Leader", "team": "Charlie", "pos": "21,5"},
			{"name": "Pvt Butterman", "role": "US Rifleman", "team": "Charlie",
				"pos": "20,4", "counter": "US-Charlie-Pvt-Butterman"},
			{"name": "Pvt Connor", "role": "US Rifleman", "team": "Charlie",
				"pos": "20,6", "counter": "US-Charlie-Pvt-Connor"},
			{"name": "Pvt Douglas", "role": "US Rifleman", "team": "Charlie",
				"pos": "21,7", "counter": "US-Charlie-Pvt-Douglas"},
			{"name": "Pvt Kowalski", "role": "US Rifleman", "team": "Charlie",
				"pos": "22,4", "counter": "US-Charlie-Pvt-Kowalski"},
			{"name": "Pvt Stubbs", "role": "MG Gunner", "team": "Charlie",
				"pos": "22,6", "counter": "US-Charlie-Pvt-Stubbs"},
		],
		"enemy_cup": [
			{"name": "Obfr Sauer", "role": "NCO", "team": "Blue", "counter": "GE-BlueTeam-Obfr-Sauer"},
			{"name": "Soldat Hahn", "role": "Rifleman", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Hahn"},
			{"name": "Soldat Horn", "role": "Rifleman", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Horn"},
			{"name": "Soldat Pfeiffer", "role": "Rifleman", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Pfeiffer"},
			{"name": "Soldat Abbas", "role": "Recruit", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Abbas"},
			{"name": "Soldat Abend", "role": "Recruit", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Abend"},
			{"name": "Soldat Arnold", "role": "Recruit", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Arnold"},
			{"name": "Soldat Bach", "role": "Recruit", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Bach"},
			{"name": "Obfr Gunther", "role": "Veteran", "team": "Red", "counter": "GE-RedTeam-Obfr-Gunther"},
			{"name": "Soldat Engel", "role": "Recruit", "team": "Red", "counter": "GE-RedTeam-Soldat-Engel"},
			{"name": "Soldat Friedrich", "role": "Recruit", "team": "Red", "counter": "GE-RedTeam-Soldat-Friedrich"},
			{"name": "Soldat Graf", "role": "Recruit", "team": "Red", "counter": "GE-RedTeam-Soldat-Graf"},
			{"name": "Soldat Jung", "role": "Recruit", "team": "Red", "counter": "GE-RedTeam-Soldat-Jung"},
			{"name": "Soldat Roth", "role": "Recruit", "team": "Red", "counter": "GE-RedTeam-Soldat-Roth"},
			{"name": "Soldat Berger", "role": "Rifleman", "team": "Red", "counter": "GE-RedTeam-Soldat-Berger"},
		],
		"dummies": 6,
		"enemy_setup": ["11,5", "11,6", "11,7", "11,8", "11,9"],
		"no_events": true,
		"first_order_d6": ["EVADE 6", "EVADE 5", "EVADE 5/6",
			"EVADE 6/5", "RUN_AND_GUN 5", "SNEAK 5/6"],
		# Ondate: altri nemici dalla Coppa agli stessi hex ai turni 2 e 3.
		"waves": [
			{"turn": 2, "hexes": ["11,5", "11,6", "11,7", "11,8", "11,9"]},
			{"turn": 3, "hexes": ["11,5", "11,6", "11,7", "11,8", "11,9"]},
		],
		"vp": {"enemy_killed": 1, "friendly_killed": -2, "friendly_wounded": -1},
	},
}


# Costruisce la partita per lo scenario indicato.
static func build(state: GameState, scenario_id: String) -> void:
	assert(SCENARIOS.has(scenario_id), "Scenario sconosciuto: %s" % scenario_id)
	var sc: Dictionary = SCENARIOS[scenario_id]
	state.scenario_id = scenario_id
	state.max_turns = sc["turns"]
	state.hand_limit = sc["hand_limit"]
	Boards.fill(state, sc["map"])

	for f in sc["friendly"]:
		var fc := _make(f, D.Side.FRIENDLY)
		fc.morale = int(sc.get("friendly_morale", D.Morale.NORMAL))
		state.characters.append(fc)
	# Scenario notturno: -2 al fuoco oltre 2 hex (salvo illuminazione).
	state.night = bool(sc.get("night", false))

	# Coppa nemica = personaggi reali + pedine-esca, mescolata.
	var cup: Array = sc["enemy_cup"].duplicate()
	for i in range(int(sc.get("dummies", 0))):
		cup.append({"name": "Esca", "role": "Dummy",
			"team": "Blue" if i % 2 == 0 else "Red"})
	_shuffle(cup, state.rng)
	# Si piazza ai setup hex (coperti); il resto resta in riserva (rinforzi).
	var hexes: Array = sc["enemy_setup"]
	var placed := 0
	for entry in cup:
		if placed >= hexes.size():
			state.enemy_reserve.append(entry)
			continue
		_place_enemy(state, entry, hexes[placed])
		placed += 1

	# Mano iniziale (Starting Hand Size).
	for i in range(state.hand_limit):
		state.friendly_hand.append(state.draw_friendly_card())


# Piazza un personaggio nemico (coperto = alerted, non known) a un hex.
static func _place_enemy(state: GameState, entry: Dictionary, hexkey: String) -> Character:
	var e := _make(entry, D.Side.ENEMY)
	var p: PackedStringArray = String(hexkey).split(",")
	e.position = Vector2i(int(p[0]), int(p[1]))
	e.alerted = true
	state.characters.append(e)
	return e


# Ondate di rinforzi: pesca dalla riserva e piazza agli hex dell'ondata.
# forced (es. "RUN_AND_GUN 5") assegna subito quell'ordine ai nuovi.
static func run_waves(state: GameState) -> void:
	var sc: Dictionary = SCENARIOS[state.scenario_id]
	for wave in sc.get("waves", []):
		var t: int = wave["turn"]
		if state.turn != t or t in state.waves_done:
			continue
		state.waves_done.append(t)
		var arrived := false
		for hexkey in wave["hexes"]:
			if state.enemy_reserve.is_empty():
				break
			var e := _place_enemy(state, state.enemy_reserve.pop_front(), hexkey)
			arrived = true
			if wave.has("forced"):
				var parts: PackedStringArray = String(wave["forced"]).split(" ")
				e.set_order(ORDER_BY_NAME[parts[0]], parts[1])
				e.had_first_order = true
		if arrived:
			state.log_event("Arrivano rinforzi nemici al bordo!")


# Ordine forzato di scenario al primo ordine (1D6). Ritorna {order, move}
# oppure {} se lo scenario non ha la regola.
static func first_order(scenario_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var sc: Dictionary = SCENARIOS[scenario_id]
	if not sc.has("first_order_d6"):
		return {}
	var entry: String = sc["first_order_d6"][rng.randi_range(0, 5)]
	var parts := entry.split(" ")
	return {"order": ORDER_BY_NAME[parts[0]], "move": parts[1]}


# Crea un Character da una voce di scenario applicando il profilo del ruolo.
static func _make(entry: Dictionary, side: int) -> Character:
	var prof: Dictionary = ROLE[entry["role"]]
	var c := Character.new(entry["name"].to_lower().replace(" ", "_"),
		entry["name"], side, entry["team"])
	c.troop_quality = prof["tq"]
	c.leadership = prof["ldr"]
	if not String(prof["weapon"]).is_empty():
		c.weapon_skills = {prof["weapon"]: prof["ws"]}
	c.counter = entry.get("counter", "")
	c.is_dummy = entry["role"] == "Dummy"
	if entry.has("pos"):
		var p: PackedStringArray = String(entry["pos"]).split(",")
		c.position = Vector2i(int(p[0]), int(p[1]))
	return c


# Conteggio forze: vivi/morti per lato, nemici identificati.
static func tally(state: GameState) -> Dictionary:
	var t := {"f_alive": 0, "f_dead": 0, "e_alive": 0, "e_dead": 0, "e_known": 0}
	for c in state.characters:
		if c.side == D.Side.FRIENDLY:
			t["f_dead" if c.is_dead() else "f_alive"] += 1
		else:
			if c.is_dead():
				t["e_dead"] += 1
			else:
				t["e_alive"] += 1
				if c.known:
					t["e_known"] += 1
	return t


# Esito dello scenario: a VP dove il libro li da' (intro2/3/4), euristica
# di ricognizione per intro1 (il libro non da' VP formali).
# Ritorna {outcome, detail, vp}.
static func victory(state: GameState, scenario_id: String) -> Dictionary:
	var sc: Dictionary = SCENARIOS[scenario_id]
	var t := tally(state)
	if not sc.has("vp"):
		return _victory_recon(state, t)
	var vp_rules: Dictionary = sc["vp"]
	var vp := 0
	var parts: Array[String] = []
	vp += t["e_dead"] * int(vp_rules.get("enemy_killed", 0))
	parts.append("%d nemici eliminati" % t["e_dead"])
	vp += t["f_dead"] * int(vp_rules.get("friendly_killed", 0))
	parts.append("%d caduti" % t["f_dead"])
	var wounded := 0
	for c in state.characters:
		if c.side == D.Side.FRIENDLY and not c.is_dead() and not c.wounds.is_empty():
			wounded += 1
	vp += wounded * int(vp_rules.get("friendly_wounded", 0))
	if wounded > 0:
		parts.append("%d feriti" % wounded)
	# Chiesa (intro2): +N per ogni Friendly negli hex obiettivo.
	if vp_rules.has("church_hexes"):
		var in_church := 0
		for c in state.characters:
			if c.side == D.Side.FRIENDLY and not c.is_dead() \
					and ("%d,%d" % [c.position.x, c.position.y]) in vp_rules["church_hexes"]:
				in_church += 1
		vp += in_church * int(vp_rules["church_each"])
		parts.append("%d alla chiesa" % in_church)
	if vp_rules.has("no_enemy_in_building"):
		if not _enemy_in_building(state):
			vp += int(vp_rules["no_enemy_in_building"])
			parts.append("edifici liberi")
	# Cannone (intro3): obiettivo obbligatorio.
	if vp_rules.get("gun_destroyed_required", false):
		if state.gun_destroyed:
			return {"outcome": "Vittoria - cannone distrutto!", "vp": vp,
				"detail": ", ".join(parts)}
		return {"outcome": "Sconfitta - il cannone spara ancora", "vp": vp,
			"detail": ", ".join(parts)}
	var outcome := "Sconfitta"
	if vp >= 13:
		outcome = "Vittoria netta"
	elif vp >= 8:
		outcome = "Vittoria"
	elif vp >= 4:
		outcome = "Vittoria risicata"
	elif vp >= 1:
		outcome = "Prestazione scarsa"
	return {"outcome": outcome, "vp": vp,
		"detail": "%d VP - %s" % [vp, ", ".join(parts)]}


static func _enemy_in_building(state: GameState) -> bool:
	for c in state.characters:
		if c.side != D.Side.ENEMY or c.is_dead():
			continue
		var hex := state.hex_at(c.position.x, c.position.y)
		if hex != null and hex.terrain == D.Terrain.BUILDING:
			return true
	return false


static func _victory_recon(state: GameState, t: Dictionary) -> Dictionary:
	var recon: int = t["e_known"] + t["e_dead"]
	var outcome := "Pareggio"
	if t["f_alive"] == 0:
		outcome = "Sconfitta"
	elif t["f_dead"] <= 2 and recon >= 6:
		outcome = "Vittoria"
	elif t["f_dead"] <= 3 and recon >= 4:
		outcome = "Vittoria parziale"
	elif t["f_dead"] >= 4:
		outcome = "Sconfitta"
	var detail := "Pattuglia: %d vivi, %d caduti - Nemici: %d individuati, %d eliminati" % [
		t["f_alive"], t["f_dead"], t["e_known"], t["e_dead"]]
	return {"outcome": outcome, "detail": detail, "vp": recon - t["f_dead"]}


# Un lato e' stato annientato? (per la fine anticipata della partita)
static func side_eliminated(state: GameState) -> bool:
	var t := tally(state)
	return t["f_alive"] == 0 or t["e_alive"] == 0


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
