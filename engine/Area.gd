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

enum Type { GRENADE, SMOKE, MORTAR_60, MORTAR_81, ARTILLERY_105, ILLUM, C4,
	FIRE, RAGING_FIRE }

const NAMES := {
	Type.GRENADE: "Granata", Type.SMOKE: "Fumo",
	Type.MORTAR_60: "Mortaio 60mm", Type.MORTAR_81: "Mortaio 81mm",
	Type.ARTILLERY_105: "Artiglieria 105mm", Type.ILLUM: "Illuminazione",
	Type.C4: "Carica C4", Type.FIRE: "Incendio", Type.RAGING_FIRE: "Incendio furioso",
}

# Incendi (Rule 29): tabelle d10 <= valore, solo per il terreno infiammabile.
# Kindling = accensione dopo artiglieria/mortaio; Growth = un incendio
# divampa (furioso); Spread = un furioso si propaga sottovento.
const KINDLING := {
	D.Terrain.TREES: 2, D.Terrain.BUILDING: 1, D.Terrain.HEDGEROW: 3,
	D.Terrain.BOCAGE: 2, D.Terrain.LONG_GRASS: 3, D.Terrain.ORCHARD: 2, D.Terrain.LOGS: 2,
}
const FIRE_GROWTH := {
	D.Terrain.TREES: 2, D.Terrain.BUILDING: 2, D.Terrain.HEDGEROW: 3,
	D.Terrain.BOCAGE: 3, D.Terrain.LONG_GRASS: 4, D.Terrain.ORCHARD: 3, D.Terrain.LOGS: 2,
}
const FIRE_SPREAD := {
	D.Terrain.TREES: 2, D.Terrain.BUILDING: 1, D.Terrain.HEDGEROW: 2,
	D.Terrain.BOCAGE: 2, D.Terrain.LONG_GRASS: 3, D.Terrain.ORCHARD: 3, D.Terrain.LOGS: 1,
}


# Il terreno puo' prendere fuoco (Rule 29.2)?
static func burnable(terrain: int) -> bool:
	return KINDLING.has(terrain)


# Tipo di incendio nell'hex (Type.FIRE / Type.RAGING_FIRE) o -1.
static func fire_at(state: GameState, hex: Vector2i) -> int:
	for m in state.area_markers:
		if m["hex"] == hex and m["type"] in [Type.FIRE, Type.RAGING_FIRE]:
			return m["type"]
	return -1


static func _terrain_at(state: GameState, hex: Vector2i) -> int:
	var h := state.hex_at(hex.x, hex.y)
	return h.terrain if h != null else D.Terrain.OPEN_LEVEL_0

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


# Penalita' al WS/LOS (numero di fumo, negativo) di fumo e incendi nell'hex.
# Fumo pieno -4 / dissolvenza -2; Incendio -3, Incendio furioso -4 (Rule 29.2):
# il fuoco genera fumo, e in questo modello l'hex stesso lo emette.
static func smoke_penalty(state: GameState, hex: Vector2i) -> int:
	var p := 0
	for m in state.area_markers:
		if m["hex"] != hex:
			continue
		match m["type"]:
			Type.SMOKE: p -= (4 if m["turns_left"] >= 2 else 2)
			Type.FIRE: p -= 3
			Type.RAGING_FIRE: p -= 4
	return p


# L'hex e' illuminato (scenari notturni)?
static func illuminated(state: GameState, hex: Vector2i) -> bool:
	for m in state.area_markers:
		if m["type"] == Type.ILLUM \
				and Spotting.hex_distance(m["hex"], hex) <= 3:
			return true
	return false


# End Phase: incendi, esplosioni, dissolvenza fumo, rimozione.
static func end_phase(state: GameState) -> void:
	var last_turn := state.turn >= state.max_turns
	# Incendi gia' presenti (Rule 29): danno, crescita, propagazione.
	_process_fires(state)
	var keep: Array = []
	for m in state.area_markers:
		var t: int = m["type"]
		if t in [Type.FIRE, Type.RAGING_FIRE]:
			keep.append(m)  # gestiti da _process_fires; restano finche' non spenti
			continue
		if t in [Type.GRENADE, Type.MORTAR_60, Type.MORTAR_81, Type.ARTILLERY_105]:
			_explode(state, m)
			# L'artiglieria/mortaio puo' accendere il terreno (Rule 29.1).
			if t != Type.GRENADE:
				_try_kindle(state, m["hex"], keep)
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


