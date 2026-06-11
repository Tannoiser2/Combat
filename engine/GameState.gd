## Lo stato completo della partita di Combat!.
## La spina dorsale: ogni regola legge e modifica questo oggetto.
## RefCounted = dati puri, niente grafica.
class_name GameState
extends RefCounted

# Una casella di mappa: terreno + livello di altezza.
class MapHex:
	var terrain: int  # Domain.Terrain
	var level: int = 0
	func _init(p_terrain: int, p_level: int = 0) -> void:
		terrain = p_terrain
		level = p_level

var turn: int = 1
var impulse: int = 1  # 1..4

# Mappa: chiave "col,row" -> MapHex
var map: Dictionary = {}

# Tutti i personaggi in gioco
var characters: Array[Character] = []

# Ordine di iniziativa: lista di Team dal piu' basso (agisce primo) al piu' alto
var initiative_order: Array[String] = []

# Bussola direzionale del nemico (Rule 9.3): rotazione applicata alle direzioni
var compass_rotation: int = 0

# Fine partita
var max_turns: int = 10
var game_over: bool = false


# Chiave di una cella a partire da coordinate.
static func hex_key(col: int, row: int) -> String:
	return "%d,%d" % [col, row]


# Restituisce la MapHex a date coordinate, o null se fuori mappa.
func hex_at(col: int, row: int) -> MapHex:
	return map.get(hex_key(col, row))


# Tutti i personaggi di un dato Team.
func characters_of_team(team: String) -> Array[Character]:
	var result: Array[Character] = []
	for c in characters:
		if c.team == team:
			result.append(c)
	return result


# Personaggio in una data cella, o null.
func character_at(col: int, row: int) -> Character:
	for c in characters:
		if c.position.x == col and c.position.y == row:
			return c
	return null
