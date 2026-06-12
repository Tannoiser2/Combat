## Registrazione della partita per il replay (solo dati, niente grafica).
##
## Il motore registra un "frame" per ogni impulse in cui succede qualcosa:
## snapshot delle unita' a inizio impulse, percorsi di movimento passo per
## passo, colpi sparati ed esplosioni. La UI riproduce i frame animando
## tutte le azioni dell'impulse IN SIMULTANEA (come avvengono nel gioco
## da tavolo), turno per turno.
##
## I frame vivono in state.replay; le unita' sono identificate dall'indice
## in state.characters (stabile: i personaggi non vengono mai rimossi).
class_name Replay
extends RefCounted


# Il frame corrente per (turn, impulse); ne crea uno nuovo al primo
# evento registrato dell'impulse.
static func _frame(state: GameState) -> Dictionary:
	if state.replay.is_empty() \
			or state.replay.back()["turn"] != state.turn \
			or state.replay.back()["impulse"] != state.impulse:
		state.replay.append({
			"turn": state.turn, "impulse": state.impulse,
			"units": _snapshot(state),
			"moves": {},   # idx -> [Vector2i, ...] (percorso, primo = partenza)
			"shots": [],   # come state.shots
			"booms": [],   # esplosioni: {hex, type}
			"sfx": [],     # suoni extra (mischia, urla): chiavi di Main._sfx
		})
	return state.replay.back()


# Fotografia delle unita' vive: quanto serve alla UI per disegnarle.
static func _snapshot(state: GameState) -> Dictionary:
	var units := {}
	for i in state.characters.size():
		var c: Character = state.characters[i]
		if c.is_dead():
			continue
		units[i] = {
			"pos": c.position, "counter": c.counter, "side": c.side,
			"team": c.team, "morale": c.morale, "name": c.display_name,
			"order": c.order if c.has_order else -1,
			"hidden": c.side == Domain.Side.ENEMY and not c.known,
		}
	return units


# Un passo di movimento (chiamato da Move a ogni cambio di hex).
static func step(state: GameState, mover: Character, from: Vector2i, to: Vector2i) -> void:
	var f := _frame(state)
	var i := state.characters.find(mover)
	if i < 0:
		return
	if not f["moves"].has(i):
		f["moves"][i] = [from]
		if f["units"].has(i):
			# il frame puo' nascere a impulse iniziato: la partenza vera
			# del percorso e' la posizione di riferimento dell'unita'
			f["units"][i]["pos"] = from
	f["moves"][i].append(to)


# Un'azione di fuoco completa (stesso dict di state.shots).
static func shot(state: GameState, data: Dictionary) -> void:
	_frame(state)["shots"].append(data)


# Un'esplosione (granata/mortaio/C4).
static func boom(state: GameState, hex: Vector2i, type: int) -> void:
	_frame(state)["booms"].append({"hex": hex, "type": type})


# Un suono senza grafica propria (mischia, urlo): la UI lo riproduce
# insieme ai colpi del frame.
static func sfx(state: GameState, key: String) -> void:
	_frame(state)["sfx"].append(key)