# Incendi del turno: danno a chi e' nelle fiamme, crescita (incendio ->
# furioso, o spento col 9), propagazione del furioso sottovento (Rule 29).
# Non si processa il fuoco nel turno in cui e' nato.
static func _process_fires(state: GameState) -> void:
	var new_fires: Array = []
	var heavy_rain := state.weather == Weather.Type.HEAVY_RAIN
	for m in state.area_markers:
		if m["type"] not in [Type.FIRE, Type.RAGING_FIRE]:
			continue
		if int(m["placed_turn"]) >= state.turn:
			continue  # appena nato: niente effetti questo turno
		var hex: Vector2i = m["hex"]
		var terrain := _terrain_at(state, hex)
		# Danno: chi resta nell'hex pesca una ferita (due se furioso).
		var draws := 2 if m["type"] == Type.RAGING_FIRE else 1
		for c in state.characters:
			if c.is_dead() or c.position != hex:
				continue
			state.log_event("%s e' tra le fiamme in %02d.%02d!" % [c.display_name, hex.x, hex.y])
			for i in range(draws):
				if not c.is_dead():
					Fire._resolve_wound(state, null, c)
		if m["type"] == Type.FIRE:
			var roll := Checks.roll_d10(state.rng)
			if roll == 9:
				m["extinguished"] = true
				state.log_event("L'incendio in %02d.%02d si spegne" % [hex.x, hex.y])
			elif roll <= int(FIRE_GROWTH.get(terrain, 0)):
				m["type"] = Type.RAGING_FIRE
				state.log_event("L'incendio in %02d.%02d divampa furioso!" % [hex.x, hex.y])
		elif state.wind != Vector3i.ZERO:
			# Furioso: prova a propagarsi all'hex sottovento se infiammabile.
			var dest := Move.from_cube(Move.to_cube(hex) + state.wind)
			var dt := _terrain_at(state, dest)
			if state.map.has(GameState.hex_key(dest.x, dest.y)) and burnable(dt) \
					and fire_at(state, dest) < 0:
				var roll2 := Checks.roll_d10(state.rng) + (1 if heavy_rain else 0)
				if roll2 <= int(FIRE_SPREAD.get(dt, 0)):
					new_fires.append({"type": Type.FIRE, "hex": dest,
						"placed_turn": state.turn, "turns_left": 99})
					state.log_event("L'incendio si propaga a %02d.%02d!" % [dest.x, dest.y])
	# Rimuovi gli spenti, aggiungi i propagati.
	var kept: Array = []
	for m in state.area_markers:
		if not m.get("extinguished", false):
			kept.append(m)
	kept.append_array(new_fires)
	state.area_markers = kept


# Tentativo di accensione di un hex colpito da artiglieria/mortaio (Rule 29.1):
# d10 (+1 con pioggia battente) <= valore Kindling del terreno -> Incendio.
static func _try_kindle(state: GameState, hex: Vector2i, into: Array) -> void:
	var terrain := _terrain_at(state, hex)
	if not burnable(terrain) or fire_at(state, hex) >= 0:
		return
	var roll := Checks.roll_d10(state.rng) + (1 if state.weather == Weather.Type.HEAVY_RAIN else 0)
	if roll <= int(KINDLING.get(terrain, 0)):
		into.append({"type": Type.FIRE, "hex": hex,
			"placed_turn": state.turn, "turns_left": 99})
		state.log_event("Un incendio divampa in %02d.%02d!" % [hex.x, hex.y])


static func _explode(state: GameState, m: Dictionary) -> void:
	var hex: Vector2i = m["hex"]
	var pw: Array = POWER[m["type"]]
	state.log_event("%s esplode in %02d.%02d!" % [NAMES[m["type"]], hex.x, hex.y])
	state.booms.append({"hex": hex, "type": m["type"]})
	Replay.boom(state, hex, m["type"])
	state.audio_events.append({"type": "boom", "area_type": m["type"], "hex": hex})
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
	var dead_before := c.is_dead()
	# Esplosione: nessun tiratore (firer null), ma Tough del bersaglio vale.
	Fire._resolve_wound(state, null, c)
	if c.is_dead() and not dead_before:
		state.audio_events.append({"type": "scream", "hex": c.position})
		Replay.sfx(state, "scream")
