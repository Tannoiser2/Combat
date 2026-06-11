## Scena principale: per ora fa da banco di prova del motore.
## Costruisce una mini-partita e fa girare i turni stampando lo stato.
## Quando il motore reggera', qui sotto costruiremo la UI vera (griglia,
## segnalini, pannelli). Per ora dimostra che le fondamenta girano.
extends Node


func _ready() -> void:
	print("=== Combat! - test del motore ===")

	var state := _make_tiny_state()
	print("Mappa: %d hex" % state.map.size())
	print("Personaggi: %d" % state.characters.size())
	_print_morale_check()

	print("\n--- Ciclo dei turni ---")
	print("Turno iniziale: %d, game_over: %s" % [state.turn, state.game_over])
	while not state.game_over:
		# Step espliciti invece di run_turn: cosi' possiamo stampare gli
		# ordini nemici prima che la End Phase li rimuova.
		TurnSequence.friendly_card_phase(state)
		TurnSequence.friendly_order_phase(state)
		TurnSequence.enemy_order_phase(state)
		_print_enemy_orders(state)
		TurnSequence.action_phase(state)
		TurnSequence.end_phase(state)
		print("  fine turno -> turno %d, game_over: %s" % [state.turn, state.game_over])
	print("Partita finita al turno %d." % state.turn)


# Costruisce una mini-partita di prova: griglia 3x3, due personaggi.
func _make_tiny_state() -> GameState:
	var state := GameState.new()
	state.max_turns = 3
	state.rng.seed = hash("combat-test")  # partita riproducibile

	# Mini-mappa 3x3, Open Level 0 con un bosco in (2,2)
	for col in range(3):
		for row in range(3):
			var key := GameState.hex_key(col, row)
			state.map[key] = GameState.MapHex.new(Domain.Terrain.OPEN_LEVEL_0, 0)
	state.map[GameState.hex_key(2, 2)] = GameState.MapHex.new(Domain.Terrain.TREES, 0)

	# Sgt Taylor (Friendly, Able)
	var taylor := Character.new("taylor", "Sgt Taylor", Domain.Side.FRIENDLY, "Able")
	taylor.troop_quality = 6
	taylor.leadership = 3
	taylor.weapon_skills = {"SMG": 7}
	taylor.position = Vector2i(0, 0)
	taylor.morale = Domain.Morale.NORMAL
	state.characters.append(taylor)

	# Soldat Jung (Enemy, Red): nel bosco -> In Cover
	var jung := Character.new("jung", "Soldat Jung", Domain.Side.ENEMY, "Red")
	jung.troop_quality = 4
	jung.weapon_skills = {"Rifle": 3}
	jung.position = Vector2i(2, 2)
	jung.morale = Domain.Morale.NORMAL
	jung.alerted = true
	state.characters.append(jung)

	# Gefreiter Braun (Enemy, Red): allo scoperto e Shaken
	var braun := Character.new("braun", "Gefr Braun", Domain.Side.ENEMY, "Red")
	braun.troop_quality = 5
	braun.weapon_skills = {"Rifle": 4}
	braun.position = Vector2i(2, 0)
	braun.morale = Domain.Morale.SHAKEN
	braun.alerted = true
	state.characters.append(braun)

	state.initiative_order = ["Able", "Red"]
	return state


# Stampa la carta pescata e gli ordini assegnati nella Enemy Order Phase.
func _print_enemy_orders(state: GameState) -> void:
	for team in state.enemy_cards_in_play:
		var serial: int = state.enemy_cards_in_play[team]
		print("  [T%d] Team %s pesca la carta %d (iniziativa %d)" % [
			state.turn, team, serial, EnemyCards.initiative_of(serial)
		])
		for c in state.characters_of_team(team):
			if not c.has_order:
				continue
			var hex := state.hex_at(c.position.x, c.position.y)
			var cover := "In Cover" if Domain.terrain_gives_cover(hex.terrain) else "In Open"
			var extra := "" if c.order_move.is_empty() else " " + c.order_move
			if c.order_grenade:
				extra += " +Grenade"
			if c.order_charge:
				extra += " +Charge"
			print("    %s (%s, %s) -> %s%s" % [
				c.display_name, Domain.MORALE_NAMES[c.morale], cover,
				Domain.ORDER_NAMES[c.order], extra
			])


# Verifica veloce che l'ordinamento del morale e i helper funzionino.
func _print_morale_check() -> void:
	var berserk_lvl := int(Domain.Morale.BERSERK)
	var rout_lvl := int(Domain.Morale.ROUT)
	print("Morale: Berserk=%d (alto), Rout=%d (basso)" % [berserk_lvl, rout_lvl])

	# Un Normal che sale di 1 diventa Bold; che scende di 1 diventa Cautious.
	var up := Domain.raise_morale(Domain.Morale.NORMAL, 1)
	var down := Domain.lower_morale(Domain.Morale.NORMAL, 1)
	print("Normal +1 -> %s, Normal -1 -> %s" % [
		Domain.MORALE_NAMES[up], Domain.MORALE_NAMES[down]
	])
