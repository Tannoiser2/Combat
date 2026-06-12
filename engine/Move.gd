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

# Le 6 direzioni in senso ORARIO sullo schermo, partendo da basso-destra.
const CW_DIRS := [
	Vector3i(1, -1, 0),   # 30 gradi: basso-destra
	Vector3i(0, -1, 1),   # 90: basso
	Vector3i(-1, 0, 1),   # 150: basso-sinistra
	Vector3i(-1, 1, 0),   # 210: alto-sinistra
	Vector3i(0, 1, -1),   # 270: alto
	Vector3i(1, 0, -1),   # 330: alto-destra
]


# Bussola del nemico (Rule 9.3): dato il delta della freccia "1",
# ritorna l'array indicizzabile 1..6 (senso orario) dei delta cubici.
static func compass_from_dir1(dir1: Vector3i) -> Array:
	var start := CW_DIRS.find(dir1)
	if start < 0:
		start = 4  # ripiego: "1" = nord
	var out: Array = [Vector3i.ZERO]  # indice 0 inutilizzato
	for k in range(6):
		out.append(CW_DIRS[(start + k) % 6])
	return out


# "5/6" -> [5, 6]; "6" -> [6]; non-direzioni -> [].
static func parse_dirs(move_str: String) -> Array[int]:
	var out: Array[int] = []
	for part in move_str.split("/"):
		if part.is_valid_int():
			var d := int(part)
			if d >= 1 and d <= 6:
				out.append(d)
	return out

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
	if Area.fire_at(state, hex) >= 0:
		return false  # Rule 29.2: non si entra in un hex in fiamme
	var occ := state.character_at(hex.x, hex.y)
	return occ == null or occ.is_dead()


# Percorribilita' per UN mover specifico: come is_passable, ma chi sta
# caricando (Charge/Melee) puo' entrare nell'hex di un avversario vivo -
# e' l'assalto che porta alla mischia nello stesso hex (Rule 15).
static func can_enter(state: GameState, mover: Character, hex: Vector2i) -> bool:
	if not state.map.has(GameState.hex_key(hex.x, hex.y)):
		return false
	if Area.fire_at(state, hex) >= 0:
		return false  # Rule 29.2: nemmeno la carica entra nelle fiamme
	var occ := state.character_at(hex.x, hex.y)
	if occ == null or occ.is_dead():
		return true
	if occ.side == mover.side or not mover.has_order \
			or mover.order not in [D.Order.CHARGE, D.Order.MELEE]:
		return false
	# Edificio fortificato (Rule 27.2): non si carica un occupante al suo
	# interno (vale per entrambi i lati - il giocatore non entra, il nemico
	# non ci prova).
	var h := state.hex_at(hex.x, hex.y)
	if h != null and h.terrain == D.Terrain.FORTIFIED_BUILDING:
		return false
	return true


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


# Registra un passo per l'animazione (UI) e il replay, poi sposta davvero.
static func _commit_step(state: GameState, mover: Character, dest: Vector2i) -> void:
	var from := mover.position
	mover.position = dest
	state.move_paths.append({"who": mover, "from": from, "to": dest})
	Replay.step(state, mover, from, dest)


# Passo verso un hex scelto (deve essere adiacente e libero). Per il
# movimento guidato dal giocatore. Ritorna true se si e' mosso.
static func step_to(state: GameState, mover: Character, dest: Vector2i) -> bool:
	if dest in neighbors(state, mover.position) and can_enter(state, mover, dest):
		_commit_step(state, mover, dest)
		return true
	return false


# Un passo verso (o lontano da) target_pos. Ritorna true se si e' mosso.
static func step(state: GameState, mover: Character, target_pos: Vector2i, away: bool) -> bool:
	var cur := Spotting.hex_distance(mover.position, target_pos)
	var best := Vector2i(-99, -99)
	var best_score := 0
	for n in neighbors(state, mover.position):
		if not can_enter(state, mover, n):
			continue
		var delta := cur - Spotting.hex_distance(n, target_pos)  # >0 = avvicina
		var score := -delta if away else delta
		if score > best_score:
			best_score = score
			best = n
	if best.x <= -99:
		return false
	_commit_step(state, mover, best)
	return true


# Passo in direzione di bussola (prima direzione percorribile della
# lista). Ritorna: 0 = fermo, 1 = mosso, 2 = uscito dalla mappa.
static func compass_step(state: GameState, mover: Character, dirs: Array[int]) -> int:
	var may_exit: bool = not state.scenario_id.is_empty() \
		and Scenario.SCENARIOS[state.scenario_id].get("enemy_may_exit", false)
	# Un nemico in ROUT che raggiunge il bordo fugge sempre dalla mappa
	# (eliminato ai fini dei VP).
	var routing := mover.morale == D.Morale.ROUT
	for d in dirs:
		if d < 1 or d >= state.compass.size():
			continue
		var dest := from_cube(to_cube(mover.position) + state.compass[d])
		if not state.map.has(GameState.hex_key(dest.x, dest.y)):
			if (may_exit or routing) and mover.side == D.Side.ENEMY:
				mover.removed = true
				mover.routed_off = routing
				state.log_event("%s %s" % [mover.display_name,
					"fugge fuori mappa in ROUT" if routing else "esce dalla mappa"])
				return 2
			continue
		if is_passable(state, dest):
			_commit_step(state, mover, dest)
			return 1
	return 0


# Muove fino a `hexes` passi secondo l'ordine del personaggio.
# I nemici con una direzione stampata sulla carta (es. Evade 5/6) seguono
# la BUSSOLA (Rule 9.3); Charge e Berserk puntano il nemico piu' vicino;
# senza direzione si ripiega su verso/lontano dal nemico.
# Ritorna il numero di passi effettuati.
static func move_character(state: GameState, mover: Character, hexes: int) -> int:
	var dirs := parse_dirs(mover.order_move)
	var use_compass: bool = mover.side == D.Side.ENEMY and not dirs.is_empty() \
		and state.compass.size() == 7 and mover.order != D.Order.CHARGE
	var target := nearest_enemy(state, mover)
	if target == null and not use_compass:
		return 0
	var away := not advances(mover.order)
	var moved := 0
	for i in range(hexes):
		var from := mover.position
		if use_compass:
			var res := compass_step(state, mover, dirs)
			if res != 1:
				break
		else:
			# Charge/Sprint si fermano accanto al bersaglio (per la melee).
			if not away and target != null \
					and Spotting.hex_distance(mover.position, target.position) <= 1:
				break
			if not step(state, mover, target.position, away):
				break
		moved += 1
		# Scavalcare un BOCAGE (argine alto) esaurisce il movimento.
		if state.hexside_between(from, mover.position) == D.Terrain.BOCAGE:
			break
	return moved
