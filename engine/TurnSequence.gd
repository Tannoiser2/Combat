## La macchina a stati della sequenza di gioco (Rule 4.0).
## Un turno = 5 step. Lo step 4 (Action) si svolge in 4 Impulse,
## e in ogni Impulse i Team agiscono in ordine di iniziativa.
##
## OSSATURA: la struttura c'e' tutta, i sottosistemi (firing, morale, LOS...)
## si innestano nei punti marcati TODO. Cosi' il gioco e' sempre eseguibile
## e si arricchisce a strati.
class_name TurnSequence
extends RefCounted


# Step 1 - Friendly Card Phase (Rule 5.0), in due meta' cosi' la UI puo'
# mostrare la mano e far scegliere il giocatore tra prepare e play.

# SOP 1a-1c: pesca se la mano e' vuota, scarta oltre il limite.
static func friendly_card_phase_prepare(state: GameState) -> void:
	if state.friendly_hand.is_empty():
		state.friendly_hand.append(state.draw_friendly_card())
	# TODO SOP 1b: aggiungere le carte messe da parte da un Plan riuscito.
	# SOP 1c: scelta del giocatore; policy provvisoria: si scartano le prime.
	while state.friendly_hand.size() > GameState.HAND_LIMIT:
		state.friendly_discard.append(state.friendly_hand.pop_front())


# SOP 1d-1e: gioca la carta scelta sull'Initiative Track.
static func friendly_card_play(state: GameState, index: int) -> void:
	state.friendly_card_played = state.friendly_hand.pop_at(index)
	state.log_event('Friendly gioca la carta %d: "%s"' % [
		state.friendly_card_played,
		FriendlyCards.title_of(state.friendly_card_played),
	])
	# SOP 1e: se la carta giocata e' un Event, si risolve e si rimpiazza.
	while FriendlyCards.kind_of(state.friendly_card_played) == FriendlyCards.Kind.EVENT:
		# TODO: tirare 1D10 sulla Event Table dello scenario (gli eventi
		#       non sono ancora implementati).
		# La carta stessa dice: pesca un rimpiazzo, poi rimescola mazzo
		# e scarti insieme (la carta Event torna nel giro).
		state.log_event("Carta Event! Pesco un rimpiazzo e rimescolo (evento TODO)")
		state.friendly_discard.append(state.friendly_card_played)
		state.friendly_card_played = state.draw_friendly_card()
		state.reshuffle_friendly_deck()


# Fase completa senza UI (banco di prova): gioca la prima carta.
static func friendly_card_phase(state: GameState, play_index: int = 0) -> void:
	friendly_card_phase_prepare(state)
	friendly_card_play(state, play_index)


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
		state.log_event("Team %s pesca la Enemy Card %d (iniziativa %d)" % [
			team, serial, EnemyCards.initiative_of(serial)])
		# SOP step 3b: ordini a tutti gli Alerted del team, ciascuno
		# secondo il proprio morale e la propria copertura.
		for c in state.characters_of_team(team):
			if c.alerted and not c.is_dead():
				_assign_enemy_order(state, c, serial)
	# SOP step 3c: completare l'Initiative Order Track.
	_update_initiative_order(state)


# L'Initiative Track: ogni Team friendly prende il valore della Friendly
# Card giocata, ogni Team nemico attivo quello della sua Enemy Card.
# Si agisce dal valore piu' basso al piu' alto (friendly pari, enemy
# dispari: mai pareggi).
static func _update_initiative_order(state: GameState) -> void:
	var entries: Array = []  # coppie [iniziativa, team]
	if state.friendly_card_played >= 0:
		for team in state.friendly_teams():
			entries.append([FriendlyCards.initiative_for(state.friendly_card_played, team), team])
	for team in state.enemy_cards_in_play:
		entries.append([EnemyCards.initiative_of(state.enemy_cards_in_play[team]), team])
	entries.sort()
	state.initiative_order.clear()
	for e in entries:
		state.initiative_order.append(e[1])


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
	var extra := "" if c.order_move.is_empty() else " " + c.order_move
	if entry["grenade"]:
		extra += " +Grenade"
	if entry["charge"]:
		extra += " +Charge"
	state.log_event("%s (%s, %s) -> %s%s" % [
		c.display_name, Domain.MORALE_NAMES[c.morale],
		"In Cover" if in_cover else "In Open",
		Domain.ORDER_NAMES[c.order], extra,
	])


# Step 4 - Action Phase: 4 impulsi (Rule 4.0 step 4)
static func action_phase(state: GameState) -> void:
	for imp in range(1, 5):
		run_impulse(state, imp)


# Un singolo impulse: i Team agiscono in ordine di iniziativa.
static func run_impulse(state: GameState, imp: int) -> void:
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
	#       gestire Duck Back. A strati. Primo strato: Rally.
	if c.is_dead() or not c.has_order:
		return
	if c.order == Domain.Order.RALLY and state.impulse == 1:
		var res := Checks.rally_check(c, state.rng)
		state.log_event("%s tenta Rally: tira %d (TQ %d) -> %s%s" % [
			c.display_name, res["roll"], Checks.effective_tq(c),
			Domain.MORALE_NAMES[res["after"]],
			"" if res["delta"] != 0 else " (nessun effetto)",
		])


# Step 5 - End Phase (Rule 4.0 step 5)
static func end_phase(state: GameState) -> void:
	# TODO: granate esplodono; medic; plan draw; smoke; alert dei waiting;
	#       reset; check vittoria.
	# SOP step 5d: rimuovere tutti gli ordini.
	for c in state.characters:
		c.clear_order()
	state.enemy_cards_in_play.clear()
	# La Friendly Card giocata va negli scarti.
	if state.friendly_card_played >= 0:
		state.friendly_discard.append(state.friendly_card_played)
		state.friendly_card_played = -1
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
