## Random Events — tabelle Attacking/Defending e per-scenario (s3/s6/s10).
## resolve(state, which) tira 1D10 e applica l'effetto in base al tipo
## di scenario (chiave "event_table" nello scenario, default "attacking").
## I mortai/artiglieria piazzano marker Area che esplodono nella End Phase.
## I segnalini ILLUM durano 1 turno e illuminano un raggio di 3 hex.
class_name Events
extends RefCounted

const D := preload("res://engine/Domain.gd")

# ---------------------------------------------------------------- subtable
# Chiavi: "af"=attacking-friendly, "ae"=attacking-enemy,
#         "df"=defending-friendly, "de"=defending-enemy.
# I fuochi amici (af/df) colpiscono il lato nemico; quelli nemici (ae/de)
# colpiscono il lato amico. Defending e' il ribaltamento di Attacking.
const HEXES := {
	"af": {0:"20,7",1:"27,11",2:"20,14",3:"27,16",4:"30,12",
	       5:"28,7",6:"19,14",7:"24,13",8:"23,6",9:"12,10"},
	"ae": {0:"6,6",1:"8,10",2:"10,14",3:"4,15",4:"11,16",
	       5:"10,12",6:"10,4",7:"4,4",8:"5,16",9:"9,15"},
	"df": {0:"6,6",1:"8,10",2:"10,14",3:"4,15",4:"11,16",
	       5:"10,12",6:"10,4",7:"4,4",8:"5,16",9:"9,15"},
	"de": {0:"20,7",1:"27,11",2:"20,14",3:"27,16",4:"30,12",
	       5:"28,7",6:"19,14",7:"24,13",8:"23,6",9:"12,10"},
	# s3: sub-table A (lato amico col 4-11) e B (lato nemico col 20-30).
	# Il fuoco amico usa A ai turni 1-4, B ai turni 5-12 (retroguardia).
	"s3a": {0:"6,6",1:"8,10",2:"10,14",3:"4,15",4:"11,17",
	        5:"10,12",6:"10,4",7:"4,4",8:"5,17",9:"9,17"},
	"s3b": {0:"20,7",1:"27,11",2:"20,14",3:"27,18",4:"30,12",
	        5:"28,7",6:"19,14",7:"24,13",8:"23,6",9:"12,10"},
	# s6 — illuminazione sulla collina
	"s6i": {0:"20,7",1:"27,11",2:"20,14",3:"27,17",4:"30,12",
	        5:"28,7",6:"19,14",7:"24,13",8:"23,6",9:"12,10"},
	# s10 — farmhouse (semplificato a mappa singola)
	"s10a": {0:"8,4",1:"8,12",2:"9,18",3:"10,8",4:"11,16",
	         5:"12,11",6:"15,5",7:"15,10",8:"16,14",9:"16,17"},
	"s10b": {0:"8,3",1:"8,11",2:"9,18",3:"10,7",4:"11,16",
	         5:"12,10",6:"15,5",7:"15,10",8:"16,13",9:"16,16"},
	"s10e": {0:"20,6",1:"27,11",2:"20,13",3:"27,17",4:"30,11",
	         5:"28,6",6:"19,14",7:"24,12",8:"23,6",9:"12,9"},
}

# Sub-table rinforzi da evento per s3 e s6 (roll 1D10 -> hex e ordine).
const REINFORCE_S3 := {
	0: {"hexes": ["23,1","24,1","25,1"],              "move": "5"},
	1: {"hexes": ["23,19","24,19","25,19"],            "move": "6"},
	2: {"hexes": ["12,1","13,1","14,1"],               "move": "5"},
	3: {"hexes": ["17,19","18,19","19,19"],            "move": "6"},
	4: {"hexes": ["35,13","35,14","35,15"],            "move": "6/5"},
	5: {"hexes": ["35,1","35,2","35,3"],               "move": "5"},
	6: {"hexes": ["9,19","10,19","11,19"],             "move": "1"},
	7: {"hexes": ["35,5","35,6","35,7","35,8","35,9"], "move": "5"},
	8: {"hexes": ["6,19","7,19","8,19"],               "move": "1"},
	9: {"hexes": ["1,1","2,1","3,1"],                  "move": "3"},
}


# ---------------------------------------------------------- entry point
static func resolve(state: GameState, which: String, depth: int = 0) -> void:
	if depth > 2:
		return
	var roll := Checks.roll_d10(state.rng)
	var ttype: String = "attacking"
	if not state.scenario_id.is_empty():
		ttype = str(Scenario.SCENARIOS[state.scenario_id].get("event_table", "attacking"))
	state.log_event("▶ Carta Evento (%s) — dado: %d" % [which, roll])
	if which == "friendly":
		_friendly(state, roll, ttype, depth)
	else:
		_enemy(state, roll, ttype, depth)


