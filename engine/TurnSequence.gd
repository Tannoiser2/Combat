## La macchina a stati della sequenza di gioco (Rule 4.0).
## Un turno = 5 step. Lo step 4 (Action) si svolge in 4 Impulse,
## e in ogni Impulse i Team agiscono in ordine di iniziativa.
##
## OSSATURA: la struttura c'e' tutta, i sottosistemi (firing, morale, LOS...)
## si innestano nei punti marcati TODO. Cosi' il gioco e' sempre eseguibile
## e si arricchisce a strati.
class_name TurnSequence
extends RefCounted


# Step 1 - Friendly Card Phase (Rule 5.0)
static func friendly_card_phase(state: GameState) -> void:
	# TODO: pescare carta se mano vuota; aggiungere carte da Plan;
	#       scartare oltre 5; giocare una carta sull'Initiative Track;
	#       risolvere eventuali Event.
	pass


# Step 2 - Friendly Order Phase (Rule 7.0)
static func friendly_order_phase(state: GameState) -> void:
	# TODO: il giocatore assegna un Order a ogni Friendly Character.
	pass


# Step 3 - Enemy Card and Order Phase (Rule 9.0)
static func enemy_order_phase(state: GameState) -> void:
	# SOP step 3a: una carta per ogni Enemy Team con almeno un Alerted.
	state.enemy_cards_in_play.clear()
	for team in state.enemy_teams_with_alerted():
		var serial := state.draw_enemy_card()
		state.enemy_cards_in_play[team] = serial
		# SOP step 3b: ordini a tutti gli Alerted del team, ciascuno
		# secondo il proprio morale e la propria copertura.
		for c in state.characters_of_team(team):
			if c.alerted and not c.is_dead():
				_assign_enemy_order(state, c, serial)
	# TODO SOP step 3c: completare l'Initiative Order Track con i valori
	#      di iniziativa delle carte (il sistema di iniziativa non c'e'
	#      ancora; i seriali pescati restano in state.enemy_cards_in_play).


static func _assign_enemy_order(state: GameState, c: Character, serial: int) -> void:
	if not EnemyCards.has_table_row(c.morale):
		# Berserk e Rout non ricevono ordini dalla carta: agiscono
		# d'istinto (TODO Rule 17: carica obbligata / fuga, con il
		# movimento di EnemyCards.berserk_move/rout_move).
		c.clear_order()
		return
	var hex := state.hex_at(c.position.x, c.position.y)
	var in_cover := hex != null and Domain.terrain_gives_cover(hex.terrain)
	var entry := EnemyCards.lookup(serial, c.morale, in_cover)
	c.set_order(entry["order"], entry["move"], entry["grenade"], entry["charge"])


# Step 4 - Action Phase: 4 impulsi (Rule 4.0 step 4)
static func action_phase(state: GameState) -> void:
	for imp in range(1, 5):
		state.impulse = imp
		for team in state.initiative_order:
			_activate_team(state, team)


static func _activate_team(state: GameState, team: String) -> void:
	# Rule 10.0: i nemici si attivano dall'alto della mappa al basso;
	# i friendly nell'ordine scelto dal giocatore. Ordine base per ora.
	for c in state.characters_of_team(team):
		_activate_character(state, c)


static func _activate_character(state: GameState, c: Character) -> void:
	# TODO: eseguire l'azione dell'impulse corrente secondo l'Order del
	#       personaggio (move/fire/melee...), fare Spotting Checks,
	#       gestire Duck Back. A strati.
	pass


# Step 5 - End Phase (Rule 4.0 step 5)
static func end_phase(state: GameState) -> void:
	# TODO: granate esplodono; medic; plan draw; smoke; alert dei waiting;
	#       reset; check vittoria.
	# SOP step 5d: rimuovere tutti gli ordini.
	for c in state.characters:
		c.clear_order()
	state.enemy_cards_in_play.clear()
	state.impulse = 1
	state.turn += 1
	if state.turn > state.max_turns:
		state.game_over = true


# Un turno completo: i 5 step in sequenza.
static func run_turn(state: GameState) -> void:
	friendly_card_phase(state)
	friendly_order_phase(state)
	enemy_order_phase(state)
	action_phase(state)
	end_phase(state)
