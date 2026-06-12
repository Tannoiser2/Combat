## Segnalini d'area sugli hex: granate, fumo, mortai, artiglieria,
## illuminazione (Rules 14/15 + Event Tables + carte armi).
##
## Ogni marker e' {type, hex, turns_left, placed_turn}. Vive in
## state.area_markers. Il ciclo di vita e' gestito in End Phase:
## - GRENADE/MORTAR/ARTILLERY piazzati in un turno ESPLODONO nella End
##   Phase dello stesso turno (attacco su chi sta nell'hex), poi via.
## - SMOKE degrada: pieno -> fading -> rimosso.
## - ILLUM dura il turno e sparisce.
##
## Scatter: 1D6 in una delle 6 direzioni (deviazione di 1 hex; i mortai
## del libro usano scatter 1D6-1/-2: qui si applica la probabilita' di
## restare nel punto).
##
## Valori d'attacco (dalle schede armi): Damage X/Y = attacco X
## nell'hex, Y negli adiacenti (Frag). Si risolve come un TQC sul
## bersaglio modificato: tira 1D10 <= TQ - potenza -> illeso, altrimenti
## pesca ferita. APPROSSIMATO finche' non trascriviamo la regola esatta.
class_name Area
extends RefCounted

const D := preload("res://engine/Domain.gd")

enum Type { GRENADE, SMOKE, MORTAR_60, MORTAR_81, ARTILLERY_105, ILLUM, C4 }

const NAMES := {
	Type.GRENADE: "Granata", Type.SMOKE: "Fumo",
	Type.MORTAR_60: "Mortaio 60mm", Type.MORTAR_81: "Mortaio 81mm",
	Type.ARTILLERY_105: "Artiglieria 105mm", Type.ILLUM: "Illuminazione",
	Type.C4: "Carica C4",
}

# Potenza: [danno nell'hex, danno negli adiacenti]
const POWER := {
	Type.GRENADE: [3, 1],          # US MkII / Stielhandgranate: Damage 3/1
	Type.MORTAR_60: [3, 2],
	Type.MORTAR_81: [4, 2],
	Type.ARTILLERY_105: [5, 3],
	Type.C4: [3, 3],               # intro3 SR15: Blast 3 / Frag 3
}


# C4 (intro3): resta nell'hex e a ogni End Phase esplode con 0-2 su 1D10
# (sempre, a fine partita). Distrugge il cannone se nel suo hex.
static func place_c4(state: GameState, hex: Vector2i) -> void:
	state.area_markers.append({
		"type": Type.C4, "hex": hex, "placed_turn": state.turn, "turns_left": 99,
	})


# Piazza un marker con scatter 1D6: 1-2 resta, altrimenti devia di 1 hex
# in direzione casuale.
static func place_with_scatter(state: GameState, type: int, hex: Vector2i) -> Vector2i:
	var final := hex
	if state.rng.randi_range(1, 6) > 2:
		var dirs := Move.CUBE_DIRS
		var dir: Vector3i = dirs[state.rng.randi_range(0, 5)]
		var dev := Move.from_cube(Move.to_cube(hex) + dir)
		if state.map.has(GameState.hex_key(dev.x, dev.y)):
			final = dev
	state.area_markers.append({
		"type": type, "hex": final, "placed_turn": state.turn,
		"turns_left": 2 if type == Type.SMOKE else 1,
	})
	state.log_event("%s in %02d.%02d%s" % [NAMES[type], final.x, final.y,
		"" if final == hex else " (deviato)"])
	return final


# Fumo pieno/in dissolvenza in un hex (per i modificatori al fuoco).
# Ritorna 0 = niente, 2 = fumo pieno (-4), 1 = fading (-2).
static func smoke_level(state: GameState, hex: Vector2i) -> int:
	var level := 0
	for m in state.area_markers:
		if m["type"] == Type.SMOKE and m["hex"] == hex:
			level = maxi(level, m["turns_left"])
	return level


# L'hex e' illuminato (scenari notturni)?
static func illuminated(state: GameState, hex: Vector2i) -> bool:
	for m in state.area_markers:
		if m["type"] == Type.ILLUM \
				and Spotting.hex_distance(m["hex"], hex) <= 3:
			return true
	return false


# End Phase: esplosioni, dissolvenza fumo, rimozione.
static func end_phase(state: GameState) -> void:
	var last_turn := state.turn >= state.max_turns
	var keep: Array = []
	for m in state.area_markers:
		var t: int = m["type"]
		if t in [Type.GRENADE, Type.MORTAR_60, Type.MORTAR_81, Type.ARTILLERY_105]:
			_explode(state, m)
			continue  # esploso: via
		if t == Type.C4:
			# Esplode con 0-2 su 1D10 (non nel turno in cui e' piazzata),
			# o automaticamente a fine partita.
			var armed: bool = m["placed_turn"] < state.turn
			if last_turn or (armed and Checks.roll_d10(state.rng) <= 2):
				_explode(state, m)
				continue
			keep.append(m)
			continue
		m["turns_left"] -= 1
		if m["turns_left"] > 0:
			# Il fumo che resta deriva di 1 hex col vento.
			if t == Type.SMOKE and state.wind != Vector3i.ZERO:
				var dest := Move.from_cube(Move.to_cube(m["hex"]) + state.wind)
				if state.map.has(GameState.hex_key(dest.x, dest.y)):
					state.log_event("Il fumo deriva col vento: %02d.%02d -> %02d.%02d" % [
						m["hex"].x, m["hex"].y, dest.x, dest.y])
					m["hex"] = dest
			keep.append(m)
		else:
			state.log_event("%s in %02d.%02d si dissolve" % [
				NAMES[t], m["hex"].x, m["hex"].y])
	state.area_markers = keep


static func _explode(state: GameState, m: Dictionary) -> void:
	var hex: Vector2i = m["hex"]
	var pw: Array = POWER[m["type"]]
	state.log_event("%s esplode in %02d.%02d!" % [NAMES[m["type"]], hex.x, hex.y])
	state.booms.append({"hex": hex, "type": m["type"]})
	Replay.boom(state, hex, m["type"])
	# Cannoni (intro3/s9): la C4 nell'hex di un pezzo lo distrugge.
	if m["type"] == Type.C4 and not state.scenario_id.is_empty():
		var key := "%d,%d" % [hex.x, hex.y]
		var guns: Array = Scenario.SCENARIOS[state.scenario_id].get("gun_hexes", [])
		if key in guns and not key in state.guns_destroyed:
			state.guns_destroyed.append(key)
			state.log_event("  CANNONE DISTRUTTO! (%d/%d)" % [
				state.guns_destroyed.size(), guns.size()])
	for c in state.characters:
		if c.is_dead():
			continue
		var dist := Spotting.hex_distance(c.position, hex)
		if dist > 1:
			continue
		var power: int = pw[0] if dist == 0 else pw[1]
		_blast_check(state, c, power)


# Esplosione su un personaggio: 1D10 <= TQ - potenza -> illeso, altrimenti
# pesca ferita (APPROSSIMATO).
static func _blast_check(state: GameState, c: Character, power: int) -> void:
	if c.is_dummy:
		c.removed = true
		state.log_event("  un'esca salta in aria")
		return
	var roll := Checks.roll_d10(state.rng)
	var thr := Checks.effective_tq(c) - power
	if roll <= thr:
		state.log_event("  %s si salva (tira %d <= %d)" % [c.display_name, roll, thr])
		return
	state.log_event("  %s e' investito dall'esplosione" % c.display_name)
	c.known = true
	Fire._resolve_wound(state, c)
