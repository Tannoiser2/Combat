## Movimento sulla griglia esagonale (Rule 10/13, primo strato).
##
## Convenzione: esagoni flat-top, offset "even-q" (colonne pari mezzo
## passo piu' in basso), coerente con MapView.hex_center, Spotting e LOS.
## Il movimento e' a passi di 1 hex; quanti passi per impulse lo dice
## Orders.IMPULSES. La direzione (verso/lontano dall'avversario) dipende
## dall'ordine: e' l'approssimazione procedurale dell'avversario a tabelle.
##
## TODO: costi di movimento per terreno, melee a fine Charge, uso dei
## valori di direzione stampati sulle Enemy Card (order_move) per la
## bussola quando il nemico non ha un bersaglio noto.
class_name Move
extends RefCounted

const D := preload("res://engine/Domain.gd")

const CUBE_DIRS := [
	Vector3i(1, -1, 0), Vector3i(1, 0, -1), Vector3i(0, 1, -1),
	Vector3i(-1, 1, 0), Vector3i(-1, 0, 1), Vector3i(0, -1, 1),
]

# Ordini che fanno avanzare verso il nemico; gli altri (Evade, Carry/Drag)
# allontanano.
const TOWARD_ORDERS := [
	D.Order.SNEAK, D.Order.SPRINT, D.Order.RUN_AND_GUN, D.Order.CHARGE,
	D.Order.GRENADE, D.Order.SMOKE_GRENADE,
]


static func to_cube(h: Vector2i) -> Vector3i:
	var z := h.y - int((h.x + (h.x & 1)) / 2.0)
	return Vector3i(h.x, -h.x - z, z)


static func from_cube(c: Vector3i) -> Vector2i:
	return Vector2i(c.x, c.z + int((c.x + (c.x & 1)) / 2.0))


# Gli hex adiacenti presenti sulla mappa.
static func neighbors(state: GameState, h: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cube := to_cube(h)
	for dir in CUBE_DIRS:
		var n := from_cube(cube + dir)
		if state.map.has(GameState.hex_key(n.x, n.y)):
			out.append(n)
	return out


# Un hex e' calpestabile se esiste ed e' libero (niente vivi dentro).
static func is_passable(state: GameState, hex: Vector2i) -> bool:
	if not state.map.has(GameState.hex_key(hex.x, hex.y)):
		return false
	var occ := state.character_at(hex.x, hex.y)
	return occ == null or occ.is_dead()


# L'ordine fa avanzare (true) o ritirare (false)?
static func advances(order: int) -> bool:
	return order in TOWARD_ORDERS


# Avversario vivo piu' vicino (riferimento per verso/fuga).
static func nearest_enemy(state: GameState, mover: Character) -> Character:
	var best: Character = null
	var best_d := 99999
	for other in state.characters:
		if other.side == mover.side or other.is_dead():
			continue
		var d := Spotting.hex_distance(mover.position, other.position)
		if d < best_d:
			best_d = d
			best = other
	return best


# Passo verso un hex scelto (deve essere adiacente e libero). Per il
# movimento guidato dal giocatore. Ritorna true se si e' mosso.
static func step_to(state: GameState, mover: Character, dest: Vector2i) -> bool:
	if dest in neighbors(state, mover.position) and is_passable(state, dest):
		mover.position = dest
		return true
	return false


# Un passo verso (o lontano da) target_pos. Ritorna true se si e' mosso.
static func step(state: GameState, mover: Character, target_pos: Vector2i, away: bool) -> bool:
	var cur := Spotting.hex_distance(mover.position, target_pos)
	var best := Vector2i(-99, -99)
	var best_score := 0
	for n in neighbors(state, mover.position):
		if not is_passable(state, n):
			continue
		var delta := cur - Spotting.hex_distance(n, target_pos)  # >0 = avvicina
		var score := -delta if away else delta
		if score > best_score:
			best_score = score
			best = n
	if best.x <= -99:
		return false
	mover.position = best
	return true


# Muove fino a `hexes` passi secondo l'ordine del personaggio.
# Ritorna il numero di passi effettuati.
static func move_character(state: GameState, mover: Character, hexes: int) -> int:
	var target := nearest_enemy(state, mover)
	if target == null:
		return 0
	var away := not advances(mover.order)
	var moved := 0
	for i in range(hexes):
		# Charge/Sprint si fermano accanto al bersaglio (per la melee).
		if not away and Spotting.hex_distance(mover.position, target.position) <= 1:
			break
		if not step(state, mover, target.position, away):
			break
		moved += 1
	return moved
