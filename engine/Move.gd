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


# Direzione esagonale (1..6, indice di CUBE_DIRS) di un passo fra due hex
# ADIACENTI. 0 se i due hex non sono adiacenti (Rule 31: facing dello scafo).
static func dir_of_step(from: Vector2i, to: Vector2i) -> int:
	var delta := to_cube(to) - to_cube(from)
	var idx := CUBE_DIRS.find(delta)
	return idx + 1 if idx >= 0 else 0


# Direzione esagonale (1..6) piu' vicina dal centro `from` verso `to`, anche a
# distanza. Usata per orientare la torretta sul bersaglio (Rule 31.6).
static func dir_toward(from: Vector2i, to: Vector2i) -> int:
	var delta := to_cube(to) - to_cube(from)
	var best := 1
	var best_dot := -0x7fffffff
	for i in range(6):
		var dir: Vector3i = CUBE_DIRS[i]
		var dot: int = dir.x * delta.x + dir.y * delta.y + dir.z * delta.z
		if dot > best_dot:
			best_dot = dot
			best = i + 1
	return best


# Ruota un facing (1..6) di UN hex-side verso target_dir, per la via piu'
# corta (Rule 31.5/31.6: 1 hex-side per impulso). Se gia' allineato, invariato.
static func rotate_toward(current: int, target_dir: int) -> int:
	if current == target_dir:
		return current
	var cw := (target_dir - current + 6) % 6   # passi in senso orario
	var ccw := (current - target_dir + 6) % 6   # passi in senso antiorario
	if cw <= ccw:
		return (current % 6) + 1                 # +1 (wrap 6->1)
	return ((current + 4) % 6) + 1               # -1 (wrap 1->6)


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
	# Rule 31: i veicoli non entrano in certi terreni.
	if mover.is_vehicle:
		var hv := state.hex_at(hex.x, hex.y)
		if hv != null and hv.terrain in VehicleCombat.VEHICLE_BLOCKED:
			return false
	var occ := state.character_at(hex.x, hex.y)
	if occ == null or occ.is_dead():
		return true
	# Stacking (Rule 8): piu' uomini dello stesso lato possono condividere un
	# hex. I veicoli non condividono l'hex con la fanteria.
	if occ.side == mover.side:
		return _stack_ok(mover, occ)
	if not mover.has_order or mover.order not in [D.Order.CHARGE, D.Order.MELEE]:
		return false
	# Rule 15: non si può caricare un hex con 2+ difensori (uno contro due).
	if _enemy_count_at(state, mover, hex) >= 2:
		return false
	# Edificio fortificato (Rule 27.2): non si carica un occupante al suo
	# interno (vale per entrambi i lati - il giocatore non entra, il nemico
	# non ci prova).
	var h := state.hex_at(hex.x, hex.y)
	if h != null and h.terrain == D.Terrain.FORTIFIED_BUILDING:
		return false
	return true


# Lo stacking dello stesso lato e' permesso (Rule 8): un compagno vivo nell'hex
# non blocca, salvo che uno dei due sia un veicolo (la fanteria non condivide
# l'hex con i mezzi).
static func _stack_ok(mover: Character, occ: Character) -> bool:
	return not occ.is_vehicle and not mover.is_vehicle


# Conta i nemici vivi nell'hex (per il blocco Charge con 2+ difensori).
static func _enemy_count_at(state: GameState, mover: Character, hex: Vector2i) -> int:
	var count := 0
	for c in state.characters:
		if c.side != mover.side and not c.is_dead() and c.position == hex:
			count += 1
	return count


# L'ordine fa avanzare (true) o ritirare (false)?
static func advances(order: int) -> bool:
	return order in TOWARD_ORDERS


# Avversario vivo piu' vicino (riferimento per verso/fuga).
static func nearest_enemy(state: GameState, mover: Character) -> Character:
	var best: Character = null
	var best_d := 99999
	for other in state.characters:
		if other.side == mover.side or other.is_dead() or other.embarked:
			continue
		var d := Spotting.hex_distance(mover.position, other.position)
		if d < best_d:
			best_d = d
			best = other
	return best