# ------------------------------------------- tabella FRIENDLY (comuni)
static func _friendly(state: GameState, roll: int, ttype: String, depth: int) -> void:
	match roll:
		0:
			_log(state, "Evento Friendly 0: rimuovo 1 Light Wound amico")
			_remove_light_wound(state, D.Side.FRIENDLY)
		1:
			_log(state, "Evento Friendly 1: via tutti i Low/No Ammo amici")
			_clear_low_ammo(state, D.Side.FRIENDLY)
		2:
			_log(state, "Evento Friendly 2 (Lucky Strike): carta extra in mano")
			state.friendly_hand.append(state.draw_friendly_card())
		7:
			_log(state, "Evento Friendly 7 (Come on men!): +1 morale entro LDR")
			_morale_near_leader(state)
		8:
			_log(state, "Evento Friendly 8: rivelo un nemico nascosto")
			_reveal_one_hidden(state)
		9:
			_log(state, "Evento Friendly 9 (Uh-oh): tiro sulla tabella Nemica")
			resolve(state, "enemy", depth + 1)
		_:
			# Rolls 3-6: fuoco amico; dipendono dallo scenario
			_friendly_fire(state, roll, ttype)


static func _friendly_fire(state: GameState, roll: int, ttype: String) -> void:
	var htab: Dictionary
	match ttype:
		"s3":
			htab = HEXES["s3a"] if state.turn <= 4 else HEXES["s3b"]
			match roll:
				3, 4:
					_log(state, "Evento Friendly 3/4 (s3): mortaio 60mm amico")
					_fire_mortar(state, Area.Type.MORTAR_60, htab, 10)
				5:
					_log(state, "Evento Friendly 5 (s3): mortaio 81mm amico")
					_fire_mortar(state, Area.Type.MORTAR_81, htab, 6)
				6:
					_log(state, "Evento Friendly 6 (s3): artiglieria 105mm amica")
					_fire_mortar(state, Area.Type.ARTILLERY_105, htab, 6)
		"s6":
			match roll:
				3, 4, 5:
					_log(state, "Evento Friendly 3-5 (s6 Infiltrazione): muovo 1 amico")
					_infiltrate(state)
				6:
					_log(state, "Evento Friendly 6 (s6): illuminazione amica")
					_place_illumination(state, HEXES["s6i"])
		"s10":
			match roll:
				3, 4:
					_log(state, "Evento Friendly 3-4 (s10): mortaio 60mm amico")
					_fire_mortar(state, Area.Type.MORTAR_60, HEXES["s10a"], 10)
				5, 6:
					_log(state, "Evento Friendly 5-6 (s10): mortaio 81mm amico")
					_fire_mortar(state, Area.Type.MORTAR_81, HEXES["s10b"], 6)
		"defending":
			htab = HEXES["df"]
			match roll:
				3, 4:
					_log(state, "Evento Friendly 3/4 (Defending): mortaio 60mm amico")
					_fire_mortar(state, Area.Type.MORTAR_60, htab, 10)
				5:
					_log(state, "Evento Friendly 5 (Defending): mortaio 81mm amico")
					_fire_mortar(state, Area.Type.MORTAR_81, htab, 6)
				6:
					_log(state, "Evento Friendly 6 (Defending): artiglieria 105mm amica")
					_fire_mortar(state, Area.Type.ARTILLERY_105, htab, 6)
		_:  # "attacking" e default
			htab = HEXES["af"]
			match roll:
				3, 4:
					_log(state, "Evento Friendly 3/4 (Attacking): mortaio 60mm amico")
					_fire_mortar(state, Area.Type.MORTAR_60, htab, 10)
				5:
					_log(state, "Evento Friendly 5 (Attacking): mortaio 81mm amico")
					_fire_mortar(state, Area.Type.MORTAR_81, htab, 6)
				6:
					_log(state, "Evento Friendly 6 (Attacking): artiglieria 105mm amica")
					_fire_mortar(state, Area.Type.ARTILLERY_105, htab, 6)


