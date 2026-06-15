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
	"Officer": {"tq": 6, "ldr": 2, "weapon": "MP40", "ws": 5},
	"Elite": {"tq": 7, "ldr": 0, "weapon": "MP40", "ws": 6},
	"LMG": {"tq": 5, "ldr": 0, "weapon": "MG42", "ws": 5},
	"Sniper": {"tq": 5, "ldr": 0, "weapon": "KAR 98K", "ws": 8},
	"Maquis": {"tq": 4, "ldr": 0, "weapon": "M1911", "ws": 3},
	# Truppe SS (Rule 24): skill per ruolo — ogni archetipo ha una specializzazione.
	# Schutze: assaltatori (Dodge + Knife Expert, +1 TQ in mischia).
	# NCO: capisquadra che spottano (Dodge + Eagle Eyes, TQ 7+1=8 spotting).
	# Veteran: duri e letali (Dodge + Tough + Deadly).
	# Officer: tiratori di precisione (Dodge + Sniper, WS 7+2=9 in Aimed).
	"SS Schutze": {"tq": 6, "ldr": 0, "weapon": "StG 44", "ws": 5,
		"skills": ["Dodge", "Knife Expert"]},
	"SS Veteran": {"tq": 7, "ldr": 0, "weapon": "StG 44", "ws": 6,
		"skills": ["Dodge", "Tough", "Deadly"]},
	"SS NCO": {"tq": 7, "ldr": 1, "weapon": "StG 44", "ws": 6,
		"skills": ["Dodge", "Eagle Eyes"]},
	"SS Officer": {"tq": 8, "ldr": 2, "weapon": "MP40", "ws": 7,
		"skills": ["Dodge", "Sniper"]},
	# Friendly
	"Leader": {"tq": 6, "ldr": 3, "weapon": "M3 Grease Gun", "ws": 7},
	"Leader2": {"tq": 6, "ldr": 2, "weapon": "M1 Thompson", "ws": 6},
	"US Rifleman": {"tq": 5, "ldr": 0, "weapon": "M1 Garand", "ws": 5},
	"BAR Gunner": {"tq": 5, "ldr": 0, "weapon": "BAR", "ws": 5},
	"MG Gunner": {"tq": 5, "ldr": 0, "weapon": "M1919", "ws": 5},
	"MG Assistant": {"tq": 5, "ldr": 0, "weapon": "M1 Garand", "ws": 5},
	# Medico addestrato (Rule 30): disarmato, +2 TQ alle cure. Vale per
	# entrambi i lati (lo schiera lo scenario).
	"Medic": {"tq": 5, "ldr": 0, "weapon": "", "ws": 0, "medic": true},
	# Pedina-esca: valori minimi, non combatte mai.
	"Dummy": {"tq": 1, "ldr": 0, "weapon": "", "ws": 0},
	# Rule 31-32: porta il bazooka (M9); stat. come rifleman ma arma AT.
	"Bazooka Man": {"tq": 5, "ldr": 0, "weapon": "Bazooka M9", "ws": 5},
	# Fanteria controcarri tedesca (Panzerfaust 60); stat. come Rifleman.
	"AT Grenadier": {"tq": 5, "ldr": 0, "weapon": "Panzerfaust 60", "ws": 5},
}

# Zona di schieramento per la fase di deploy. Ritorna gli hex validi.
# Specifica: {"cols":[a,b], "rows":[c,d]} (rettangolo) oppure
# {"triangle":["c,r","c,r","c,r"]} (triangolo sui centri hex).
static func deploy_hexes(state: GameState, scenario_id: String) -> Array[Vector2i]:
	var sc: Dictionary = SCENARIOS[scenario_id]
	var out: Array[Vector2i] = []
	if not sc.has("deploy"):
		return out
	var spec: Dictionary = sc["deploy"]
	if spec.has("triangle"):
		var pts: Array[Vector2] = []
		for s in spec["triangle"]:
			var p: PackedStringArray = String(s).split(",")
			pts.append(_hexf(int(p[0]), int(p[1])))
		for key in state.map:
			var q: PackedStringArray = String(key).split(",")
			var col := int(q[0])
			var row := int(q[1])
			if Geometry2D.is_point_in_polygon(_hexf(col, row), PackedVector2Array(pts)):
				out.append(Vector2i(col, row))
	else:
		for col in range(int(spec["cols"][0]), int(spec["cols"][1]) + 1):
			for row in range(int(spec["rows"][0]), int(spec["rows"][1]) + 1):
				if state.map.has(GameState.hex_key(col, row)):
					out.append(Vector2i(col, row))
	return out


# Posizione "continua" di un hex per i test geometrici (colonne pari giu').
static func _hexf(col: int, row: int) -> Vector2:
	return Vector2(col, row + (0.5 if col % 2 == 0 else 0.0))


# Nome ordine -> enum, per le tabelle testuali degli scenari.
const ORDER_BY_NAME := {
	"EVADE": D.Order.EVADE, "SNEAK": D.Order.SNEAK, "HIDE": D.Order.HIDE,
	"RUN_AND_GUN": D.Order.RUN_AND_GUN, "SPRINT": D.Order.SPRINT,
}

# Roster completi dei 4 team tedeschi (pedine del modulo Vassal),
# ufficiali e graduati in testa. make_cup abbina pedina e grado al ruolo
# e ricava il nome del personaggio dalla pedina stessa.
const TEAM_COUNTERS := {
	"Blue": [
		"GE-BlueTeam-Lt-Brandt", "GE-BlueTeam-Obfr-Gottschied",
		"GE-BlueTeam-Obfr-Sauer", "GE-BlueTeam-Obfr-Simon",
		"GE-BlueTeam-Soldat-Abbas", "GE-BlueTeam-Soldat-Abend",
		"GE-BlueTeam-Soldat-Arnold", "GE-BlueTeam-Soldat-Bach",
		"GE-BlueTeam-Soldat-Bahlow", "GE-BlueTeam-Soldat-Hahn",
		"GE-BlueTeam-Soldat-Horn", "GE-BlueTeam-Soldat-Pfeiffer",
		"GE-BlueTeam-Soldat-Pohl", "GE-BlueTeam-Soldat-Scholz",
		"GE-BlueTeam-Soldat-Schreiber", "GE-BlueTeam-Soldat-Schulte",
		"GE-BlueTeam-Soldat-Seidel", "GE-BlueTeam-Soldat-Sommer",
		"GE-BlueTeam-Soldat-Voight", "GE-BlueTeam-Soldat-Wolf",
		"GE-BlueTeam-Soldat-Ziegler",
	],
	"Red": [
		"GE-RedTeam-Lt-Martin", "GE-RedTeam-Obfr-Franke",
		"GE-RedTeam-Obfr-Gunther", "GE-RedTeam-Soldat-Berger",
		"GE-RedTeam-Soldat-Engel", "GE-RedTeam-Soldat-Friedrich",
		"GE-RedTeam-Soldat-Graf", "GE-RedTeam-Soldat-Haas",
		"GE-RedTeam-Soldat-Hahn", "GE-RedTeam-Soldat-Jager",
		"GE-RedTeam-Soldat-Jung", "GE-RedTeam-Soldat-Keller",
		"GE-RedTeam-Soldat-Kraus", "GE-RedTeam-Soldat-Lorenz",
		"GE-RedTeam-Soldat-Moller", "GE-RedTeam-Soldat-Otto",
		"GE-RedTeam-Soldat-Roth", "GE-RedTeam-Soldat-Schubert",
		"GE-RedTeam-Soldat-Vogel", "GE-RedTeam-Soldat-Winkler",
		"GE-RedTeam-Soldat-Winter",
	],
	"Yellow": [
		"GE-YellowTeam-Hptm-Weber", "GE-YellowTeam-Obfr-Klein",
		"GE-YellowTeam-Obfr-Wagner", "GE-YellowTeam-Obfr-Werner",
		"GE-YellowTeam-Soldat-Bauer", "GE-YellowTeam-Soldat-Becker",
		"GE-YellowTeam-Soldat-Braun", "GE-YellowTeam-Soldat-Fischer",
		"GE-YellowTeam-Soldat-Hoffmann", "GE-YellowTeam-Soldat-Koch",
		"GE-YellowTeam-Soldat-Meyer", "GE-YellowTeam-Soldat-Muller",
		"GE-YellowTeam-Soldat-Neumann", "GE-YellowTeam-Soldat-Richter",
		"GE-YellowTeam-Soldat-Schafer", "GE-YellowTeam-Soldat-Scheider",
		"GE-YellowTeam-Soldat-Schmidt", "GE-YellowTeam-Soldat-Schroder",
		"GE-YellowTeam-Soldat-Schulz", "GE-YellowTeam-Soldat-Schwarz",
		"GE-YellowTeam-Soldat-Wolf",
	],
	"White": [
		"GE-WhiteTeam-Hptm-Wess", "GE-WhiteTeam-Obfr-Hermann",
		"GE-WhiteTeam-Obfr-Kohler", "GE-WhiteTeam-Obfr-Thomas",
		"GE-WhiteTeam-Soldat-Becker", "GE-WhiteTeam-Soldat-Frank",
		"GE-WhiteTeam-Soldat-Fuchs", "GE-WhiteTeam-Soldat-Hoffman",
		"GE-WhiteTeam-Soldat-Huber", "GE-WhiteTeam-Soldat-Kaiser",
		"GE-WhiteTeam-Soldat-Konig", "GE-WhiteTeam-Soldat-Krause",
		"GE-WhiteTeam-Soldat-Kruger", "GE-WhiteTeam-Soldat-Lang",
		"GE-WhiteTeam-Soldat-Lange", "GE-WhiteTeam-Soldat-Meier",
		"GE-WhiteTeam-Soldat-Schmid", "GE-WhiteTeam-Soldat-Schmitz",
		"GE-WhiteTeam-Soldat-Stein-", "GE-WhiteTeam-Soldat-Walter",
		"GE-WhiteTeam-Soldat-Zimmer",
	],
	# Vol. 2: reparti SS (OBSTM = Obersturmführer, OBSH = Oberscharführer,
	# SCH = Scharführer). Rule 24 skills assegnate via ROLE "SS *".
	"Teal": [
		"GE-TealTeam-OBSTM-Brandt",
		"GE-TealTeam-OBSH-Engel", "GE-TealTeam-OBSH-Sauer",
		"GE-TealTeam-OBSH-Seidel", "GE-TealTeam-OBSH-Simon",
		"GE-TealTeam-OBSH-Weber",
		"GE-TealTeam-SCH-Arnold", "GE-TealTeam-SCH-Bahlow",
		"GE-TealTeam-SCH-Haas", "GE-TealTeam-SCH-Horn",
		"GE-TealTeam-SCH-Muller", "GE-TealTeam-SCH-Pfeiffer",
		"GE-TealTeam-SCH-Pohl", "GE-TealTeam-SCH-Schmidt",
		"GE-TealTeam-SCH-Scholz", "GE-TealTeam-SCH-Schreiber",
		"GE-TealTeam-SCH-Schulte", "GE-TealTeam-SCH-Sommer",
		"GE-TealTeam-SCH-Voight", "GE-TealTeam-SCH-Wolff",
		"GE-TealTeam-SCH-Ziegler",
	],
	"Purple": [
		"GE-PurpleTeam-OBSTM-Geiger",
		"GE-PurpleTeam-OBSH-Bender", "GE-PurpleTeam-OBSH-Michel",
		"GE-PurpleTeam-OBSH-Pohl", "GE-PurpleTeam-OBSH-Sauer",
		"GE-PurpleTeam-OBSH-Schindler", "GE-PurpleTeam-OBSH-Wurst",
		"GE-PurpleTeam-SCH-Blum", "GE-PurpleTeam-SCH-Bock",
		"GE-PurpleTeam-SCH-Breuer", "GE-PurpleTeam-SCH-Frey",
		"GE-PurpleTeam-SCH-Jahn", "GE-PurpleTeam-SCH-Kruse",
		"GE-PurpleTeam-SCH-Nowak", "GE-PurpleTeam-SCH-Reuter",
		"GE-PurpleTeam-SCH-Scherer", "GE-PurpleTeam-SCH-Stark",
		"GE-PurpleTeam-SCH-Thiel", "GE-PurpleTeam-SCH-Thiele",
		"GE-PurpleTeam-SCH-Voss", "GE-PurpleTeam-SCH-Witt",
	],
}
const GERMAN_NAMES := ["Becker", "Fuchs", "Hoffmann", "Kaiser", "Krause",
	"Lange", "Maier", "Neumann", "Richter", "Schafer", "Schmidt", "Vogt",
	"Weber", "Werner", "Winkler", "Zimmermann", "Brandt", "Dietrich"]