# Registra un passo per l'animazione (UI) e il replay, poi sposta davvero.
static func _commit_step(state: GameState, mover: Character, dest: Vector2i) -> void:
	var from := mover.position
	# Rule 31.5: lo scafo del veicolo si orienta nella direzione di marcia.
	if mover.is_vehicle:
		var d := dir_of_step(from, dest)
		if d > 0:
			mover.facing = d
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


# Passo verso (o lontano da) target_pos con BFS a 3 livelli di lookahead.
# Risolve i blocchi contro ostacoli che il vecchio greedy non superava.
static func step(state: GameState, mover: Character, target_pos: Vector2i, away: bool) -> bool:
	# BFS: per ogni hex raggiungibile in max 3 passi, traccia il primo passo.
	var first_step: Dictionary = {}  # hex -> primo hex adiacente al mover
	var frontier: Array[Vector2i] = []
	for n in neighbors(state, mover.position):
		if can_enter(state, mover, n):
			first_step[n] = n
			frontier.append(n)
	if frontier.is_empty():
		return false
	for _depth in range(2):  # già fatto 1 livello; altri 2 = totale 3
		var next_frontier: Array[Vector2i] = []
		for pos in frontier:
			for n in neighbors(state, pos):
				if n == mover.position or first_step.has(n):
					continue
				if not can_enter(state, mover, n):
					continue
				first_step[n] = first_step[pos]
				next_frontier.append(n)
		if next_frontier.is_empty():
			break
		frontier = next_frontier
	var best_first := Vector2i(-99, -99)
	var best_score := -99999
	var cur_dist := Spotting.hex_distance(mover.position, target_pos)
	for hex: Vector2i in first_step:
		var dist := Spotting.hex_distance(hex, target_pos)
		var score: int = (cur_dist - dist) if not away else (dist - cur_dist)
		if score > best_score:
			best_score = score
			best_first = first_step[hex]
	if best_first.x <= -99 or best_score <= 0:
		return false
	_commit_step(state, mover, best_first)
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
		# Hex libero, oppure occupato da un compagno (stacking, Rule 8).
		var occ := state.character_at(dest.x, dest.y)
		var stackable: bool = occ != null and not occ.is_dead() \
			and occ.side == mover.side and _stack_ok(mover, occ) \
			and Area.fire_at(state, dest) < 0
		if is_passable(state, dest) or stackable:
			_commit_step(state, mover, dest)
			return 1
	return 0


# Muove fino a `hexes` passi secondo l'ordine del personaggio.
# I nemici con una direzione stampata sulla carta (es. Evade 5/6) seguono
# la BUSSOLA (Rule 9.3); Charge e Berserk puntano il nemico piu' vicino;
# senza direzione si ripiega su verso/lontano dal nemico.
# Ritorna il numero di passi effettuati.
# Un compagno dello stesso lato nell'hex tiene giu' il filo spinato con un
# ordine Hide: in quel caso le restrizioni del filo non si applicano (Rule 27.7).
static func wire_hide_exempt(state: GameState, mover: Character) -> bool:
	for c in state.characters:
		if c != mover and not c.is_dead() and c.position == mover.position \
				and c.side == mover.side and c.has_order and c.order == D.Order.HIDE:
			return true
	return false


static func move_character(state: GameState, mover: Character, hexes: int) -> int:
	# Rule 31: veicolo FAST con MUST_MOVE_2 si muove di 2 hex invece di 1.
	if mover.is_vehicle and hexes == 2:
		hexes = VehicleCombat.vehicle_hexes(mover.vehicle_type, true)
	# Filo spinato (Rule 27.7): per USCIRE serve un TQC (fallito = resta
	# impigliato), salvo che un compagno nell'hex sia in Hide.
	if state.has_wire(mover.position) and not wire_hide_exempt(state, mover):
		if not Checks.troop_quality_check(mover, state.rng)["passed"]:
			state.log_event("%s e' impigliato nel filo spinato (TQC fallito)" % mover.display_name)
			return 0
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
	if moved > 0:
		var sfx := "vehicle" if mover.is_vehicle else \
			("run" if mover.order in [D.Order.SPRINT, D.Order.RUN_AND_GUN,
				D.Order.CHARGE] else "footstep")
		state.audio_events.append({"type": sfx, "hex": mover.position})
	return moved
