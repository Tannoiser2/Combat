## Lo stato completo della partita di Combat!.
## La spina dorsale: ogni regola legge e modifica questo oggetto.
## RefCounted = dati puri, niente grafica.
class_name GameState
extends RefCounted

# Una casella di mappa: terreno + livello di altezza. Il filo spinato
# (Rule 27.7) e' un overlay sul terreno base, non un terreno a se'.
class MapHex:
	var terrain: int  # Domain.Terrain
	var level: int = 0
	var wire: bool = false  # filo spinato sovrapposto (Rule 27.7)
	func _init(p_terrain: int, p_level: int = 0) -> void:
		terrain = p_terrain
		level = p_level


# C'e' filo spinato in questo hex? (Rule 27.7)
func has_wire(pos: Vector2i) -> bool:
	var h := hex_at(pos.x, pos.y)
	return h != null and h.wire

var turn: int = 1
var impulse: int = 1  # 1..4

# Mappa: chiave "col,row" -> MapHex
var map: Dictionary = {}

# Hexside (siepi/bocage/muri sui BORDI): chiave canonica
# "c1,r1|c2,r2" (coppia ordinata) -> Domain.Terrain.
var hexsides: Dictionary = {}


# Chiave canonica del bordo tra due hex adiacenti.
static func hexside_key(a: Vector2i, b: Vector2i) -> String:
	if b.x < a.x or (b.x == a.x and b.y < a.y):
		var t := a
		a = b
		b = t
	return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]


# Tipo di hexside tra due hex adiacenti, o -1 se nessuno.
func hexside_between(a: Vector2i, b: Vector2i) -> int:
	return hexsides.get(hexside_key(a, b), -1)


# L'hex ha almeno un hexside (siepe/muro) su un bordo? (per la copertura)
func hex_has_hexside(pos: Vector2i) -> bool:
	for dir in Move.CUBE_DIRS:
		var n := Move.from_cube(Move.to_cube(pos) + dir)
		if hexside_between(pos, n) >= 0:
			return true
	return false

# Tutti i personaggi in gioco
var characters: Array[Character] = []

# Ordine di iniziativa: lista di Team dal piu' basso (agisce primo) al piu' alto
var initiative_order: Array[String] = []

# Bussola direzionale del nemico (Rule 9.3): array indicizzabile 1..6
# dei delta cubici (impostata dallo scenario; [0] inutilizzato).
var compass: Array = []

# Direzione del vento (delta cubico, 1D6 sulla bussola a inizio scenario):
# il fumo deriva di 1 hex per turno. ZERO = calma piatta.
var wind: Vector3i = Vector3i.ZERO

# Generatore di casualita' della partita: un solo rng, cosi' col seed
# la partita e' riproducibile (utile per i test).
var rng := RandomNumberGenerator.new()

# Mazzo delle Enemy Card (seriali): si pesca dal fondo, si rimescola
# automaticamente quando e' esaurito.
var enemy_deck: Array[int] = []
var enemy_discard: Array[int] = []
# Carte pescate in questa Enemy Card Phase: team -> seriale (SOP step 3a)
var enemy_cards_in_play: Dictionary = {}

# Mazzo delle Friendly Card (Rule 5.0): mano, mazzo, scarti e la carta
# giocata sull'Initiative Track in questo turno (-1 = nessuna).
# Il limite della mano dipende dallo scenario (Starting Hand Size).
const HAND_LIMIT := 5
var hand_limit: int = HAND_LIMIT
var friendly_deck: Array[int] = []
var friendly_discard: Array[int] = []
var friendly_hand: Array[int] = []
var friendly_card_played: int = -1

# Scenario in corso e riserva nemica (Coppa non ancora schierata, per i
# rinforzi); flag per rinforzi gia' arrivati.
var scenario_id: String = ""
var enemy_reserve: Array = []
var waves_done: Array = []      # turni di rinforzo gia' eseguiti
var night: bool = false         # scenario notturno
var large_battle: bool = false  # Rule 9.2: una carta per Gruppo invece che per personaggio
# Meteo e condizioni del terreno (Rule 28): vedi Weather.gd. max_los = limite
# di visibilita' del meteo (0 = illimitato), tirato a inizio scenario.
var weather: int = Weather.Type.CLEAR
var ground: int = Weather.Ground.NONE
var max_los: int = 0
var guns_destroyed: Array = []  # hex (chiavi) dei cannoni saltati
var visited_objectives: Array = []  # punti di ricognizione raggiunti