# --------------------------------------------- tabella ENEMY (comuni)
static func _enemy(state: GameState, roll: int, ttype: String, depth: int) -> void:
	match roll:
		0:
			_log(state, "Evento Enemy 0: tiro sulla tabella Amica")
			resolve(state, "friendly", depth + 1)
		1:
			_log(state, "Evento Enemy 1: via tutti i Low Ammo nemici")
			_clear_low_ammo(state, D.Side.ENEMY)
		2:
			if ttype == "s6":
				_log(state, "Evento Enemy 2 (s6 Rumore!): nemici Waiting nel raggio 5 TQC")
				_noise_event(state)
			else:
				_log(state, "Evento Enemy 2 (Second Thoughts): cambio un ordine nemico")
				_rechange_enemy_order(state)
		9:
			if ttype == "attacking":
				_log(state, "Evento Enemy 9 (Campo minato!): MC su un amico")
				_minefield_simplified(state)
			else:
				_log(state, "Evento Enemy 9: rimuovo 1 Light Wound da un nemico")
				_remove_light_wound(state, D.Side.ENEMY)
		_:
			_enemy_fire(state, roll, ttype)


static func _enemy_fire(state: GameState, roll: int, ttype: String) -> void:
	match ttype:
		"s3":
			var htab: Dictionary = HEXES["s3b"] if state.turn <= 4 else HEXES["s3a"]
			match roll:
				3:
					_log(state, "Evento Enemy 3 (s3): mortaio 81mm nemico")
					_fire_mortar(state, Area.Type.MORTAR_81, htab, 10)
				4:
					_log(state, "Evento Enemy 4 (s3): artiglieria 105mm nemica")
					_fire_mortar(state, Area.Type.ARTILLERY_105, htab, 6)
				5, 6, 7:
					_log(state, "Evento Enemy 5-7 (s3): rinforzi da sub-tabella")
					_reinforce_subtable(state, REINFORCE_S3)
				8:
					_log(state, "Evento Enemy 8 (s3): rinforzi bordo est (Evade 6/5)")
					_enemy_reinforce_with_order(state,
						["35,5","35,6","35,7","35,8","35,9","35,10"], "6/5")
		"s6":
			match roll:
				3, 4, 5:
					_log(state, "Evento Enemy 3-5 (s6 Campo minato): MC su un amico")
					_minefield_simplified(state)
				6:
					_log(state, "Evento Enemy 6 (s6): illuminazione nemica")
					_place_illumination(state, HEXES["s6i"])
				7, 8:
					_log(state, "Evento Enemy 7-8 (s6): rinforzi da sub-tabella")
					_reinforce_subtable(state, REINFORCE_S3)
		"s10":
			match roll:
				2, 3:
					_log(state, "Evento Enemy 2-3 (s10): rinforzi lato ovest")
					_enemy_reinforce_with_order(state,
						["7,12","7,13","7,14","7,15","7,16"], "6/5")
				4, 5:
					_log(state, "Evento Enemy 4-5 (s10): rinforzi lato est")
					_enemy_reinforce_with_order(state,
						["31,7","31,8","31,9","31,10","31,11"], "5/6")
				6, 7:
					_log(state, "Evento Enemy 6-7 (s10): mortaio 81mm nemico")
					_fire_mortar(state, Area.Type.MORTAR_81, HEXES["s10e"], 10)
				8:
					_log(state, "Evento Enemy 8 (s10): artiglieria 105mm nemica")
					_fire_mortar(state, Area.Type.ARTILLERY_105, HEXES["s10e"], 6)
		"defending":
			match roll:
				3, 4, 5:
					_log(state, "Evento Enemy 3-5 (Defending): mortaio 81mm nemico")
					_fire_mortar(state, Area.Type.MORTAR_81, HEXES["de"], 10)
				6:
					_log(state, "Evento Enemy 6 (Defending): artiglieria 105mm nemica")
					_fire_mortar(state, Area.Type.ARTILLERY_105, HEXES["de"], 6)
				7:
					_log(state, "Evento Enemy 7 (Defending): rinforzi (01.01-01.05)")
					_enemy_reinforce_with_order(state,
						["1,1","1,2","1,3","1,4","1,5"], "6/5")
				8:
					_log(state, "Evento Enemy 8 (Defending): rinforzi (01.13-01.17)")
					_enemy_reinforce_with_order(state,
						["1,13","1,14","1,15","1,16","1,17"], "6/5")
		_:  # "attacking" e default
			match roll:
				3, 4:
					_log(state, "Evento Enemy 3/4 (Attacking): mortaio 81mm nemico")
					_fire_mortar(state, Area.Type.MORTAR_81, HEXES["ae"], 10)
				5:
					_log(state, "Evento Enemy 5 (Attacking): artiglieria 105mm nemica")
					_fire_mortar(state, Area.Type.ARTILLERY_105, HEXES["ae"], 6)
				6:
					_log(state, "Evento Enemy 6 (Attacking): rinforzi (35.16-35.18)")
					_enemy_reinforce_with_order(state,
						["35,16","35,17","35,18"], "6")
				7:
					_log(state, "Evento Enemy 7 (Attacking): rinforzi (35.06-35.10)")
					_enemy_reinforce_with_order(state,
						["35,6","35,7","35,8","35,9","35,10"], "6/5")
				8:
					_log(state, "Evento Enemy 8 (Attacking): rimuovo 1 Light Wound nemico")
					_remove_light_wound(state, D.Side.ENEMY)


