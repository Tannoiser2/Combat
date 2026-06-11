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
		TurnSequence.run_turn(state)
		print("  dopo run_turn -> turno %d, game_over: %s" % [state.turn, state.game_over])
	print("Partita finita al turno %d." % state.turn)


# Costruisce una mini-partita di prova: griglia 3x3, due personaggi.
func _make_tiny_state() -> GameState:
	var state := GameState.new()
	state.max_turns = 3

	# Mini-mappa 3x3, tutta Open Level 0
	for col in range(3):
		for row in range(3):
			var key := GameState.hex_key(col, row)
			state.map[key] = GameState.MapHex.new(Domain.Terrain.OPEN_LEVEL_0, 0)

	# Sgt Taylor (Friendly, Able)
	var taylor := Character.new("taylor", "Sgt Taylor", Domain.Side.FRIENDLY, "Able")
	taylor.troop_quality = 6
	taylor.leadership = 3
	taylor.weapon_skills = {"SMG": 7}
	taylor.position = Vector2i(0, 0)
	taylor.morale = Domain.Morale.NORMAL
	state.characters.append(taylor)

	# Soldat Jung (Enemy, Red)
	var jung := Character.new("jung", "Soldat Jung", Domain.Side.ENEMY, "Red")
	jung.troop_quality = 4
	jung.weapon_skills = {"Rifle": 3}
	jung.position = Vector2i(2, 2)
	jung.morale = Domain.Morale.NORMAL
	jung.alerted = true
	state.characters.append(jung)

	state.initiative_order = ["Able", "Red"]
	return state


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