# Modificatori della carta giocata, validi per il turno (azzerati in End
# Phase). Es. ws_all, ws_team{team:mod}, ws_cover_self, no_impulse1,
# restrict (limitazione ordini), event.
var turn_fx: Dictionary = {}

# Segnalini d'area sugli hex (granate, fumo, mortai...): vedi Area.gd.
var area_markers: Array = []

# Fine partita
var max_turns: int = 10
var game_over: bool = false

# Log eventi del motore: il motore registra, la UI consuma e stampa.
var log: Array[String] = []

# Colpi sparati nell'impulse corrente, come dati per la UI (linee di
# fuoco): {from, to, hit, side}. La UI li disegna e li azzera per impulse.
var shots: Array = []

# Passi di movimento dell'impulse corrente, per l'animazione hex-per-hex:
# {who: Character, from: Vector2i, to: Vector2i}. Stesso ciclo di shots.
var move_paths: Array = []

# Esplosioni avvenute (per il lampo in mappa): {hex, type}.
var booms: Array = []

# Coda eventi audio dell'impulse corrente: {type, weapon?, area_type?, hex}.
# La UI la consuma e la azzera dopo ogni azione, come shots/booms.
var audio_events: Array = []

# Frame registrati per il replay (vedi Replay.gd).
var replay: Array = []


func log_event(msg: String) -> void:
	log.append(msg)


# Svuota il log e ritorna le righe accumulate.
func drain_log() -> Array[String]:
	var lines := log.duplicate()
	log.clear()
	return lines


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
	# Preferisce un personaggio VIVO: i corpi e le esche rivelate restano
	# nell'array (gli indici del replay non cambiano mai) e farebbero da
	# schermo a chi entra nel loro hex (es. il disperso di Charlie Team
	# che spawna sull'esca: senza questo, il click non lo trova).
	var fallback: Character = null
	for c in characters:
		if c.position.x == col and c.position.y == row:
			if not c.is_dead():
				return c
			if fallback == null:
				fallback = c
	return fallback


# Team nemici con almeno un personaggio Alerted vivo (SOP step 3a).
func enemy_teams_with_alerted() -> Array[String]:
	var teams: Array[String] = []
	for c in characters:
		if c.side == Domain.Side.ENEMY and c.alerted and not c.is_dead() \
				and not teams.has(c.team):
			teams.append(c.team)
	return teams


# Pesca una Enemy Card; rimescola gli scarti quando il mazzo finisce.
func draw_enemy_card() -> int:
	if enemy_deck.is_empty():
		_refill_enemy_deck()
	var serial: int = enemy_deck.pop_back()
	enemy_discard.append(serial)
	return serial


func _refill_enemy_deck() -> void:
	enemy_deck.assign(EnemyCards.all_serials())
	enemy_discard.clear()
	_shuffle(enemy_deck)


# Pesca una Friendly Card; quando il mazzo finisce rimescola gli scarti.
func draw_friendly_card() -> int:
	if friendly_deck.is_empty():
		reshuffle_friendly_deck()
	return friendly_deck.pop_back()


# Rimescola mazzo e scarti friendly insieme (richiesto anche dalle carte
# Event). Le carte in mano e quella giocata restano fuori.
func reshuffle_friendly_deck() -> void:
	for s in friendly_discard:
		friendly_deck.append(s)
	friendly_discard.clear()
	if friendly_deck.is_empty():
		# Primo uso: mazzo completo.
		friendly_deck.assign(FriendlyCards.all_serials())
	_shuffle(friendly_deck)


# Fisher-Yates con l'rng dello stato (non Array.shuffle, che usa
# l'rng globale e romperebbe la riproducibilita' col seed).
func _shuffle(deck: Array[int]) -> void:
	for i in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := deck[i]
		deck[i] = deck[j]
		deck[j] = tmp


# Team friendly con almeno un personaggio vivo (vanno sull'Initiative Track).
func friendly_teams() -> Array[String]:
	var teams: Array[String] = []
	for c in characters:
		if c.side == Domain.Side.FRIENDLY and not c.is_dead() \
				and not teams.has(c.team):
			teams.append(c.team)
	return teams
