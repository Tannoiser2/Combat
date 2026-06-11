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
		# TODO regole speciali: ordini forzati Evade/Sneak al turno 1
		# (SR10), rinforzi al turno 4 (SR11), bussola/vento, Dummy,
		# uscita dal bordo per i nemici (SR13).
	},
}


# Costruisce la partita per lo scenario indicato.
static func build(state: GameState, scenario_id: String) -> void:
	assert(SCENARIOS.has(scenario_id), "Scenario sconosciuto: %s" % scenario_id)
	var sc: Dictionary = SCENARIOS[scenario_id]
	state.max_turns = sc["turns"]
	state.hand_limit = sc["hand_limit"]
	Boards.fill(state, sc["map"])

	for f in sc["friendly"]:
		state.characters.append(_make(f, D.Side.FRIENDLY))

	# Coppa nemica: mescola e piazza ai setup hex (coperti = alerted ma
	# non known, finche' il giocatore non li individua).
	var cup: Array = sc["enemy_cup"].duplicate()
	_shuffle(cup, state.rng)
	var hexes: Array = sc["enemy_setup"]
	for i in range(min(cup.size(), hexes.size())):
		var e := _make(cup[i], D.Side.ENEMY)
		var p: PackedStringArray = String(hexes[i]).split(",")
		e.position = Vector2i(int(p[0]), int(p[1]))
		e.alerted = true
		state.characters.append(e)

	# Mano iniziale (Starting Hand Size).
	for i in range(state.hand_limit):
		state.friendly_hand.append(state.draw_friendly_card())


# Crea un Character da una voce di scenario applicando il profilo del ruolo.
static func _make(entry: Dictionary, side: int) -> Character:
	var prof: Dictionary = ROLE[entry["role"]]
	var c := Character.new(entry["name"].to_lower().replace(" ", "_"),
		entry["name"], side, entry["team"])
	c.troop_quality = prof["tq"]
	c.leadership = prof["ldr"]
	c.weapon_skills = {prof["weapon"]: prof["ws"]}
	c.counter = entry.get("counter", "")
	if entry.has("pos"):
		var p: PackedStringArray = String(entry["pos"]).split(",")
		c.position = Vector2i(int(p[0]), int(p[1]))
	return c


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