# --------------------------------------------------- helper fuoco/illum
static func _fire_mortar(state: GameState, area_type: int, hexes: Dictionary,
		count_die: int) -> void:
	var count: int = Checks.roll_d10(state.rng) if count_die == 10 \
		else state.rng.randi_range(1, 6)
	if count == 0:
		_log(state, "  Nessun colpo (dado 0)")
		return
	_log(state, "  %s: %d colp%s" % [
		Area.NAMES[area_type], count, "o" if count == 1 else "i"])
	for _i in count:
		var roll := Checks.roll_d10(state.rng)
		var hk: String = hexes.get(roll, "")
		if hk.is_empty():
			continue
		var parts := hk.split(",")
		Area.place_with_scatter(state, area_type, Vector2i(int(parts[0]), int(parts[1])))


static func _place_illumination(state: GameState, hexes: Dictionary) -> void:
	var roll := Checks.roll_d10(state.rng)
	var hk: String = hexes.get(roll, "")
	if hk.is_empty():
		return
	var parts := hk.split(",")
	var hex := Vector2i(int(parts[0]), int(parts[1]))
	Area.place_with_scatter(state, Area.Type.ILLUM, hex)


# -------------------------------------------------- helper rinforzi
static func _reinforce_subtable(state: GameState, subtable: Dictionary) -> void:
	var sub_roll := Checks.roll_d10(state.rng)
	var sub: Dictionary = subtable.get(sub_roll, {})
	if sub.is_empty():
		return
	_enemy_reinforce_with_order(state, sub["hexes"], sub["move"])


static func _enemy_reinforce_with_order(state: GameState, hexes: Array,
		move: String) -> void:
	var placed := 0
	for hexkey in hexes:
		if state.enemy_reserve.is_empty():
			break
		var e := Scenario._place_enemy(state, state.enemy_reserve.pop_front(), hexkey)
		e.alerted = true   # rinforzi: entrano gia' in combattimento
		e.prepared = true
		e.set_order(D.Order.EVADE, move)
		e.had_first_order = true
		placed += 1
	if placed > 0:
		_log(state, "  %d rinforz%s (EVADE %s)" % [
			placed, "o" if placed == 1 else "i", move])
	else:
		_log(state, "  Nessun rinforzo disponibile nella riserva")


# ----------------------------------------------- eventi speciali
static func _infiltrate(state: GameState) -> void:
	# Sposta automaticamente l'amico non avvistato piu' vicino a un nemico.
	var best: Character = null
	var best_d := 99999
	for f in state.characters:
		if f.side != D.Side.FRIENDLY or f.is_dead() or f.spotted:
			continue
		for e in state.characters:
			if e.side == D.Side.ENEMY and not e.is_dead():
				var d := Spotting.hex_distance(f.position, e.position)
				if d < best_d:
					best_d = d
					best = f
	if best == null:
		_log(state, "  Infiltrazione: nessun amico non avvistato disponibile")
		return
	var target_hex := best.position
	var nearest_d := 99999
	for e in state.characters:
		if e.side == D.Side.ENEMY and not e.is_dead():
			var d := Spotting.hex_distance(best.position, e.position)
			if d < nearest_d:
				nearest_d = d
				target_hex = e.position
	var best_nb := best.position
	var best_nd := nearest_d
	for dir in Move.CUBE_DIRS:
		var nb := Move.from_cube(Move.to_cube(best.position) + dir)
		if not state.map.has(GameState.hex_key(nb.x, nb.y)):
			continue
		var nd := Spotting.hex_distance(nb, target_hex)
		if nd < best_nd:
			best_nd = nd
			best_nb = nb
	if best_nb != best.position:
		best.position = best_nb
		_log(state, "  Infiltrazione: %s -> %02d.%02d" % [
			best.display_name, best_nb.x, best_nb.y])
	else:
		_log(state, "  Infiltrazione: %s non puo' avanzare" % best.display_name)


