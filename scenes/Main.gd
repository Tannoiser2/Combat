## Scena principale: banco di prova del motore.
## Costruisce una mini-partita, mostra la mappa (MapView) e fa avanzare
## un turno al secondo stampando lo stato in console.
extends Node

const TURN_SECONDS := 1.5

var state: GameState
var map_view: MapView
var turn_timer: Timer


func _ready() -> void:
	print("=== Combat! - test del motore ===")

	state = _make_tiny_state()
	print("Mappa: %d hex" % state.map.size())
	print("Personaggi: %d" % state.characters.size())
	_print_morale_check()

	map_view = MapView.new()
	map_view.state = state
	map_view.position = Vector2(120, 100)
	add_child(map_view)

	print("\n--- Ciclo dei turni (uno ogni %.1fs) ---" % TURN_SECONDS)
	turn_timer = Timer.new()
	turn_timer.wait_time = TURN_SECONDS
	turn_timer.timeout.connect(_run_one_turn)
	add_child(turn_timer)
	turn_timer.start()


# Il turno avanza in due battute del timer: prima le fasi delle carte e
# degli ordini (cosi' gli ordini restano visibili sulla mappa per un
# tick), poi Action e End Phase. run_turn resta la via "tutta d'un fiato".
var _mid_turn := false


func _run_one_turn() -> void:
	if state.game_over:
		print("Partita finita al turno %d." % state.turn)
		turn_timer.stop()
		return
	if not _mid_turn:
		TurnSequence.friendly_card_phase(state)
		_print_friendly_card(state)
		TurnSequence.friendly_order_phase(state)
		TurnSequence.enemy_order_phase(state)
		_print_enemy_orders(state)
		print("    Initiative Track: %s" % " -> ".join(state.initiative_order))
	else:
		TurnSequence.action_phase(state)
		TurnSequence.end_phase(state)
		print("  fine turno -> turno %d, game_over: %s" % [state.turn, state.game_over])
	_mid_turn = not _mid_turn
	map_view.queue_redraw()
	_maybe_screenshot()


# Hook di debug per verifiche senza monitor (CI/cloud): se la variabile
# d'ambiente COMBAT_SCREENSHOT e' impostata, salva li' uno screenshot
# del viewport a ogni turno.
func _maybe_screenshot() -> void:
	var path := OS.get_environment("COMBAT_SCREENSHOT")
	if path.is_empty():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


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


# Stampa la Friendly Card giocata sull'Initiative Track.
func _print_friendly_card(state: GameState) -> void:
	var serial := state.friendly_card_played
	print("  [T%d] Friendly gioca la carta %d: \"%s\" (Able %d, Baker %d, Charlie %d)" % [
		state.turn, serial, FriendlyCards.title_of(serial),
		FriendlyCards.initiative_for(serial, "Able"),
		FriendlyCards.initiative_for(serial, "Baker"),
		FriendlyCards.initiative_for(serial, "Charlie"),
	])


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
