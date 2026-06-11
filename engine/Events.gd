## Random Events (Friendly/Enemy Event Table, versione Defending),
## trascritte dalle tabelle. resolve(state, which) tira 1D10 e applica
## l'effetto. Gli effetti "a segnalino" (illuminazione, mortai, artiglieria
## con scatter) sono registrati nel log ma non ancora piazzati: il sistema
## dei segnalini d'area e' un TODO. Gli altri sono applicati.
class_name Events
extends RefCounted

const D := preload("res://engine/Domain.gd")


static func resolve(state: GameState, which: String, depth: int = 0) -> void:
	if depth > 2:
		return  # guardia anti-ricorsione (0/9 rimandano all'altra tabella)
	var roll := Checks.roll_d10(state.rng)
	if which == "friendly":
		_friendly(state, roll, depth)
	else:
		_enemy(state, roll, depth)


static func _friendly(state: GameState, roll: int, depth: int) -> void:
	match roll:
		0:
			_log(state, "Evento Friendly 0: rimuovo 1 Light Wound")
			_remove_light_wound(state, D.Side.FRIENDLY)
		1:
			_log(state, "Evento Friendly 1: via tutti i Low Ammo Friendly")
			_clear_low_ammo(state, D.Side.FRIENDLY)
		2:
			_log(state, "Evento Friendly 2 (Lucky Strike): pesco una carta extra")
			state.friendly_hand.append(state.draw_friendly_card())
		3, 4, 5:
			_log(state, "Evento Friendly %d: fuoco di mortaio/illuminazione amico (segnalini TODO)" % roll)
		6:
			_log(state, "Evento Friendly 6: artiglieria 105mm amica (segnalini TODO)")
		7:
			_log(state, "Evento Friendly 7 (Come on men!): +1 morale entro LDR di un leader")
			_morale_near_leader(state)
		8:
			_log(state, "Evento Friendly 8: rivelo un nemico nascosto")
			_reveal_one_hidden(state)
		9:
			_log(state, "Evento Friendly 9 (Uh-oh): tiro sulla tabella Nemica")
			resolve(state, "enemy", depth + 1)


static func _enemy(state: GameState, roll: int, depth: int) -> void:
	match roll:
		0:
			_log(state, "Evento Enemy 0: tiro sulla tabella Amica")
			resolve(state, "friendly", depth + 1)
		1:
			_log(state, "Evento Enemy 1: via tutti i Low Ammo nemici")
			_clear_low_ammo(state, D.Side.ENEMY)
		2:
			_log(state, "Evento Enemy 2 (Second Thoughts): cambio un ordine nemico")
			_rechange_enemy_order(state)
		3, 4, 5:
			_log(state, "Evento Enemy %d: mortaio/illuminazione nemica (segnalini TODO)" % roll)
		6:
			_log(state, "Evento Enemy 6: artiglieria 105mm nemica (segnalini TODO)")
		7:
			_log(state, "Evento Enemy 7: rinforzi nemici (bordo 01.01-01.05)")
			_enemy_reinforce(state, ["1,1", "1,2", "1,3", "1,4", "1,5"])
		8:
			_log(state, "Evento Enemy 8: rinforzi nemici (bordo 01.13-01.17)")
			_enemy_reinforce(state, ["1,13", "1,14", "1,15", "1,16", "1,17"])
		9:
			_log(state, "Evento Enemy 9: rimuovo 1 Light Wound da un nemico")
			_remove_light_wound(state, D.Side.ENEMY)


# ----------------------------------------------------------- effetti

static func _clear_low_ammo(state: GameState, side: int) -> void:
	for c in state.characters:
		if c.side == side and not c.is_dead():
			c.low_ammo = false
			c.no_ammo = false


static func _remove_light_wound(state: GameState, side: int) -> void:
	for c in state.characters:
		if c.side == side and not c.is_dead() and D.Wound.LIGHT in c.wounds:
			c.wounds.erase(D.Wound.LIGHT)
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
			_log(state, "  rivelato: %s in %02d.%02d" % [
				c.display_name, c.position.x, c.position.y])
			return


static func _rechange_enemy_order(state: GameState) -> void:
	# Nemico vivo piu' vicino a un Friendly: nuovo ordine dalla sua carta.
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


static func _enemy_reinforce(state: GameState, hexes: Array) -> void:
	for hexkey in hexes:
		if state.enemy_reserve.is_empty():
			return
		Scenario._place_enemy(state, state.enemy_reserve.pop_front(), hexkey)


static func _log(state: GameState, msg: String) -> void:
	state.log_event(msg)
