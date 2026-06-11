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
const ROLE := {
	"Recruit": {"tq": 3, "ldr": 0, "weapon": "KAR 98K", "ws": 3},
	"Rifleman": {"tq": 4, "ldr": 0, "weapon": "KAR 98K", "ws": 4},
	"Veteran": {"tq": 6, "ldr": 0, "weapon": "KAR 98K", "ws": 6},
	"NCO": {"tq": 5, "ldr": 2, "weapon": "MP40", "ws": 5},
	"Sniper": {"tq": 6, "ldr": 0, "weapon": "KAR 98K", "ws": 8},
	# Friendly
	"Leader": {"tq": 6, "ldr": 3, "weapon": "M3 Grease Gun", "ws": 7},
	"US Rifleman": {"tq": 5, "ldr": 0, "weapon": "M1 Garand", "ws": 5},
	"BAR Gunner": {"tq": 5, "ldr": 0, "weapon": "BAR", "ws": 5},
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
		# SR11: rinforzi al turno 4, 4 pedine dalla Coppa ai seguenti hex.
		"reinforce_turn": 4,
		"reinforce_hexes": ["35,8", "35,7", "35,6", "35,5"],
		# SR13: i nemici possono uscire dalla mappa da qualsiasi bordo.
		"enemy_may_exit": true,
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
		state.characters.append(_make(f, D.Side.FRIENDLY))

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


# Rinforzi (SR11): pesca dalla riserva e piazza ai reinforce_hexes.
static func bring_reinforcements(state: GameState) -> void:
	var sc: Dictionary = SCENARIOS[state.scenario_id]
	var hexes: Array = sc.get("reinforce_hexes", [])
	for hexkey in hexes:
		if state.enemy_reserve.is_empty():
			return
		_place_enemy(state, state.enemy_reserve.pop_front(), hexkey)
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


# Esito dello scenario. PROVVISORIO: il libro non da' VP formali per gli
# scenari introduttivi, quindi per "A Meeting of Patrols" (ricognizione)
# si valuta quanto la pattuglia e' rientrata intatta e quanti nemici ha
# individuato o eliminato. {outcome, detail}.
static func victory(state: GameState, scenario_id: String) -> Dictionary:
	var t := tally(state)
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
	return {"outcome": outcome, "detail": detail}


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