# La squadra completa (3 Able + 3 Baker + 6 Charlie) degli scenari 1-9.
const FULL_SQUAD := [
	{"name": "Sgt Taylor", "role": "Leader", "team": "Able", "counter": "US-Able-Sgt-Taylor"},
	{"name": "Pvt Brubaker", "role": "US Rifleman", "team": "Able", "counter": "US-Able-Pvt-Brubaker"},
	{"name": "Pvt Cragg", "role": "US Rifleman", "team": "Able", "counter": "US-Able-Pvt-Cragg"},
	{"name": "Pvt Johnson", "role": "US Rifleman", "team": "Baker", "counter": "US-Baker-Pvt-Johnson"},
	{"name": "Pvt Miller", "role": "BAR Gunner", "team": "Baker", "counter": "US-Baker-Pvt-Miller"},
	{"name": "Pvt Peters", "role": "US Rifleman", "team": "Baker", "counter": "US-Baker-Pvt-Peters"},
	{"name": "Cpl Thomas", "role": "Leader", "team": "Charlie", "counter": "US-Charlie-Pvt-Thomas"},
	{"name": "Pvt Butterman", "role": "US Rifleman", "team": "Charlie", "counter": "US-Charlie-Pvt-Butterman"},
	{"name": "Pvt Connor", "role": "US Rifleman", "team": "Charlie", "counter": "US-Charlie-Pvt-Connor"},
	{"name": "Pvt Douglas", "role": "US Rifleman", "team": "Charlie", "counter": "US-Charlie-Pvt-Douglas"},
	{"name": "Pvt Kowalski", "role": "US Rifleman", "team": "Charlie", "counter": "US-Charlie-Pvt-Kowalski"},
	{"name": "Pvt Stubbs", "role": "BAR Gunner", "team": "Charlie", "counter": "US-Charlie-Pvt-Stubbs"},
]

# Squadra Vol. 2: nuovi personaggi (SSGT Perez + 11 soldati, mappe 5-10).
const FULL_SQUAD_VOL2 := [
	{"name": "SSgt Perez", "role": "Leader", "team": "Able",
		"counter": "US-Able-SSGT-Perez"},
	{"name": "Pvt Butler", "role": "BAR Gunner", "team": "Able",
		"counter": "US-Able-Pvt-Butler"},
	{"name": "Pvt Hatcher", "role": "US Rifleman", "team": "Able",
		"counter": "US-Able-Pvt-Hatcher", "weapon": "M1 Thompson", "ws": 5},
	{"name": "PVT Peterson", "role": "US Rifleman", "team": "Able",
		"counter": "US-Able-PVT-Peterson"},
	{"name": "Pvt James", "role": "US Rifleman", "team": "Baker",
		"counter": "US-Baker-Pvt-James"},
	{"name": "Pvt Moore", "role": "BAR Gunner", "team": "Baker",
		"counter": "US-Baker-Pvt-Moore"},
	{"name": "Pvt Lewist", "role": "US Rifleman", "team": "Baker",
		"counter": "US-Baker-Pvt-Lewist"},
	{"name": "Pvt Cruz", "role": "Bazooka Man", "team": "Baker",
		"counter": "US-Baker-Pvt-Cruz"},
	{"name": "Cpl Diaz", "role": "Leader2", "team": "Charlie",
		"counter": "US-Charlie-Cpl-Diaz"},
	{"name": "Pvt Bennett", "role": "US Rifleman", "team": "Charlie",
		"counter": "US-Charlie-Pvt-Bennett"},
	{"name": "Pvt Hall", "role": "US Rifleman", "team": "Charlie",
		"counter": "US-Charlie-Pvt-Hall"},
	{"name": "Pvt Holland", "role": "US Rifleman", "team": "Charlie",
		"counter": "US-Charlie-Pvt-Holland", "weapon": "M1903 Springfield", "ws": 5},
	{"name": "Pvt Williams", "role": "MG Gunner", "team": "Charlie",
		"counter": "US-Charlie-Pvt-Williams", "mg_role": "operator",
		"mg_companion": "Pvt Bennett"},
]


# Genera la coppa nemica da una specifica per team: {"Blue": {"Recruit": 4,
# "NCO": 1, ...}, "Red": {...}}. Ogni ruolo pesca una pedina del grado
# giusto (Officer -> Lt/Hptm, NCO/Veteran -> Obfr, truppa -> Soldat) e il
# NOME del personaggio viene dalla pedina, cosi' segnalino e nome
# coincidono sempre.
static func make_cup(spec: Dictionary) -> Array:
	var cup: Array = []
	var name_i := 0
	for team in spec:
		# pool divisi per grado
		var officers: Array = []
		var ncos: Array = []
		var troops: Array = []
		for id in TEAM_COUNTERS.get(team, []):
			if "-Lt-" in id or "-Hptm-" in id or "-OBSTM-" in id:
				officers.append(id)
			elif "-Obfr-" in id or "-OBSH-" in id:
				ncos.append(id)
			else:
				troops.append(id)
		for role in spec[team]:
			for i in range(int(spec[team][role])):
				var pool: Array
				match role:
					"Officer", "SS Officer":
						pool = officers if not officers.is_empty() else ncos
					"NCO", "Veteran", "SS NCO", "SS Veteran":
						pool = ncos if not ncos.is_empty() else troops
					_:
						pool = troops
				var entry := {"role": role, "team": team}
				if not pool.is_empty():
					var id: String = pool.pop_front()
					entry["counter"] = id
					entry["name"] = _name_from_counter(id)
				else:
					# pool esaurito: nome generico, pedina di ripiego
					var rank := "Obfr" if role in ["NCO", "Veteran"] else \
						("Lt" if role == "Officer" else "Soldat")
					entry["name"] = "%s %s" % [rank,
						GERMAN_NAMES[name_i % GERMAN_NAMES.size()]]
					name_i += 1
				cup.append(entry)
	return cup


