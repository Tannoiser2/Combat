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
	# TODO: per ogni Enemy Alerted, pescare Enemy Card e fare il LOOKUP
	#       morale x cover -> Order. E' il "cervello" dell'AI: una tabella,
	#       non una decisione. Da implementare per primo.
	pass


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
	#       rimuovere ordini; reset; check vittoria.
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