static func _knife_attack_or_morale(state: GameState) -> void:
	for f in state.characters:
		if f.side != D.Side.FRIENDLY or f.is_dead() or f.spotted:
			continue
		for e in state.characters:
			if e.side != D.Side.ENEMY or e.is_dead() or e.alerted:
				continue
			if Spotting.hex_distance(f.position, e.position) == 1:
				_log(state, "  Knife Attack! %s elimina silenziosamente %s" % [
					f.display_name, e.display_name])
				e.removed = true
				f.spotted = false
				f.set_order(D.Order.HIDE)
				return
	_log(state, "  Evento Friendly 7 (Knife Attack non disponibile): +1 morale entro LDR")
	_morale_near_leader(state)


static func _noise_event(state: GameState) -> void:
	var teams := ["Able", "Baker", "Charlie"]
	var t_roll := state.rng.randi_range(1, 6)
	var team_name: String = teams[(t_roll - 1) / 2]
	var noisy: Character = null
	for f in state.characters:
		if f.side == D.Side.FRIENDLY and not f.is_dead() and f.team == team_name:
			noisy = f
			break
	if noisy == null:
		_log(state, "  Rumore (team %s): nessun amico disponibile" % team_name)
		return
	_log(state, "  Rumore! %s ha fatto rumore" % noisy.display_name)
	for e in state.characters:
		if e.side != D.Side.ENEMY or e.is_dead() or e.alerted:
			continue
		if Spotting.hex_distance(e.position, noisy.position) <= 5:
			var r := Checks.roll_d10(state.rng)
			if r <= Checks.effective_tq(e):
				e.alerted = true
				_log(state, "  %s si allerta (TQ %d, dado %d)" % [
					e.display_name, Checks.effective_tq(e), r])


static func _minefield_simplified(state: GameState) -> void:
	var alive: Array[Character] = []
	for c in state.characters:
		if c.side == D.Side.FRIENDLY and not c.is_dead():
			alive.append(c)
	if alive.is_empty():
		return
	var victim: Character = alive[state.rng.randi_range(0, alive.size() - 1)]
	_log(state, "  Campo minato! %s: MC" % victim.display_name)
	Checks.morale_check(victim, state.rng)


# --------------------------------------------------- effetti base
static func _clear_low_ammo(state: GameState, side: int) -> void:
	for c in state.characters:
		if c.side == side and not c.is_dead():
			c.low_ammo = false
			c.no_ammo = false


static func _remove_light_wound(state: GameState, side: int) -> void:
	for c in state.characters:
		if c.side == side and not c.is_dead() and D.Wound.LIGHT in c.wounds:
			c.wounds.erase(D.Wound.LIGHT)
			_log(state, "  Light Wound rimossa da %s" % c.display_name)
			return


static func _morale_near_leader(state: GameState) -> void:
	var leaders: Array[Character] = []
	for c in state.characters:
		if c.side == D.Side.FRIENDLY and c.leadership > 0 and not c.is_dead():
			leaders.append(c)
	for c in state.characters:
		if c.side != D.Side.FRIENDLY or c.is_dead():
			continue
		for ldr in leaders:
			if Spotting.hex_distance(c.position, ldr.position) <= ldr.leadership:
				c.morale = D.raise_morale(c.morale, 1, D.Morale.AGGRESSIVE)
				break


static func _reveal_one_hidden(state: GameState) -> void:
	for c in state.characters:
		if c.side == D.Side.ENEMY and not c.known and not c.is_dead() and not c.is_dummy:
			c.known = true
			_log(state, "  Rivelato: %s in %02d.%02d" % [
				c.display_name, c.position.x, c.position.y])
			return


static func _rechange_enemy_order(state: GameState) -> void:
	var best: Character = null
	var best_d := 99999
	for e in state.characters:
		if e.side != D.Side.ENEMY or e.is_dead() or not e.alerted:
			continue
		for f in state.characters:
			if f.side == D.Side.FRIENDLY and not f.is_dead():
				var d := Spotting.hex_distance(e.position, f.position)
				if d < best_d:
					best_d = d
					best = e
	if best != null and state.enemy_cards_in_play.has(best.team):
		var serial: int = state.enemy_cards_in_play[best.team]
		var hex := state.hex_at(best.position.x, best.position.y)
		var in_cover := hex != null and Domain.terrain_gives_cover(hex.terrain)
		if EnemyCards.has_table_row(best.morale):
			var entry := EnemyCards.lookup(serial, best.morale, in_cover)
			best.set_order(entry["order"], entry["move"], entry["grenade"], entry["charge"])
			_log(state, "  %s cambia ordine -> %s" % [
				best.display_name, Domain.ORDER_NAMES[best.order]])


static func _log(state: GameState, msg: String) -> void:
	state.log_event(msg)