# "GE-BlueTeam-Lt-Brandt" -> "Lt Brandt"
static func _name_from_counter(id: String) -> String:
	var parts := id.split("-")
	# [GE, XxxTeam, Grado, Nome(, ...)] - il nome puo' contenere trattini
	var rank := parts[2]
	var name := "-".join(parts.slice(3)).trim_suffix("-")
	return "%s %s" % [rank, name]

const SCENARIOS := {
	"intro1": {
		"name": "A Meeting of Patrols",
		"map": "hedgerows",
		"turns": 7,
		"hand_limit": 3,
		"compass": ["19,2", "18,1"],
		"deploy": {"triangle": ["18,14", "18,19", "28,19"]},
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
		# Punti di ricognizione da raggiungere (+4 VP l'uno).
		"objective_hexes": ["20,6", "27,3", "29,14", "33,5"],
		"vp": {"enemy_killed": 1, "friendly_killed": -3, "friendly_wounded": -1,
			"objective_each": 4},
	},

	"intro2": {
		"name": "Rendezvous",
		"map": "village",
		"turns": 5,
		"hand_limit": 2,
		"compass": ["11,2", "11,1"],
		"deploy": {"cols": [11, 11], "rows": [1, 12]},
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
			{"name": "Soldat Wolf", "role": "Sniper", "team": "Blue", "counter": "GE-BlueTeam-Soldat-Wolf"},
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
		"compass": ["11,11", "11,10"],
		"deploy": {"cols": [11, 11], "rows": [12, 19]},
		"desc": "Un pezzo d'artiglieria martella il C.P. della compagnia.\nCharlie Team avanza con le cariche C4.",
		"friendly_morale": 2,  # Bold
		"friendly": [
			{"name": "Cpl Thomas", "role": "Leader", "team": "Charlie", "pos": "11,13", "counter": "US-Charlie-Pvt-Thomas"},
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
		"gun_hexes": ["20,15"],
		"c4": true,
		"vp": {"enemy_killed": 1, "friendly_killed": -2, "friendly_wounded": -1,
			"guns_required": true},
	},

	"intro4": {
		"name": "Here They Come!",
		"map": "hill",
		"turns": 7,
		"hand_limit": 3,
		"compass": ["11,2", "11,3"],
		"deploy": {"cols": [19, 23], "rows": [2, 10]},
		"desc": "Notte. Charlie Team e' di vedetta quando un ramo si spezza.\nUn grido: \"Eccoli, arrivano!\"",
		"night": true,
		"friendly": [
			{"name": "Cpl Thomas", "role": "Leader", "team": "Charlie", "pos": "21,5", "counter": "US-Charlie-Pvt-Thomas"},
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

	# ------------------------------------------------ scenari principali

	"s1": {
		"name": "1. Attack the Farmhouse",
		"map": "farmhouse", "turns": 12, "hand_limit": 3, "event_table": "attacking",
		"compass": ["2,3", "2,2"],
		"deploy": {"cols": [1, 4], "rows": [0, 19]},
		"desc": "Forze nemiche presidiano la fattoria.\nTocca alla tua squadra ripulirla.",
		"squad_full": true,
		"cup_spec": {
			"Blue": {"Recruit": 4, "Rifleman": 4, "NCO": 1},
			"Red": {"Veteran": 1, "Sniper": 1, "Recruit": 5},
			"Yellow": {"Officer": 1, "Rifleman": 5, "Elite": 1},
			"White": {"Recruit": 5, "Rifleman": 5, "NCO": 2},
		},
		"dummies": 20,
		"enemy_setup": ["16,2", "22,4", "22,5", "24,5", "14,10", "15,11",
			"19,11", "12,13", "13,18", "20,16", "22,19", "27,9", "28,8",
			"27,14", "29,19", "31,16", "31,17", "32,16", "27,4", "28,5",
			"29,5", "17,10", "25,19", "16,15", "22,1", "28,7"],
		# SR8: nemici nei 3 edifici chiave -> Aimed Fire finche' Normal.
		"building_tqc_aimed": true,
		"vp": {"enemy_killed": 1, "enemy_nco_killed": 2, "enemy_officer_killed": 3,
			"friendly_killed": -2, "friendly_wounded": -1,
			"no_enemy_in_building": 5},
	},

	"s2": {
		"name": "2. Defend the Farmhouse",
		"map": "farmhouse", "turns": 12, "hand_limit": 2, "event_table": "defending",
		"deploy": {"cols": [18, 30], "rows": [0, 19]},
		"desc": "Prenderla e' stato facile, tenerla no:\nil nemico torna a riprendersi la 'sua' fattoria.",
		"squad_full": true,
		"enemy_morale": 1,  # Aggressive
		# SR9: bombardamento iniziale (105mm, 6 colpi).
		"opening_barrage": {
			"type": "ARTILLERY_105",
			"rolls": 6,
			"scatter": true,
			"hex_table": [
				"20,7", "27,11", "20,14", "27,18", "30,12",
				"28,7", "19,14", "24,13", "23,6", "12,10",
			],
		},
		"cup_spec": {
			"Blue": {"Recruit": 2, "Rifleman": 5, "NCO": 1, "Officer": 1},
			"Red": {"Veteran": 2, "Rifleman": 5, "Recruit": 1},
			"Yellow": {"Officer": 1, "Rifleman": 5, "NCO": 2, "Elite": 1},
			"White": {"Recruit": 3, "Rifleman": 5, "NCO": 2, "Officer": 1},
		},
		"dummies": 20,
		"enemy_setup": ["3,2", "3,3", "3,5", "3,12", "3,13", "3,14", "3,15",
			"3,17", "4,1", "4,2", "4,3", "4,4", "4,5", "4,10", "4,11",
			"4,12", "4,13", "4,14", "4,15", "4,17"],
		# SR libro: al turno 5 nuovi nemici ai medesimi hex d'entrata.
		"waves": [
			{"turn": 5, "hexes": ["3,2", "3,3", "3,5", "3,12", "3,13", "3,14", "3,15",
				"3,17", "4,1", "4,2", "4,3", "4,4", "4,5", "4,10", "4,11",
				"4,12", "4,13", "4,14", "4,15", "4,17"]},
		],
		"vp": {"enemy_killed": 1, "enemy_nco_killed": 2, "enemy_officer_killed": 3,
			"friendly_killed": -2, "friendly_wounded": -1,
			"no_enemy_in_building": 8},
	},

	"s3": {
		"name": "3. Let's Get Out of Here!",
		"map": "farmhouse", "turns": 12, "hand_limit": 3, "event_table": "s3",
		"deploy": {"cols": [18, 26], "rows": [0, 19]},
		"desc": "Prigioniero catturato, Taylor ferito grave,\ne il nemico lancia l'attacco. Si torna a casa.",
		"squad_full": true,
		"taylor_bad_wound": true,
		"enemy_morale": 1,  # Aggressive
		"cup_spec": {
			"Blue": {"Recruit": 5, "Rifleman": 5, "NCO": 2, "Officer": 1},
			"Red": {"Recruit": 4, "Rifleman": 5, "Veteran": 2, "Officer": 1},
			"Yellow": {"Recruit": 5, "Rifleman": 5, "NCO": 2},
			"White": {"Recruit": 5, "Rifleman": 5, "Officer": 1},
		},
		"dummies": 20,
		# Hex corretti dal libro (aggiunto 24.19 mancante al gruppo 2).
		"enemy_setup": ["33,4", "33,5", "33,6", "33,7", "33,8", "33,9",
			"35,5", "35,6", "35,7", "35,8", "35,9", "35,10", "33,10",
			"18,19", "19,19", "20,19", "21,19", "22,19", "23,19", "24,19"],
		"first_order_d6": ["EVADE 5/6", "EVADE 6/5", "SPRINT 6",
			"SPRINT 5", "SNEAK 5", "SNEAK 6"],
		# SR libro: rinforzi al turno 3 dal bordo est.
		"waves": [
			{"turn": 3, "hexes": ["35,5", "35,6", "35,7", "35,8", "35,9", "35,10"]},
		],
		# Fuga: VP per ogni uomo che esce dal bordo sinistro (col <= 2).
		"exit_col": 2,
		"vp": {"enemy_killed": 1, "friendly_killed": -3, "friendly_wounded": -1,
			"friendly_exited": 3},
	},

	"s4": {
		"name": "4. Sniper Village",
		"map": "village", "turns": 14, "hand_limit": 3, "event_table": "attacking",
		"deploy": {"cols": [1, 4], "rows": [0, 19]},
		"desc": "Il paese sembra vuoto, ma il QG teme i cecchini.\nE il nemico ha scelto proprio ora per pattugliare.",
		"squad_full": true,
		# Coppa iniziale: solo i tipi iniziali (reclute/cecchini).
		# Al turno 4 il libro aggiunge reparti completi alla pool: li
		# pre-carichiamo qui cosi' la wave del turno 4 li pesca dalla riserva.
		"cup_spec": {
			"Blue": {"Recruit": 3, "Sniper": 1, "Rifleman": 5, "NCO": 1, "Officer": 1},
			"Red": {"Sniper": 1, "Recruit": 5, "Veteran": 2, "Rifleman": 5},
			"Yellow": {"Sniper": 1, "Officer": 1, "Rifleman": 5, "NCO": 2, "Elite": 1},
			"White": {"Recruit": 4, "Sniper": 1, "Rifleman": 5, "NCO": 2, "Officer": 1},
		},
		"dummies": 24,
		"enemy_setup": ["14,7", "16,11", "16,17", "17,4", "19,5", "20,3",
			"21,3", "21,15", "21,18", "23,6", "24,6", "24,7", "25,9",
			"25,11", "25,13", "25,19", "27,8", "28,4", "28,10", "29,7", "29,17"],
		# SR11 (libro): al turno 4 i reparti completi entrano dai bordi est.
		"waves": [
			{"turn": 4, "hexes": ["35,3", "35,4", "35,5", "35,6", "35,7",
				"35,15", "35,16", "35,17", "35,18", "35,19"]},
		],
		"building_tqc_aimed": true,
		"vp": {"enemy_killed": 2, "friendly_killed": -2, "friendly_wounded": -1,
			"no_enemy_in_building": 5},
	},

	"s5": {
		"name": "5. Village Defense",
		"map": "village", "turns": 12, "hand_limit": 3, "event_table": "defending",
		"large_battle": true,
		"deploy": {"cols": [14, 30], "rows": [0, 19]},
		"desc": "Vengono dritti su di noi: o teniamo il paese\no il plotone a sud resta tagliato fuori.",
		"squad_full": true,
		"enemy_morale": 1,  # Aggressive
		"cup_spec": {
			"Blue": {"Recruit": 2, "Rifleman": 5, "NCO": 1, "Officer": 1},
			"Red": {"Veteran": 2, "Rifleman": 5, "Recruit": 1},
			"Yellow": {"Officer": 1, "Rifleman": 5, "NCO": 2, "Elite": 1},
			"White": {"Recruit": 3, "Rifleman": 5, "NCO": 2, "Officer": 1},
		},
		"dummies": 20,
		# SR10: bombardamento iniziale (105mm, 6 colpi) prima dell'inizio.
		"opening_barrage": {
			"type": "ARTILLERY_105",
			"rolls": 6,
			"scatter": true,
			"hex_table": [
				"20,7", "27,11", "20,14", "27,18", "30,12",
				"28,7", "19,14", "24,13", "23,6", "12,10",
			],
		},
		# Hex corretti dal libro (04.11 non 04.10; 04.16/04.18 non 04.15/04.17).
		"enemy_setup": ["3,2", "3,3", "3,5", "3,12", "3,13", "3,14", "3,15",
			"3,17", "4,1", "4,2", "4,3", "4,4", "4,5", "4,11",
			"4,12", "4,13", "4,14", "4,15", "4,16", "4,18"],
		# SR13 (libro): al turno 5 altri nemici dalla riserva agli stessi hex.
		"waves": [
			{"turn": 5, "hexes": ["3,2", "3,3", "3,5", "3,12", "3,13", "3,14",
				"3,15", "3,17", "4,2", "4,3", "4,4", "4,5", "4,6", "4,11",
				"4,12", "4,13", "4,14", "4,15", "4,16", "4,18"]},
		],
		"vp": {"enemy_killed": 1, "enemy_nco_killed": 2, "enemy_officer_killed": 3,
			"friendly_killed": -2, "friendly_wounded": -1,
			"no_enemy_in_building": 8},
	},

	"s6": {
		"name": "6. Scout the Hill",
		"map": "hill", "turns": 15, "hand_limit": 3, "event_table": "s6",
		# SR8 libro: "within 4 hexes of the left hand board edge" = colonne 1-4.
		"deploy": {"cols": [1, 4], "rows": [0, 19]},
		"desc": "Pattuglia notturna: ricognizione sui 4 punti\nsegnati in mappa. E riportate un prigioniero vivo.",
		"night": true,
		"squad_full": true,
		"cup_spec": {
			"Blue": {"Veteran": 3, "NCO": 1, "Officer": 1, "LMG": 1},
			"Red": {"Officer": 1, "Rifleman": 4, "LMG": 1},
			"Yellow": {"Officer": 1, "Recruit": 5, "Sniper": 1},
			"White": {"Officer": 1, "Recruit": 5, "Sniper": 1},
		},
		"dummies": 24,
		# 14 hex dal libro (aggiunto 29.08 mancante).
		"enemy_setup": ["17,5", "18,6", "18,10", "18,15", "20,5", "22,4",
			"22,10", "22,15", "23,14", "24,13", "25,17", "26,6", "27,9", "29,8"],
		# I 4 punti da ricognire (+VP quando un friendly ci arriva accanto).
		# APPROSSIMATI: il libro li segna sulla mappa, non in chiaro.
		"objective_hexes": ["20,5", "18,10", "23,14", "26,6"],
		"vp": {"enemy_killed": 1, "friendly_killed": -2, "friendly_wounded": -1,
			"objective_each": 4},
	},

	"s7": {
		"name": "7. Hold the Hill",
		"map": "hill", "turns": 15, "hand_limit": 3, "event_table": "defending",
		"deploy": {"cols": [20, 30], "rows": [0, 19]},
		"desc": "La collina va tenuta a ogni costo.\nLoro arriveranno a ondate. Noi terremo.",
		"squad_full": true,
		"enemy_morale": 1,  # Aggressive
		"cup_spec": {
			"Blue": {"Veteran": 3, "Rifleman": 4, "NCO": 1, "Officer": 1},
			"Red": {"Officer": 1, "Rifleman": 4, "Recruit": 5},
			"Yellow": {"Officer": 1, "Recruit": 5, "Rifleman": 4},
			"White": {"Officer": 1, "Recruit": 5, "Rifleman": 4},
		},
		"dummies": 12,
		"enemy_setup": ["10,7", "10,9", "10,10", "10,11", "10,13", "9,8",
			"9,11", "9,12", "9,15", "9,17", "8,6", "8,9", "8,12", "8,15", "8,16"],
		# SR14 libro: rinforzi ai turni 3 e 5 (non 5 e 9) negli stessi hex
		# del setup (colonne 8-9, lato sinistro della collina).
		"waves": [
			{"turn": 3, "hexes": ["9,8", "9,11", "9,12", "9,15", "9,17",
				"8,6", "8,9", "8,12", "8,15", "8,16"]},
			{"turn": 5, "hexes": ["9,8", "9,11", "9,12", "9,15", "9,17",
				"8,6", "8,9", "8,12", "8,15", "8,16"]},
		],
		"vp": {"enemy_killed": 1, "enemy_nco_killed": 2, "enemy_officer_killed": 3,
			"friendly_killed": -2, "friendly_wounded": -1},
	},

	"s8": {
		"name": "8. Rescue Mission",
		"map": "hedgerows", "turns": 12, "hand_limit": 3, "event_table": "attacking",
		"compass": ["2,3", "2,2"],
		"deploy": {"cols": [1, 3], "rows": [0, 19]},
		"desc": "Un partigiano con documenti vitali e' nascosto in\nun casolare oltre le linee. Riportatelo a casa.",
		"squad_full": true,
		"cup_spec": {
			"Blue": {"Veteran": 3, "Rifleman": 4, "NCO": 1, "Officer": 1},
			"Red": {"Officer": 1, "Rifleman": 4, "Recruit": 5},
			"Yellow": {"Officer": 1, "Recruit": 5, "Rifleman": 4},
			"White": {"Officer": 1, "Recruit": 5, "Rifleman": 4},
		},
		"dummies": 12,
		# Hex corretti dal libro (17.14 era maquis, ma e' posizione nemica;
		# il maquis "Alex" e' a 29.14 oltre le linee).
		"enemy_setup": ["18,4", "21,9", "17,10", "17,14", "19,7", "17,17", "15,16",
			"16,13", "12,16", "16,18"],
		# Alex e' nel casolare in 29.14: va scortato fuori dal bordo sinistro.
		"maquis_hex": "29,14",
		"exit_col": 2,
		# SR libro: rinforzi al turno 3 (col 35) e turni 5 e 7 (col 34).
		"waves": [
			{"turn": 3, "hexes": ["35,6", "35,7", "35,8", "35,9", "35,10", "35,11"]},
			{"turn": 5, "hexes": ["34,6", "34,7", "34,8", "34,9", "34,10", "34,11"]},
			{"turn": 7, "hexes": ["34,6", "34,7", "34,8", "34,9", "34,10", "34,11"]},
		],
		"vp": {"enemy_killed": 1, "friendly_killed": -2, "friendly_wounded": -1,
			"maquis_rescued": 10, "friendly_exited": 1},
	},

	"s9": {
		"name": "9. Destroy Those Guns!",
		"map": "hedgerows", "turns": 12, "hand_limit": 4, "event_table": "attacking",
		"compass": ["2,3", "2,2"],
		"deploy": {"cols": [1, 3], "rows": [0, 19]},
		"desc": "L'artiglieria nemica martella le nostre posizioni\ndai campi. Entrate e fate saltare i pezzi.",
		"squad_full": true,
		"cup_spec": {
			"Blue": {"Veteran": 3, "Rifleman": 4, "NCO": 1, "Officer": 1},
			"Red": {"Officer": 1, "Rifleman": 4, "Recruit": 5},
			"Yellow": {"Officer": 1, "Recruit": 5, "Rifleman": 4},
			"White": {"Officer": 1, "Recruit": 5, "Rifleman": 4},
		},
		"dummies": 12,
		# Hex corretti dal libro (aggiunto 19.15 e 19.18 mancanti).
		"enemy_setup": ["16,16", "17,11", "18,18", "19,5", "19,10", "19,15",
			"19,18", "23,7", "24,4", "24,10", "28,11", "29,13"],
		# 4 cannoni (aggiunto 23.08 mancante).
		"gun_hexes": ["19,11", "20,19", "21,3", "23,8"],
		"c4": true,
		# SR15/16/17 libro: rinforzi ai turni 3, 5 e 7 dal bordo est (col 35).
		"waves": [
			{"turn": 3, "hexes": ["35,6", "35,7", "35,8", "35,9", "35,10", "35,11"]},
			{"turn": 5, "hexes": ["35,6", "35,7", "35,8", "35,9", "35,10", "35,11"]},
			{"turn": 7, "hexes": ["35,6", "35,7", "35,8", "35,9", "35,10", "35,11"]},
		],
		"vp": {"enemy_killed": 1, "friendly_killed": -2, "friendly_wounded": -1,
			"guns_required": true},
	},

	"s10": {
		"name": "10. Hold until Relieved!",
		"map": "farmhouse", "turns": 15, "hand_limit": 3, "event_table": "s10",
		"compass": ["2,3", "2,4"],
		# Libro: "within 3 hexes of a building hex" (centro fattoria).
		"deploy": {"cols": [11, 25], "rows": [0, 19]},
		"desc": "Circondati e tagliati fuori, il nemico preme da est e da ovest.\nTenete la fattoria finche' i rinforzi arrivano.",
		"squad_full": true,
		"enemy_morale": 2,  # Bold (+1 to TQ, libro SR3)
		# SR9: bombardamento iniziale 105mm, 6 colpi (stessa mappa farmhouse).
		"opening_barrage": {
			"type": "ARTILLERY_105",
			"rolls": 6,
			"scatter": true,
			"hex_table": [
				"20,7", "27,11", "20,14", "27,18", "30,12",
				"28,7", "31,4", "24,13", "23,6", "26,4",
			],
		},
		# Il libro usa 4 team su DUE mappe (Farmhouse + Hedgerows).
		# Semplificazione: un'unica mappa (farmhouse), nemici da sinistra
		# (Blue/Red, lato libro) e da destra (Yellow/White, lato hedgerows).
		"cup_spec": {
			"Blue": {"Officer": 1, "NCO": 2, "Veteran": 3, "Rifleman": 5, "Recruit": 5},
			"Red": {"Officer": 1, "NCO": 2, "Rifleman": 5, "Recruit": 5},
			"Yellow": {"Officer": 1, "NCO": 2, "Veteran": 3, "Rifleman": 5, "Recruit": 5},
			"White": {"Officer": 1, "NCO": 2, "Rifleman": 5, "Recruit": 5},
		},
		"dummies": 20,
		# Hex libro (Farmhouse Cup A) + simmetria sul lato destro per Cup B.
		"enemy_setup": [
			"3,6", "4,2", "4,3", "4,4", "4,5", "4,12", "4,13", "4,14", "4,15",
			"7,12", "7,13", "7,14", "7,15", "7,16",
			"31,5", "31,9", "31,13", "32,7", "32,11", "33,9",
		],
		# SR12/13 libro: al turno 5 rinforzi da entrambi i lati.
		"waves": [
			{"turn": 5, "hexes": ["7,12", "7,13", "7,14", "7,15", "7,16",
				"31,7", "31,11", "32,6", "32,10", "33,8"]},
			{"turn": 9, "hexes": ["4,2", "4,3", "4,12", "4,13",
				"31,6", "31,10", "32,8"]},
		],
		"building_tqc_aimed": true,
		"vp": {"enemy_killed": 1, "enemy_nco_killed": 2, "enemy_officer_killed": 3,
			"friendly_killed": -2, "friendly_wounded": -1,
			"no_enemy_in_building": 5},
	},

	# ------------------------------------------------ Vol. 2 — Mappe 5-10

	"s11": {
		"name": "11. Payback Time",
		"map": "woods", "turns": 14, "hand_limit": 3,
		"compass": ["34,5", "33,5"],
		"deploy": {"cols": [31, 35], "rows": [0, 19]},
		"desc": "I tedeschi si sono ritirati nel bosco pensando di essere al\nsicuro. Dimostriamo loro che si sbagliano.",
		"squad_vol2": true,
		# Sherman di supporto per la "vendetta" (scelta di design).
		"vehicles": [
			{"type": "M4A3 Sherman", "side": "friendly", "team": "Able",
				"pos": "32,8", "facing": 4},
		],
		"cup_spec": {
			"Teal": {"SS Officer": 1, "SS NCO": 2, "SS Schutze": 6},
			"Blue": {"NCO": 1, "Rifleman": 4, "Recruit": 3},
		},
		"dummies": 14,
		"enemy_setup": ["10,9", "11,8", "12,8", "13,5", "14,10", "15,5",
			"15,7", "16,6", "17,7", "17,8", "18,4", "19,4", "20,5", "21,4",
			"22,3", "23,6", "24,2"],
		"vp": {"enemy_killed": 1, "enemy_nco_killed": 2, "enemy_officer_killed": 3,
			"friendly_killed": -2, "friendly_wounded": -1},
	},

	"s12": {
		"name": "12. Overrun",
		"map": "woods", "turns": 10, "hand_limit": 3,
		"compass": ["34,5", "33,5"],
		"deploy": {"cols": [20, 28], "rows": [0, 19]},
		"desc": "Ci hanno circondato nel bosco. Reggete finché la\nriserva non arriva: ogni uomo è vitale.",
		"squad_vol2": true,
		# Assalto corazzato SS: Opel Blitz (fanteria) + PzIVH di punta (scelta
		# di design: nessun OOB ufficiale). Il Bazooka Man amico fa l'anticarro.
		"vehicles": [
			{"type": "Opel Blitz", "side": "enemy", "team": "Purple",
				"pos": "1,9", "facing": 1},
			{"type": "PzIVH", "side": "enemy", "team": "Teal",
				"pos": "1,12", "facing": 1},
		],
		"enemy_morale": 1,
		"cup_spec": {
			"Teal": {"SS Officer": 1, "SS NCO": 3, "SS Schutze": 8},
			"Purple": {"SS NCO": 2, "SS Schutze": 6},
		},
		"dummies": 10,
		"enemy_setup": ["1,3", "1,7", "1,11", "1,15", "2,5", "2,9", "2,13",
			"3,4", "3,8", "3,12", "4,6", "4,10"],
		"first_order_d6": ["EVADE 6/5", "SPRINT 6", "SPRINT 5", "SPRINT 6/5",
			"RUN_AND_GUN 6", "RUN_AND_GUN 5"],
		"waves": [
			{"turn": 3, "hexes": ["1,3", "1,7", "1,11", "1,15", "2,5"]},
			{"turn": 6, "hexes": ["1,4", "1,8", "1,12", "2,6", "2,10"]},
		],
		"vp": {"enemy_killed": 1, "enemy_nco_killed": 2, "enemy_officer_killed": 3,
			"friendly_killed": -3, "friendly_wounded": -1},
	},

	"s13": {
		"name": "13. Find That Radio",
		"map": "hamlet", "turns": 12, "hand_limit": 3,
		"compass": ["34,5", "33,5"],
		"deploy": {"cols": [1, 4], "rows": [0, 19]},
		"desc": "Una radio tedesca trasmette ordini di attacco.\nTrovatela e distruggetela prima che sia troppo tardi.",
		"squad_vol2": true,
		"cup_spec": {
			"Blue": {"NCO": 1, "Rifleman": 4, "Recruit": 4},
			"Red": {"Rifleman": 3, "Recruit": 4},
		},
		"dummies": 14,
		"enemy_setup": ["11,1", "11,4", "12,9", "13,5", "14,12", "15,14",
			"16,6", "17,8", "18,4", "19,6", "20,6", "21,11", "22,4"],
		"objective_hexes": ["11,1", "17,15", "21,11"],
		"vp": {"enemy_killed": 1, "friendly_killed": -2, "friendly_wounded": -1,
			"objective_each": 4},
	},

	"s14": {
		"name": "14. Defend the CP",
		"map": "hamlet", "turns": 15, "hand_limit": 3,
		"compass": ["34,10", "35,10"],
		"deploy": {"cols": [12, 20], "rows": [0, 19]},
		"desc": "Il posto di comando è nel casolare. I tedeschi vengono\ndalle colline. Tenete la posizione a ogni costo.",
		"squad_vol2": true,
		# Jeep di collegamento al CP (scelta di design).
		"vehicles": [
			{"type": "Jeep", "side": "friendly", "team": "Baker",
				"pos": "13,9", "facing": 2},
		],
		"enemy_morale": 1,
		"cup_spec": {
			"Purple": {"SS Officer": 1, "SS NCO": 3, "SS Schutze": 7},
			"Yellow": {"Officer": 1, "NCO": 2, "Rifleman": 4},
		},
		"dummies": 12,
		"enemy_setup": ["31,3", "31,7", "31,11", "31,15", "32,5", "32,9",
			"32,13", "33,4", "33,8", "33,12", "34,6", "34,10", "35,5", "35,9"],
		"first_order_d6": ["SPRINT 5", "SPRINT 6", "RUN_AND_GUN 5",
			"RUN_AND_GUN 6", "EVADE 6/5", "SPRINT 5/6"],
		"vp": {"enemy_killed": 1, "enemy_nco_killed": 2, "enemy_officer_killed": 3,
			"friendly_killed": -2, "friendly_wounded": -1,
			"no_enemy_in_building": 6},
	},

	"s15": {
		"name": "15. They're Falling Back",
		"map": "town", "turns": 12, "hand_limit": 3,
		"compass": ["34,5", "33,5"],
		"deploy": {"cols": [1, 4], "rows": [0, 19]},
		"desc": "I tedeschi si ritirano nel paese. Non lasciateli\nriorganizzarsi: inseguiteli e sgombrate le strade.",
		"squad_vol2": true,
		# Jeep da ricognizione per l'inseguimento (scelta di design).
		"vehicles": [
			{"type": "Jeep", "side": "friendly", "team": "Baker",
				"pos": "2,9", "facing": 4},
		],
		"cup_spec": {
			"Blue": {"Officer": 1, "NCO": 2, "Rifleman": 5, "Recruit": 3},
			"Red": {"NCO": 1, "Rifleman": 4, "Recruit": 4},
		},
		"dummies": 18,
		"enemy_setup": ["17,8", "20,4", "21,2", "21,13", "22,1", "23,3",
			"23,7", "23,17", "27,14", "30,7", "30,11", "33,2", "33,3"],
		"building_tqc_aimed": true,
		"vp": {"enemy_killed": 1, "enemy_nco_killed": 2, "enemy_officer_killed": 3,
			"friendly_killed": -2, "friendly_wounded": -1,
			"no_enemy_in_building": 6},
	},

	"s16": {
		"name": "16. Get Them Out of There",
		"map": "abbey", "turns": 14, "hand_limit": 3,
		"compass": ["34,5", "33,5"],
		"deploy": {"cols": [1, 4], "rows": [0, 19]},
		"desc": "Un partigiano è intrappolato nell'abbazia occupata dai\ntedeschi. Entrate, prendetelo, uscite subito.",
		"squad_vol2": true,
		# Camion GMC per l'estrazione rapida (scelta di design).
		"vehicles": [
			{"type": "GMC 2.5t", "side": "friendly", "team": "Baker",
				"pos": "2,10", "facing": 4},
		],
		"cup_spec": {
			"Teal": {"SS Officer": 1, "SS NCO": 3, "SS Schutze": 5},
			"Blue": {"NCO": 1, "Rifleman": 3, "Recruit": 3},
		},
		"dummies": 12,
		"enemy_setup": ["18,8", "19,10", "19,12", "20,8", "20,10",
			"21,10", "22,11", "23,11", "24,9", "25,10"],
		"maquis_hex": "21,12",
		"exit_col": 2,
		"vp": {"enemy_killed": 1, "friendly_killed": -2, "friendly_wounded": -1,
			"maquis_rescued": 12, "friendly_exited": 1},
	},

	"s17": {
		"name": "17. Clear Them Out",
		"map": "town", "turns": 15, "hand_limit": 3,
		"compass": ["2,5", "3,5"],
		"deploy": {"cols": [31, 35], "rows": [0, 19]},
		"desc": "Il paese va ripreso casa per casa. Ogni edificio\nnasconde un pericolo: procedate con cautela.",
		"squad_vol2": true,
		# Halftrack con la .50cal per ripulire gli edifici (scelta di design).
		"vehicles": [
			{"type": "M3A1 Halftrack", "side": "friendly", "team": "Baker",
				"pos": "32,10", "facing": 4},
		],
		"cup_spec": {
			"Purple": {"SS Officer": 1, "SS NCO": 3, "SS Veteran": 2, "SS Schutze": 6},
			"White": {"NCO": 2, "Rifleman": 5, "Recruit": 3},
		},
		"dummies": 20,
		"enemy_setup": ["3,14", "3,15", "5,6", "5,14", "9,11", "9,14",
			"11,6", "15,11", "16,1", "17,8", "20,4", "21,2", "22,1",
			"23,3", "23,5", "23,7", "24,2", "27,14", "30,7", "30,8",
			"30,11", "33,2"],
		"building_tqc_aimed": true,
		"vp": {"enemy_killed": 1, "enemy_nco_killed": 2, "enemy_officer_killed": 3,
			"friendly_killed": -2, "friendly_wounded": -1,
			"no_enemy_in_building": 8},
	},

	"s18": {
		"name": "18. Great Minds",
		"map": "abbey", "turns": 12, "hand_limit": 3,
		"compass": ["2,5", "3,5"],
		"deploy": {"cols": [1, 4], "rows": [0, 19]},
		"desc": "Entrambe le parti vogliono l'abbazia. Chi ci arriva\nper primo controlla la posizione chiave.",
		"night": true,
		"squad_vol2": true,
		"cup_spec": {
			"Teal": {"SS Officer": 1, "SS NCO": 2, "SS Schutze": 6},
			"Purple": {"SS NCO": 2, "SS Schutze": 4},
		},
		"dummies": 10,
		"enemy_setup": ["31,3", "31,7", "31,11", "32,5", "32,9", "32,13",
			"33,4", "33,8", "33,12", "34,6"],
		"first_order_d6": ["SPRINT 6/5", "SPRINT 5/6", "RUN_AND_GUN 5",
			"RUN_AND_GUN 6", "EVADE 5/6", "SPRINT 6"],
		"objective_hexes": ["19,12", "22,11", "23,11"],
		"vp": {"enemy_killed": 1, "enemy_nco_killed": 2, "enemy_officer_killed": 3,
			"friendly_killed": -2, "friendly_wounded": -1,
			"objective_each": 4},
	},

	"s19": {
		"name": "19. No Man Left Behind",
		"map": "hedgerows2", "turns": 14, "hand_limit": 3,
		"compass": ["34,5", "33,5"],
		"deploy": {"cols": [1, 4], "rows": [0, 19]},
		"desc": "Un soldato ferito è rimasto indietro tra le siepi.\nRecuperate Mitchell e riportarlo alle linee.",
		"squad_vol2": true,
		# Jeep per il recupero del ferito (scelta di design).
		"vehicles": [
			{"type": "Jeep", "side": "friendly", "team": "Baker",
				"pos": "2,11", "facing": 4},
		],
		"cup_spec": {
			"Blue": {"NCO": 1, "Rifleman": 4, "Recruit": 5},
			"Red": {"NCO": 1, "Rifleman": 4, "Recruit": 4},
		},
		"dummies": 14,
		"enemy_setup": ["11,7", "12,4", "13,3", "14,9", "15,6", "16,8",
			"17,3", "18,8", "19,2", "20,3", "21,5", "22,4", "24,2"],
		"maquis_hex": "17,14",
		"exit_col": 2,
		"vp": {"enemy_killed": 1, "friendly_killed": -2, "friendly_wounded": -1,
			"maquis_rescued": 10, "friendly_exited": 1},
	},

	"s20": {
		"name": "20. Long Run Home",
		"map": "hedgerows2", "turns": 12, "hand_limit": 3,
		"compass": ["2,5", "3,5"],
		"deploy": {"cols": [14, 20], "rows": [0, 19]},
		"desc": "Intrappolati tra le siepi, circondati. La via di\nfuga è verso ovest: raggiungete le linee alleate.",
		"squad_vol2": true,
		"enemy_morale": 2,
		"cup_spec": {
			"Teal": {"SS Officer": 1, "SS NCO": 2, "SS Schutze": 5},
			"Yellow": {"NCO": 1, "Rifleman": 4, "Recruit": 4},
		},
		"dummies": 12,
		"enemy_setup": ["1,4", "1,8", "1,12", "2,6", "2,10", "3,5", "3,9",
			"28,4", "28,8", "28,12", "29,6", "29,10"],
		"exit_col": 2,
		"vehicles": [
			{"type": "M3A1 Halftrack", "side": "friendly", "team": "Baker",
				"pos": "17,10", "facing": 4},
		],
		"vp": {"enemy_killed": 1, "friendly_killed": -3, "friendly_wounded": -1,
			"friendly_exited": 3},
	},

	"s21": {
		"name": "21. Machine-Gun Ridge",
		"map": "ridge", "turns": 15, "hand_limit": 3,
		"compass": ["34,5", "33,5"],
		"deploy": {"cols": [31, 35], "rows": [0, 19]},
		"desc": "Una mitragliatrice tedesca controlla tutta la cresta.\nNeutralizzatela prima che l'avanzata sia bloccata.",
		"squad_vol2": true,
		"cup_spec": {
			"Teal": {"SS Officer": 1, "SS NCO": 3, "SS Veteran": 2,
				"SS Schutze": 4, "AT Grenadier": 1},
			"Purple": {"SS NCO": 2, "SS Schutze": 3, "AT Grenadier": 1},
		},
		"dummies": 16,
		"enemy_setup": ["10,6", "11,4", "11,12", "13,8", "13,11",
			"15,3", "15,5", "15,13", "17,7", "17,9", "17,15",
			"19,10", "21,7", "22,3", "23,15", "24,9"],
		"gun_hexes": ["13,11", "17,9"],
		# Le due MG (gun_hexes) sono in nido fortificato (Rule 27.2): non
		# caricabili, vanno neutralizzate col fuoco o col C4. Trincee (27.4)
		# per la fanteria di supporto lungo la linea che batte la cresta.
		"fortified": ["13,11", "17,9"],
		"trench": ["11,12", "13,8", "15,5", "17,7", "19,10"],
		"c4": true,
		"vehicles": [
			{"type": "M4A3 Sherman", "side": "friendly", "team": "Able",
				"pos": "32,10", "facing": 4},
		],
		"vp": {"enemy_killed": 1, "enemy_nco_killed": 2, "enemy_officer_killed": 3,
			"friendly_killed": -2, "friendly_wounded": -1,
			"guns_required": true},
	},

	"s22": {
		"name": "22. Outflanked",
		"map": "ridge", "turns": 12, "hand_limit": 3,
		"compass": ["34,10", "35,10"],
		"deploy": {"cols": [14, 22], "rows": [0, 19]},
		"desc": "Ci hanno aggirato su entrambi i fianchi sulla cresta.\nReggetevi finché l'artiglieria alleata non parla.",
		"squad_vol2": true,
		"enemy_morale": 1,
		"cup_spec": {
			"Purple": {"SS Officer": 1, "SS NCO": 3, "SS Veteran": 2, "SS Schutze": 6},
			"Teal": {"SS NCO": 2, "SS Schutze": 4},
		},
		"dummies": 14,
		"enemy_setup": ["1,4", "1,8", "1,12", "2,6", "2,10", "3,5",
			"31,4", "31,8", "31,12", "32,6", "32,10", "33,5", "35,3", "35,9"],
		# Difesa scavata al centro della cresta (US, zona di schieramento):
		# linea di trincee (27.4) con un caposaldo fortificato (27.2, 18,10).
		"trench": ["16,7", "17,8", "18,9", "17,10", "16,11", "18,12"],
		"fortified": ["18,10"],
		"first_order_d6": ["SPRINT 6", "SPRINT 5", "RUN_AND_GUN 6",
			"RUN_AND_GUN 5", "SPRINT 6/5", "SPRINT 5/6"],
		"waves": [
			{"turn": 4, "hexes": ["1,5", "1,9", "1,13", "35,5", "35,9"]},
		],
		"vehicles": [
			{"type": "PzIVH", "side": "enemy", "team": "Purple",
				"pos": "33,10", "facing": 4},
		],
		"vp": {"enemy_killed": 1, "enemy_nco_killed": 2, "enemy_officer_killed": 3,
			"friendly_killed": -3, "friendly_wounded": -1},
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

	# Squadra: esplicita per scenario, o la squadra completa (scenari 1-9)
	# con posizioni iniziali nella zona di deploy.
	var roster: Array = sc.get("friendly", [])
	if sc.get("squad_full", false):
		roster = FULL_SQUAD
	elif sc.get("squad_vol2", false):
		roster = FULL_SQUAD_VOL2
	var spawn := deploy_hexes(state, scenario_id)
	var spawn_i := 0
	for f in roster:
		var fc := _make(f, D.Side.FRIENDLY)
		fc.morale = int(sc.get("friendly_morale", D.Morale.NORMAL))
		if not f.has("pos") and spawn_i < spawn.size():
			fc.position = spawn[spawn_i]
			spawn_i += 1
		if sc.get("taylor_bad_wound", false) and fc.display_name == "Sgt Taylor":
			fc.wounds.append(D.Wound.BAD)
		state.characters.append(fc)
	# MG Operator (Rule 14.3): il portatore di munizioni parte nello stesso hex
	# dell'operatore (evita il -3 WS da turno 1). La chiave "mg_companion" nel
	# roster entry indica chi deve condividere l'hex.
	for f in roster:
		if f.has("mg_companion"):
			var op_name: String = f["name"]
			var companion_name: String = f["mg_companion"]
			var op: Character = null
			var companion: Character = null
			for fc in state.characters:
				if fc.display_name == op_name:
					op = fc
				elif fc.display_name == companion_name:
					companion = fc
			if op != null and companion != null:
				companion.position = op.position
	# Il Maquis da salvare (s8): friendly senza ordini, nel casolare.
	if sc.has("maquis_hex"):
		var mq := _make({"name": "Maquis", "role": "Maquis", "team": "Charlie",
			"counter": "CIV-Alex"}, D.Side.FRIENDLY)
		var mp: PackedStringArray = String(sc["maquis_hex"]).split(",")
		mq.position = Vector2i(int(mp[0]), int(mp[1]))
		state.characters.append(mq)
	# Scenario notturno: -2 al fuoco oltre 2 hex (salvo illuminazione).
	state.night = bool(sc.get("night", false))
	state.large_battle = bool(sc.get("large_battle", false))
	# Meteo e condizioni del terreno (Rule 28): chiavi "weather"/"ground"
	# (nomi in Weather.TYPE_BY_NAME/GROUND_BY_NAME). Il limite di visibilita'
	# si tira ora a inizio scenario.
	state.weather = Weather.TYPE_BY_NAME.get(sc.get("weather", "clear"), Weather.Type.CLEAR)
	state.ground = Weather.GROUND_BY_NAME.get(sc.get("ground", "none"), Weather.Ground.NONE)
	state.max_los = Weather.roll_max_los(state.weather, state.rng)
	# Filo spinato (Rule 27.7): overlay sugli hex elencati nella chiave "wire".
	for wk in sc.get("wire", []):
		var wp: PackedStringArray = String(wk).split(",")
		var wh := state.hex_at(int(wp[0]), int(wp[1]))
		if wh != null:
			wh.wire = true
	# Trincee (Rule 27.4) ed edifici fortificati (Rule 27.2): per regola si
	# piazzano via scenario (chiavi "trench"/"fortified"). Sovrascrivono il
	# terreno dell'hex col tipo speciale gia' modellato in Domain.Terrain.
	for tk in sc.get("trench", []):
		var tp: PackedStringArray = String(tk).split(",")
		var th := state.hex_at(int(tp[0]), int(tp[1]))
		if th != null:
			th.terrain = D.Terrain.TRENCH
	for fk in sc.get("fortified", []):
		var fp: PackedStringArray = String(fk).split(",")
		var fh := state.hex_at(int(fp[0]), int(fp[1]))
		if fh != null:
			fh.terrain = D.Terrain.FORTIFIED_BUILDING
	if state.weather != Weather.Type.CLEAR or state.ground != Weather.Ground.NONE:
		state.log_event("Meteo: %s, terreno: %s%s" % [
			Weather.TYPE_NAMES[state.weather], Weather.GROUND_NAMES[state.ground],
			"" if state.max_los == 0 else " (visibilita' max %d hex)" % state.max_los])
	# Bussola del nemico (Rule 9.3): ["hex", "hex verso cui punta '1'"];
	# default: "1" = nord.
	var dir1 := Vector3i(0, 1, -1)
	var comp: Array = sc.get("compass", [])
	if comp.size() == 2:
		var pa: PackedStringArray = String(comp[0]).split(",")
		var pb: PackedStringArray = String(comp[1]).split(",")
		dir1 = Move.to_cube(Vector2i(int(pb[0]), int(pb[1]))) \
			- Move.to_cube(Vector2i(int(pa[0]), int(pa[1])))
	state.compass = Move.compass_from_dir1(dir1)
	# Vento: 1D6 sulla bussola; il fumo deriva di 1 hex per turno.
	var wind_d := state.rng.randi_range(1, 6)
	state.wind = state.compass[wind_d]
	state.log_event("Vento verso direzione %d della bussola" % wind_d)

	# Coppa nemica = personaggi reali + pedine-esca, mescolata.
	var cup: Array = make_cup(sc["cup_spec"]) if sc.has("cup_spec") \
		else sc["enemy_cup"].duplicate()
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

	# Bombardamento iniziale (se previsto dallo scenario, es. s2).
	if sc.has("opening_barrage"):
		_run_opening_barrage(state, sc["opening_barrage"])

	# Veicoli (Rule 31-32): lista opzionale di veicoli schierati nello scenario.
	# Ogni voce: {"type": "M4A3 Sherman", "team": "Able", "pos": "5,10",
	#   "facing": 4, "weapon": "", "side": "friendly"/"enemy"}.
	for ve in sc.get("vehicles", []):
		var vtype: String = ve["type"]
		var vdata: Dictionary = VehicleCombat.VEHICLE_DATA.get(vtype, {})
		var vside_str: String = ve.get("side",
			"friendly" if int(vdata.get("side", D.Side.FRIENDLY)) == D.Side.FRIENDLY
			else "enemy")
		var vside: int = D.Side.FRIENDLY if vside_str == "friendly" else D.Side.ENEMY
		var vteam: String = ve.get("team", "Able")
		var vfacing: int = ve.get("facing", 4)
		var vweapon: String = ve.get("weapon", "")
		var vc := VehicleCombat.make_vehicle(vtype, vside, vteam, Vector2i(0, 0), vfacing, vweapon)
		if ve.has("pos"):
			var vp: PackedStringArray = String(ve["pos"]).split(",")
			vc.position = Vector2i(int(vp[0]), int(vp[1]))
		if vside == D.Side.ENEMY:
			vc.alerted = true
			vc.known = true   # un veicolo e' sempre visibile (non si nasconde)
			vc.morale = int(sc.get("enemy_morale", D.Morale.NORMAL))
		else:
			vc.spotted = true  # il carro amico e' visibile anche ai nemici
		VehicleCombat.sync_crew_morale(vc)  # l'equipaggio eredita il morale del mezzo
		state.characters.append(vc)
		state.log_event("Veicolo schierato: %s (%s) in %02d.%02d" % [
			vtype, vteam, vc.position.x, vc.position.y])

	# Mano iniziale (Starting Hand Size).
	for i in range(state.hand_limit):
		state.friendly_hand.append(state.draw_friendly_card())


# Piazza un personaggio nemico (coperto = alerted, non known) a un hex.
static func _place_enemy(state: GameState, entry: Dictionary, hexkey: String) -> Character:
	var e := _make(entry, D.Side.ENEMY)
	var p: PackedStringArray = String(hexkey).split(",")
	e.position = Vector2i(int(p[0]), int(p[1]))
	e.alerted = true
	e.morale = int(SCENARIOS[state.scenario_id].get("enemy_morale", D.Morale.NORMAL))
	state.characters.append(e)
	return e


# Punti di ricognizione: segnati come visitati quando un friendly e'
# nell'hex o adiacente (chiamato in End Phase).
static func scan_objectives(state: GameState) -> void:
	var sc: Dictionary = SCENARIOS[state.scenario_id]
	for hexkey in sc.get("objective_hexes", []):
		if hexkey in state.visited_objectives:
			continue
		var p: PackedStringArray = String(hexkey).split(",")
		var hpos := Vector2i(int(p[0]), int(p[1]))
		for c in state.characters:
			if c.side == D.Side.FRIENDLY and not c.is_dead() \
					and Spotting.hex_distance(c.position, hpos) <= 1:
				state.visited_objectives.append(hexkey)
				state.log_event("Punto di ricognizione %02d.%02d raggiunto!" % [hpos.x, hpos.y])
				break


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
				e.set_order(Weather.demote_order(state.ground, ORDER_BY_NAME[parts[0]]), parts[1])
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
	# L'arma viene dal profilo del ruolo, ma una pedina puo' sostituirla
	# (Rule 26: es. Thompson al posto del Grease Gun) con "weapon"/"ws".
	var weapon: String = entry.get("weapon", prof["weapon"])
	var ws: int = entry.get("ws", prof["ws"])
	if not weapon.is_empty():
		c.weapon_skills = {weapon: ws}
	# Skill SS (Rule 24): dal profilo del ruolo e/o dalla voce di scenario.
	for s in prof.get("skills", []):
		c.skills.append(s)
	for s in entry.get("skills", []):
		if s not in c.skills:
			c.skills.append(s)
	# Medico addestrato (Rule 30): disarmato. Da ruolo ("medic") o pedina.
	if bool(prof.get("medic", false)) or bool(entry.get("medic", false)):
		c.is_medic = true
		c.weapon_skills = {}
	# MG Operator (Rule 14.3): chi imbraccia la belt-fed. L'assistente
	# (portatore di munizioni) e' un compagno qualsiasi nello stesso hex.
	c.mg_role = entry.get("mg_role", "")
	c.counter = entry.get("counter", "")
	c.role = entry["role"]
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
	# Kill divisi per ruolo (NCO/ufficiali valgono di piu').
	var plain := 0
	var ncos := 0
	var officers := 0
	var routed := 0
	for c in state.characters:
		# Un nemico fuggito dalla mappa in Rout conta come eliminato.
		if c.side == D.Side.ENEMY and not c.is_dummy \
				and (c.is_killed() or c.routed_off):
			if c.routed_off:
				routed += 1
			match c.role:
				"NCO": ncos += 1
				"Officer": officers += 1
				_: plain += 1
	vp += plain * int(vp_rules.get("enemy_killed", 0))
	vp += ncos * int(vp_rules.get("enemy_nco_killed", vp_rules.get("enemy_killed", 0)))
	vp += officers * int(vp_rules.get("enemy_officer_killed", vp_rules.get("enemy_killed", 0)))
	parts.append("%d nemici eliminati" % (plain + ncos + officers))
	if routed > 0:
		parts.append("%d fuggiti in rout" % routed)
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
	# Punti di ricognizione (s6).
	if vp_rules.has("objective_each"):
		vp += state.visited_objectives.size() * int(vp_rules["objective_each"])
		parts.append("%d punti ricogniti" % state.visited_objectives.size())
	# Uscita dal bordo amico (s3/s8).
	if sc.has("exit_col"):
		var exited := 0
		var maquis_out := false
		for c in state.characters:
			if c.side == D.Side.FRIENDLY and not c.is_dead() \
					and c.position.x <= int(sc["exit_col"]):
				exited += 1
				if c.role == "Maquis":
					maquis_out = true
		vp += exited * int(vp_rules.get("friendly_exited", 0))
		parts.append("%d usciti dal bordo" % exited)
		if maquis_out and vp_rules.has("maquis_rescued"):
			vp += int(vp_rules["maquis_rescued"])
			parts.append("Maquis in salvo!")
	# Cannoni: obiettivo obbligatorio (intro3/s9).
	if vp_rules.get("guns_required", false):
		var guns: Array = sc.get("gun_hexes", [])
		var all_down := state.guns_destroyed.size() >= guns.size()
		if all_down:
			return {"outcome": "Vittoria - cannoni distrutti!", "vp": vp,
				"detail": ", ".join(parts)}
		return {"outcome": "Sconfitta - %d/%d cannoni distrutti" % [
			state.guns_destroyed.size(), guns.size()], "vp": vp,
			"detail": ", ".join(parts)}
	# Soglie standard (Scenario Book): 15+/12-14/9-11/6-8/1-5/<=0.
	var outcome := "Demozione"
	if vp >= 15:
		outcome = "Vittoria Superba – menzionato nei bollettini!"
	elif vp >= 12:
		outcome = "Buona Vittoria"
	elif vp >= 9:
		outcome = "Vittoria risicata"
	elif vp >= 6:
		outcome = "Non abbastanza"
	elif vp >= 1:
		outcome = "Prestazione scadente"
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


# Bombardamento iniziale di setup (Rule speciale s2): piazza i marker d'artiglieria
# e li fa esplodere subito, prima dell'inizio della partita.
static func _run_opening_barrage(state: GameState, spec: Dictionary) -> void:
	var type_name: String = spec["type"]
	var atype: int = Area.Type.ARTILLERY_105
	if type_name == "MORTAR_81":
		atype = Area.Type.MORTAR_81
	elif type_name == "MORTAR_60":
		atype = Area.Type.MORTAR_60
	var table: Array = spec["hex_table"]
	var n_rolls: int = spec["rolls"]
	var scatter: bool = spec.get("scatter", false)
	state.log_event("=== BOMBARDAMENTO INIZIALE (%s, %d colpi) ===" % [type_name, n_rolls])
	for i in range(n_rolls):
		var idx := Checks.roll_d10(state.rng)
		var hexkey: String = table[idx]
		var p: PackedStringArray = String(hexkey).split(",")
		var hex := Vector2i(int(p[0]), int(p[1]))
		if scatter:
			if state.rng.randi_range(1, 6) > 2:
				var dir: Vector3i = Move.CUBE_DIRS[state.rng.randi_range(0, 5)]
				var dev := Move.from_cube(Move.to_cube(hex) + dir)
				if state.map.has(GameState.hex_key(dev.x, dev.y)):
					state.log_event("  colpo %d: %02d.%02d devia -> %02d.%02d" % [
						i + 1, hex.x, hex.y, dev.x, dev.y])
					hex = dev
		var marker := {"type": atype, "hex": hex, "placed_turn": 0, "turns_left": 1}
		Area._explode(state, marker)
		# Scia di fumo residua (Rule 18): il bombardamento iniziale lascia fumo.
		state.area_markers.append({"type": Area.Type.SMOKE, "hex": hex,
			"placed_turn": 0, "turns_left": 2})


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
