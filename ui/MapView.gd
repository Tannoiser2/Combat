## Vista 2D della mappa: disegna la griglia esagonale e i segnalini
## leggendo il GameState. SOLO rappresentazione: nessuna logica di gioco.
##
## Due modalita':
## - con `board` (scansione della mappa come texture): disegna la mappa
##   vera e ci posiziona sopra i segnalini, usando la calibrazione della
##   griglia presa dal modulo Vassal (vedi BOARDS);
## - senza (es. build web: le scansioni non sono nel repo): la stessa
##   griglia viene disegnata proceduralmente, con feature generate a
##   runtime (chiome, solchi, sassi, acqua, siepi, tetti) dal terreno
##   classificato in Boards.gd. Nessun artwork protetto, solo codice.
##
## Geometria delle mappe stampate: esagoni flat-top in colonne, numerati
## col.riga; le colonne PARI sono mezzo passo piu' in basso.
class_name MapView
extends Node2D

const D := preload("res://engine/Domain.gd")

# Calibrazione delle 4 mappe (dal buildFile del modulo Vassal: HexGrid
# dx/dy/x0/y0). origin = centro dell'hex 01.00; cell = passo (dx, dy).
const CELL := Vector2(156.30026487501547, 180.48)
const BOARDS := {
	"farmhouse": {"file": "res://assets/maps/farmhouse.jpg", "origin": Vector2(72, 106)},
	"hill": {"file": "res://assets/maps/hill.jpg", "origin": Vector2(73, 109)},
	"village": {"file": "res://assets/maps/village.jpg", "origin": Vector2(77, 110)},
	"hedgerows": {"file": "res://assets/maps/hedgerows.jpg", "origin": Vector2(70, 110)},
	# Vol. 2 — mappe 5-10
	"woods":      {"file": "res://assets/maps/woods.jpg",      "origin": Vector2(67, 103)},
	"town":       {"file": "res://assets/maps/town.jpg",       "origin": Vector2(73, 104)},
	"abbey":      {"file": "res://assets/maps/abbey.jpg",      "origin": Vector2(73, 104)},
	"hamlet":     {"file": "res://assets/maps/hamlet.jpg",     "origin": Vector2(73, 105)},
	"hedgerows2": {"file": "res://assets/maps/hedgerows2.jpg", "origin": Vector2(73, 104)},
	"ridge":      {"file": "res://assets/maps/ridge.jpg",      "origin": Vector2(73, 104)},
}

# Modalita' procedurale (nessuna texture)
const HEX_SIZE := 46.0  # raggio centro-vertice
const SQRT3 := sqrt(3.0)

# Colore di base (riempimento) di ogni hex in modalita' procedurale.
# Per i terreni "decorati" (alberi, sassi, edifici...) la base e' il
# suolo, le feature vengono disegnate sopra da _draw_feature().
const BASE_COLORS := {
	D.Terrain.OPEN_LEVEL_0: Color(0.52, 0.63, 0.37),
	D.Terrain.OPEN_LEVEL_1: Color(0.60, 0.64, 0.40),
	D.Terrain.OPEN_LEVEL_2: Color(0.68, 0.63, 0.42),
	D.Terrain.OPEN_LEVEL_3: Color(0.74, 0.64, 0.44),
	D.Terrain.ROCKS: Color(0.52, 0.63, 0.37),
	D.Terrain.BUILDING: Color(0.52, 0.63, 0.37),
	D.Terrain.TREES: Color(0.40, 0.52, 0.30),
	D.Terrain.MARSH: Color(0.46, 0.57, 0.50),
	D.Terrain.HEDGEROW: Color(0.50, 0.61, 0.36),
	D.Terrain.WALL: Color(0.52, 0.63, 0.37),
	D.Terrain.LONG_GRASS: Color(0.56, 0.66, 0.34),
	D.Terrain.DEPRESSION: Color(0.60, 0.61, 0.42),
	D.Terrain.STREAM: Color(0.50, 0.62, 0.40),
	D.Terrain.ORCHARD: Color(0.46, 0.58, 0.33),
	D.Terrain.LOGS: Color(0.52, 0.63, 0.37),
	D.Terrain.FIELD: Color(0.75, 0.68, 0.42),
	D.Terrain.FOXHOLE: Color(0.52, 0.63, 0.37),
	D.Terrain.RUBBLE: Color(0.58, 0.53, 0.47),
	D.Terrain.CRATER: Color(0.54, 0.47, 0.36),
	D.Terrain.BOCAGE: Color(0.48, 0.59, 0.34),
}

# Colori delle decorazioni procedurali.
const C_CANOPY := Color(0.20, 0.38, 0.19)
const C_CANOPY_HI := Color(0.29, 0.49, 0.26)
const C_HEDGE := Color(0.15, 0.31, 0.15)
const C_BOCAGE := Color(0.10, 0.25, 0.12)
const C_ROCK := Color(0.62, 0.62, 0.59)
const C_ROCK_HI := Color(0.75, 0.75, 0.72)
const C_ROOF := Color(0.56, 0.28, 0.22)
const C_WATER := Color(0.40, 0.58, 0.74)
const C_WALL := Color(0.56, 0.54, 0.49)
const C_LOG := Color(0.46, 0.32, 0.19)
const C_DIRT := Color(0.47, 0.39, 0.29)
const C_DIRT_DK := Color(0.36, 0.29, 0.21)
const C_FURROW := Color(0.64, 0.57, 0.33)
const C_GRASS_DK := Color(0.34, 0.46, 0.23)
const SIDE_COLORS := {
	D.Side.FRIENDLY: Color(0.18, 0.32, 0.60),
	D.Side.ENEMY: Color(0.55, 0.55, 0.52),  # feldgrau
}

# Colore del pallino di morale sul segnalino (e nel roster).
const MORALE_COLORS := {
	D.Morale.BERSERK: Color(0.75, 0.20, 0.85),    # viola
	D.Morale.AGGRESSIVE: Color(0.95, 0.45, 0.10), # arancio
	D.Morale.BOLD: Color(0.25, 0.65, 0.95),       # azzurro
	D.Morale.NORMAL: Color(0.30, 0.80, 0.30),     # verde
	D.Morale.CAUTIOUS: Color(0.95, 0.85, 0.15),   # giallo
	D.Morale.SHAKEN: Color(0.90, 0.25, 0.20),     # rosso
	D.Morale.ROUT: Color(0.35, 0.32, 0.30),       # grigio scuro
}

var state: GameState
var board: Texture2D = null
var origin := Vector2.ZERO          # centro dell'hex con etichetta (first_col, 0)
var cell := Vector2(1.5 * HEX_SIZE, SQRT3 * HEX_SIZE)
var first_col := 0                  # prima colonna etichettata (1 sulle mappe vere)
var selected: Character = null      # personaggio evidenziato
var highlight_hex := Vector2i(-99, -99)  # hex evidenziato (selezione a vuoto)
var cue_hexes: Array[Vector2i] = []  # hex suggeriti (bersagli/mosse)
var cue_color := Color(0.95, 0.85, 0.2, 0.9)
# Linee di vista dall'unita' selezionata: [{to: Vector2, clear: bool}]
var los_lines: Array = []
# Overlay di verifica del terreno (tasto T): tinte + hexside sopra la
# scansione, per confrontare la classificazione con la mappa vera.
var debug_terrain := false
# Strumento LOS: {from: Vector2, to: Vector2, clear: bool} oppure {}.
var los_tool: Dictionary = {}
var _counter_cache := {}            # id -> Texture2D oppure null (assente)

# Animazioni: posizione "visiva" dei segnalini (insegue quella logica)
# e traccianti dei colpi (eta' per dissolvenza e proiettile in volo).
var _display_pos := {}              # Character -> Vector2
var _tracers: Array = []            # {from: Vector2, to: Vector2, hit, age}
var _seen_shots := 0                # quanti state.shots gia' convertiti
# Movimento fluido hex-per-hex: ogni passo del motore diventa un waypoint
# e il segnalino li percorre a velocita' costante.
var _waypoints := {}                # Character -> Array[Vector2]
var _seen_moves := 0                # quanti state.move_paths gia' convertiti
# Esplosioni: lampo che si espande e svanisce.
var _blasts: Array = []             # {pos: Vector2, age: float}
var _seen_booms := 0

# --- Replay: la UI carica un frame "fantasma" e fa avanzare il progresso;
# il disegno usa queste unita' al posto di state.characters.
var replay_mode := false
var replay_units: Dictionary = {}   # idx -> snapshot (vedi Replay.gd)
var replay_paths: Dictionary = {}   # idx -> Array di Vector2i (percorso)
var replay_progress := 0.0          # 0..1 sulla parte di movimento


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if state == null:
		return
	var dirty := false
	if replay_mode:
		dirty = true
	# Passi di movimento del motore -> waypoint per l'animazione.
	if state.move_paths.size() < _seen_moves:
		_seen_moves = 0
	while _seen_moves < state.move_paths.size():
		var mp: Dictionary = state.move_paths[_seen_moves]
		var who: Character = mp["who"]
		if not _waypoints.has(who):
			_waypoints[who] = []
			if not _display_pos.has(who):
				_display_pos[who] = hex_center(mp["from"].x, mp["from"].y)
		_waypoints[who].append(hex_center(mp["to"].x, mp["to"].y))
		_seen_moves += 1
	# Percorri i waypoint a velocita' costante (movimento fluido hex-per-hex).
	for who in _waypoints.keys():
		var pts: Array = _waypoints[who]
		var cur: Vector2 = _display_pos.get(who, hex_center(who.position.x, who.position.y))
		var budget := cell.x * 3.2 * delta
		while budget > 0.0 and not pts.is_empty():
			var d := cur.distance_to(pts[0])
			if d <= budget:
				cur = pts.pop_front()
				budget -= d
			else:
				cur += (pts[0] - cur) / d * budget
				budget = 0.0
		_display_pos[who] = cur
		if pts.is_empty():
			_waypoints.erase(who)
		dirty = true
	# Segnalini senza percorso: inseguimento esponenziale della posizione
	# logica (teletrasporti, schieramento).
	for c in state.characters:
		if _waypoints.has(c):
			continue
		var target := hex_center(c.position.x, c.position.y)
		if not _display_pos.has(c):
			_display_pos[c] = target
			continue
		var cur2: Vector2 = _display_pos[c]
		if cur2.distance_to(target) > 0.5:
			_display_pos[c] = cur2.lerp(target, minf(1.0, delta * 9.0))
			dirty = true
		elif cur2 != target:
			_display_pos[c] = target
			dirty = true
	# Esplosioni -> lampi.
	if state.booms.size() < _seen_booms:
		_seen_booms = 0
	while _seen_booms < state.booms.size():
		var bm: Dictionary = state.booms[_seen_booms]
		add_blast(bm["hex"])
		_seen_booms += 1
	if not _blasts.is_empty():
		dirty = true
		for b in _blasts:
			b["age"] += delta
		_blasts = _blasts.filter(func(b): return b["age"] < 1.0)
	# Nuovi colpi -> traccianti.
	if state.shots.size() < _seen_shots:
		_seen_shots = 0  # azzerati a inizio impulse
	while _seen_shots < state.shots.size():
		var s: Dictionary = state.shots[_seen_shots]
		_tracers.append({
			"from": hex_center(s["from"].x, s["from"].y),
			"to": hex_center(s["to"].x, s["to"].y),
			"hit": s["hit"], "age": 0.0,
			"outcome": s.get("outcome", ""),
		})
		_seen_shots += 1
	# Invecchia i traccianti (il balloon dell'esito vive piu' a lungo).
	if not _tracers.is_empty():
		dirty = true
		for t in _tracers:
			t["age"] += delta
		_tracers = _tracers.filter(func(t): return t["age"] < 2.4)
	if dirty:
		queue_redraw()


# Posizione visiva (animata) di un personaggio.
func _pos_of(c: Character) -> Vector2:
	return _display_pos.get(c, hex_center(c.position.x, c.position.y))


# Tracciante aggiunto dalla UI (replay): stesso dict di state.shots.
func add_tracer(s: Dictionary) -> void:
	_tracers.append({
		"from": hex_center(s["from"].x, s["from"].y),
		"to": hex_center(s["to"].x, s["to"].y),
		"hit": s["hit"], "age": 0.0,
		"outcome": s.get("outcome", ""),
	})


# Lampo di esplosione su un hex.
func add_blast(hex: Vector2i) -> void:
	_blasts.append({"pos": hex_center(hex.x, hex.y), "age": 0.0})


# Posizione di un'unita' fantasma del replay: lungo il percorso del frame
# secondo replay_progress, o ferma sulla posizione dello snapshot.
func _replay_pos(idx: int) -> Vector2:
	if replay_paths.has(idx):
		var path: Array = replay_paths[idx]
		if path.size() >= 2:
			var s: float = replay_progress * (path.size() - 1)
			var i: int = mini(int(s), path.size() - 2)
			var a := hex_center(path[i].x, path[i].y)
			var b := hex_center(path[i + 1].x, path[i + 1].y)
			return a.lerp(b, s - i)
	var p: Vector2i = replay_units[idx]["pos"]
	return hex_center(p.x, p.y)

# Segnalino "retro"/dummy generico per team nemico (non identificato).
const DUMMY_BY_TEAM := {
	"Blue": "GE-BlueTeam-Dummy-1",
	"Red": "GE-RedTeam-Dummy-1",
	"White": "GE-WhiteTeam-Dummy-1",
	"Yellow": "GE-YellowTeam-Dummy-1",
	# Vol.2 SS: i file dummy non sono nel repo pubblico → cerchietto procedurale.
	"Teal": "GE-TealTeam-Dummy-1",
	"Purple": "GE-PurpleTeam-Dummy-1",
}


# Carica una delle 4 mappe (se la scansione e' presente in assets/maps).
# Ritorna true se la texture e' stata caricata; senza texture la stessa
# griglia si disegna in modalita' procedurale (terreno da Boards.gd).
func load_board(board_name: String) -> bool:
	assert(BOARDS.has(board_name), "Mappa sconosciuta: %s" % board_name)
	var info: Dictionary = BOARDS[board_name]
	first_col = 1
	if not ResourceLoader.exists(info["file"]):
		board = null
		origin = Vector2(HEX_SIZE, HEX_SIZE)
		cell = Vector2(1.5 * HEX_SIZE, SQRT3 * HEX_SIZE)
		return false
	board = load(info["file"])
	origin = info["origin"]
	cell = CELL
	return true


# Centro in pixel di una cella (col, riga). Colonne PARI mezzo passo giu'.
func hex_center(col: int, row: int) -> Vector2:
	var x := origin.x + cell.x * (col - first_col)
	var y := origin.y + cell.y * (row + (0.5 if col % 2 == 0 else 0.0))
	return Vector2(x, y)


# Hex piu' vicino a un punto in coordinate locali della mappa.
# Ritorna Vector2i(col, row), o (-99,-99) se il punto e' fuori griglia.
func pick_hex(pos: Vector2) -> Vector2i:
	var best := Vector2i(-99, -99)
	var best_d := INF
	var col_guess := int(round((pos.x - origin.x) / cell.x)) + first_col
	for col in range(col_guess - 1, col_guess + 2):
		var row_guess := int(round((pos.y - origin.y) / cell.y - (0.5 if col % 2 == 0 else 0.0)))
		for row in range(row_guess - 1, row_guess + 2):
			if state == null or not state.map.has(GameState.hex_key(col, row)):
				continue
			var d := hex_center(col, row).distance_to(pos)
			if d < best_d:
				best_d = d
				best = Vector2i(col, row)
	return best if best_d <= cell.x / 1.5 * 1.05 else Vector2i(-99, -99)


# Personaggio vivo in un dato hex, o null.
func character_at_hex(hex: Vector2i) -> Character:
	if state == null:
		return null
	var c := state.character_at(hex.x, hex.y)
	return null if c == null or c.is_dead() else c


# Texture del segnalino "<id>-f.png" da assets/counters/, o null se manca
# (caricata una volta sola). Cosi' la build web senza i PNG ripiega sui
# cerchietti, mentre in locale compaiono le pedine vere.
func _counter_tex(counter_id: String) -> Texture2D:
	if counter_id.is_empty():
		return null
	if not _counter_cache.has(counter_id):
		var path := "res://assets/counters/%s-f.png" % counter_id
		_counter_cache[counter_id] = load(path) if ResourceLoader.exists(path) else null
	return _counter_cache[counter_id]


# Segnalino-ordine (con impulse track) per ordine e lato, o null se assente.
func _order_tex(order: int, side: int) -> Texture2D:
	var prefix := "US" if side == D.Side.FRIENDLY else "GE"
	var name := "ord-%s-%s" % [prefix, D.Order.keys()[order]]
	if not _counter_cache.has(name):
		var path := "res://assets/counters/%s.png" % name
		_counter_cache[name] = load(path) if ResourceLoader.exists(path) else null
	return _counter_cache[name]


func _draw() -> void:
	if state == null:
		return
	var font := ThemeDB.fallback_font
	var radius := cell.x / 1.5  # raggio centro-vertice
	if board != null:
		draw_texture(board, Vector2.ZERO)
		if debug_terrain:
			_draw_terrain_overlay(radius)
	else:
		_draw_procedural_terrain(font, radius)
	# Hexside (siepi/bocage/muri): sempre in procedurale, col debug sulla
	# scansione (la scansione li ha gia' disegnati).
	if board == null or debug_terrain:
		_draw_hexsides(radius)
	# Cannoni obiettivo (intro3/s9): cerchio scuro, X rossa se distrutti.
	if not state.scenario_id.is_empty():
		for gun in Scenario.SCENARIOS[state.scenario_id].get("gun_hexes", []):
			var gp: PackedStringArray = String(gun).split(",")
			var gc := hex_center(int(gp[0]), int(gp[1]))
			draw_circle(gc, radius * 0.55, Color(0.25, 0.25, 0.22, 0.9))
			draw_string(font, gc + Vector2(-radius * 0.45, radius * 0.15),
				"GUN", HORIZONTAL_ALIGNMENT_LEFT, -1, int(radius * 0.35), Color.WHITE)
			if String(gun) in state.guns_destroyed:
				draw_line(gc - Vector2(radius, radius) * 0.5, gc + Vector2(radius, radius) * 0.5,
					Color(0.9, 0.1, 0.1), radius * 0.12)
				draw_line(gc + Vector2(-radius, radius) * 0.5, gc + Vector2(radius, -radius) * 0.5,
					Color(0.9, 0.1, 0.1), radius * 0.12)
		# Punti di ricognizione (s6): bandierine.
		for obj in Scenario.SCENARIOS[state.scenario_id].get("objective_hexes", []):
			var op: PackedStringArray = String(obj).split(",")
			var oc := hex_center(int(op[0]), int(op[1]))
			var done: bool = String(obj) in state.visited_objectives
			draw_circle(oc, radius * 0.30,
				Color(0.2, 0.8, 0.3, 0.9) if done else Color(0.95, 0.8, 0.1, 0.9))
			draw_string(font, oc + Vector2(-radius * 0.15, radius * 0.12),
				"R", HORIZONTAL_ALIGNMENT_LEFT, -1, int(radius * 0.3), Color.BLACK)
	# Segnalini d'area (granate, fumo, mortai, illuminazione)
	for m in state.area_markers:
		var ac := hex_center(m["hex"].x, m["hex"].y)
		match m["type"]:
			Area.Type.SMOKE:
				var alpha := 0.55 if m["turns_left"] >= 2 else 0.30
				draw_circle(ac, radius * 0.85, Color(0.85, 0.85, 0.85, alpha))
			Area.Type.ILLUM:
				draw_circle(ac, radius * 0.9, Color(1.0, 0.95, 0.5, 0.25))
			Area.Type.FIRE:
				draw_circle(ac, radius * 0.55, Color(0.95, 0.45, 0.1, 0.8))
				draw_circle(ac, radius * 0.30, Color(1.0, 0.85, 0.2, 0.9))
			Area.Type.RAGING_FIRE:
				draw_circle(ac, radius * 0.85, Color(0.9, 0.25, 0.05, 0.85))
				draw_circle(ac, radius * 0.5, Color(1.0, 0.6, 0.1, 0.95))
				draw_circle(ac, radius * 0.22, Color(1.0, 0.95, 0.5, 1.0))
			Area.Type.C4:
				draw_rect(Rect2(ac - Vector2(radius, radius) * 0.25,
					Vector2(radius, radius) * 0.5), Color(0.8, 0.7, 0.2))
				draw_string(font, ac + Vector2(-radius * 0.22, radius * 0.12),
					"C4", HORIZONTAL_ALIGNMENT_LEFT, -1, int(radius * 0.3), Color.BLACK)
			_:
				# ordigni in attesa di esplodere: cerchio arancio pulsante
				draw_circle(ac, radius * 0.4, Color(0.95, 0.5, 0.1, 0.85))
				draw_arc(ac, radius * 0.55, 0, TAU, 20, Color(0.9, 0.2, 0.1, 0.9), radius * 0.06)
				draw_string(font, ac + Vector2(-radius * 0.2, radius * 0.12),
					"!", HORIZONTAL_ALIGNMENT_LEFT, -1, int(radius * 0.5), Color.WHITE)
	# Strumento LOS: linea spessa tra i due hex scelti.
	if not los_tool.is_empty():
		var lt_col: Color = Color(0.2, 0.95, 0.3, 0.95) if los_tool["clear"] \
			else Color(0.95, 0.2, 0.15, 0.95)
		_draw_dashed(los_tool["from"], los_tool["to"], lt_col,
			radius * 0.12, radius * 0.5)
		draw_circle(los_tool["from"], radius * 0.2, lt_col)
		draw_circle(los_tool["to"], radius * 0.2, lt_col)
		if not los_tool["clear"]:
			var mid: Vector2 = (los_tool["from"] + los_tool["to"]) * 0.5
			draw_line(mid + Vector2(-1, -1) * radius * 0.3, mid + Vector2(1, 1) * radius * 0.3, lt_col, radius * 0.1)
			draw_line(mid + Vector2(-1, 1) * radius * 0.3, mid + Vector2(1, -1) * radius * 0.3, lt_col, radius * 0.1)
	# Linee di vista dall'unita' selezionata: verde tratteggiata = LOS
	# libera, rossa = bloccata (con una x sul punto di arrivo).
	if selected != null and not los_lines.is_empty():
		var from := _pos_of(selected)
		for l in los_lines:
			var col: Color = Color(0.25, 0.9, 0.35, 0.8) if l["clear"] \
				else Color(0.9, 0.25, 0.2, 0.7)
			_draw_dashed(from, l["to"], col, radius * 0.06, radius * 0.35)
			if not l["clear"]:
				var p: Vector2 = l["to"]
				draw_line(p + Vector2(-1, -1) * radius * 0.2, p + Vector2(1, 1) * radius * 0.2, col, radius * 0.06)
				draw_line(p + Vector2(-1, 1) * radius * 0.2, p + Vector2(1, -1) * radius * 0.2, col, radius * 0.06)
	# Traccianti dei colpi: tratteggio "in marcia" dal tiratore al
	# bersaglio, proiettile in volo, poi balloon con l'esito che sale.
	for t in _tracers:
		var age: float = t["age"]
		var fade := clampf((1.6 - age) / 1.2, 0.0, 1.0)
		var col: Color = Color(0.95, 0.15, 0.1, 0.85 * fade) if t["hit"] \
			else Color(0.9, 0.85, 0.4, 0.6 * fade)
		if fade > 0.0:
			_draw_dashed(t["from"], t["to"], col, radius * 0.07,
				radius * 0.35, age * radius * 3.0)
		if age < 0.35:
			var bullet: Vector2 = t["from"].lerp(t["to"], age / 0.35)
			draw_circle(bullet, radius * 0.14, Color(1.0, 0.9, 0.4, 0.95))
		elif not String(t["outcome"]).is_empty():
			_draw_balloon(font, t["to"], t["outcome"], age, radius)
	# Hex suggeriti (bersagli di fuoco in rosso, mosse in verde)
	for h in cue_hexes:
		var cc := hex_center(h.x, h.y)
		var pts := _hex_points(cc, radius * 0.9)
		draw_colored_polygon(pts, Color(cue_color.r, cue_color.g, cue_color.b, 0.22))
		draw_polyline(_closed(pts), cue_color, radius * 0.07)
	# Evidenziazione dell'hex selezionato
	if highlight_hex.x > -99:
		var hc := hex_center(highlight_hex.x, highlight_hex.y)
		draw_polyline(_closed(_hex_points(hc, radius * 0.96)),
			Color(1.0, 1.0, 0.3, 0.9), radius * 0.06)
	# Lampi delle esplosioni: anello che si espande e svanisce.
	for b in _blasts:
		var bt: float = b["age"] / 1.0
		draw_arc(b["pos"], radius * (0.3 + bt * 1.3), 0, TAU, 24,
			Color(1.0, 0.6, 0.15, 1.0 - bt), radius * 0.16 * (1.05 - bt))
		if bt < 0.4:
			draw_circle(b["pos"], radius * 0.5 * (1.0 - bt),
				Color(1.0, 0.85, 0.3, 0.9 - bt * 2.0))
	# Segnalini. In replay si disegnano le unita' fantasma del frame; in
	# gioco quelle vive. Un Enemy non Known mostra il retro generico
	# (dummy): il giocatore sa che c'e' qualcosa, non chi sia ne' cosa fara'.
	if replay_mode:
		for idx in replay_units:
			var u: Dictionary = replay_units[idx]
			_draw_unit(font, radius, _replay_pos(idx), u["counter"], u["side"],
				u["team"], u["hidden"], u["morale"], u["order"], u["name"], false)
	else:
		for c in state.characters:
			if c.is_dead():
				continue
			var hidden := c.side == D.Side.ENEMY and not c.known
			var center := _pos_of(c)
			_draw_unit(font, radius, center, c.counter, c.side, c.team, hidden,
				c.morale, c.order if c.has_order else -1, c.display_name,
				c == selected, c.order_move)
			if c.is_vehicle and not hidden:
				_draw_vehicle_overlay(radius, center, c)
			if c.side == D.Side.FRIENDLY and c.spotted:
				draw_circle(center + Vector2(radius * 0.52, -radius * 0.52),
					radius * 0.12, Color(0.9, 0.15, 0.15))


# Un segnalino completo: pedina (o cerchietto di ripiego), pallino del
# morale, badge dell'ordine. Usato sia per il gioco vivo sia per il replay.
func _draw_unit(font: Font, radius: float, center: Vector2, counter: String,
		side: int, team: String, hidden: bool, morale: int, order: int,
		name: String, is_selected: bool, order_move: String = "") -> void:
	if is_selected:
		draw_circle(center, radius * 0.62, Color(1.0, 1.0, 0.3, 0.85))
	# Segnalino vero se disponibile (dummy se nemico non identificato),
	# altrimenti cerchietto di ripiego (build web senza i PNG).
	var counter_id: String = DUMMY_BY_TEAM.get(team, "GE-RedTeam-Dummy-1") if hidden else counter
	var tex := _counter_tex(counter_id)
	if tex != null:
		var s := radius * 1.5
		draw_texture_rect(tex, Rect2(center - Vector2(s, s) * 0.5, Vector2(s, s)), false)
	else:
		draw_circle(center, radius * 0.45,
			Color(0.30, 0.30, 0.30) if hidden else SIDE_COLORS[side])
		draw_circle(center, radius * 0.45, Color(0, 0, 0, 0.6), false, radius * 0.04)
		draw_string(font, center + Vector2(-radius * 0.15, radius * 0.15),
			"?" if hidden else name.substr(0, 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(radius * 0.42), Color.WHITE)
	# Pallino del morale (alto a sinistra), bordato per leggibilita'.
	if not hidden:
		var mc := center + Vector2(-radius * 0.52, -radius * 0.52)
		draw_circle(mc, radius * 0.17, MORALE_COLORS[morale])
		draw_circle(mc, radius * 0.17, Color(0, 0, 0, 0.8), false, radius * 0.03)
	# Ordine: segnalino-ordine vero (con impulse track) come badge in
	# basso a destra; ripiego a etichetta per gli ordini senza marker.
	if order >= 0 and not hidden:
		var otex := _order_tex(order, side)
		if otex != null:
			var ms := radius * 0.95
			draw_texture_rect(otex,
				Rect2(center + Vector2(radius * 0.18, radius * 0.18), Vector2(ms, ms)), false)
		else:
			var label: String = D.ORDER_NAMES[order]
			if not order_move.is_empty():
				label += " " + order_move
			draw_string(font, center + Vector2(-radius * 0.9, radius * 0.92),
				label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(radius * 0.3),
				Color(0.95, 0.95, 0.2))


# Overlay per veicoli: rettangolo, freccia di facing, badge hull_damage.
# Le 6 direzioni di schermo corrispondono alle 6 facce del hex flat-top,
# partendo da basso-destra (facing 1) in senso orario.
func _draw_vehicle_overlay(radius: float, center: Vector2, c: Character) -> void:
	# Direzioni di schermo per facing 1..6 (CUBE_DIRS[(facing-1)%6] -> 2D).
	# 1=basso-dx, 2=alto-dx, 3=alto, 4=alto-sx, 5=basso-sx, 6=basso.
	const FACE_DIRS := [
		Vector2(0.866, 0.5), Vector2(0.866, -0.5), Vector2(0.0, -1.0),
		Vector2(-0.866, -0.5), Vector2(-0.866, 0.5), Vector2(0.0, 1.0),
	]
	var hw := radius * 0.44
	var hh := radius * 0.34
	draw_rect(Rect2(center - Vector2(hw, hh), Vector2(hw * 2, hh * 2)),
		Color(0, 0, 0, 0.75), false, radius * 0.05)
	var fi: int = clamp(c.facing - 1, 0, 5)
	var tip: Vector2 = center + (FACE_DIRS[fi] as Vector2) * radius * 0.40
	draw_line(center, tip, Color(1.0, 1.0, 1.0, 0.9), radius * 0.07)
	if c.hull_damage == 1:
		var bp := center + Vector2(radius * 0.36, radius * 0.36)
		draw_circle(bp, radius * 0.18, Color(1.0, 0.45, 0.0))
		draw_circle(bp, radius * 0.18, Color(0, 0, 0, 0.6), false, radius * 0.03)


func _draw_procedural_terrain(font: Font, radius: float) -> void:
	# Tre passate: prima tutti i riempimenti, poi le decorazioni (cosi'
	# cio' che sborda da un hex non viene coperto dal vicino), infine i
	# bordi e le etichette delle coordinate.
	for key in state.map:
		var hex: GameState.MapHex = state.map[key]
		var c := _key_to_cell(key)
		draw_colored_polygon(_hex_points(hex_center(c.x, c.y), radius),
			BASE_COLORS.get(hex.terrain, Color.MAGENTA))
	for key in state.map:
		var hex2: GameState.MapHex = state.map[key]
		var c2 := _key_to_cell(key)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(key)
		_draw_feature(hex_center(c2.x, c2.y), radius, hex2.terrain, rng)
	for key in state.map:
		var c3 := _key_to_cell(key)
		var center := hex_center(c3.x, c3.y)
		draw_polyline(_closed(_hex_points(center, radius)), Color(0, 0, 0, 0.18), 1.0)
		draw_string(font, center + Vector2(-radius * 0.42, -radius * 0.60),
			"%02d.%02d" % [c3.x, c3.y], HORIZONTAL_ALIGNMENT_LEFT, -1,
			maxi(8, int(radius * 0.22)), Color(0, 0, 0, 0.32))


# Decorazione procedurale di un hex secondo il terreno. Il rng e' seminato
# da (col,row), quindi le feature sono stabili tra un redraw e l'altro.
func _draw_feature(center: Vector2, radius: float, terrain: int, rng: RandomNumberGenerator) -> void:
	match terrain:
		D.Terrain.TREES: _draw_canopies(center, radius, rng, 5)
		D.Terrain.ORCHARD: _draw_canopies(center, radius, rng, 3)
		D.Terrain.HEDGEROW: _draw_hedge(center, radius, rng, C_HEDGE, radius * 0.40)
		D.Terrain.BOCAGE: _draw_hedge(center, radius, rng, C_BOCAGE, radius * 0.55)
		D.Terrain.ROCKS: _draw_rocks(center, radius, rng, 5)
		D.Terrain.RUBBLE: _draw_rocks(center, radius, rng, 7)
		D.Terrain.BUILDING: _draw_building(center, radius, rng)
		D.Terrain.STREAM: _draw_band(center, radius, rng, C_WATER, radius * 0.5)
		D.Terrain.WALL: _draw_band(center, radius, rng, C_WALL, radius * 0.2)
		D.Terrain.LOGS: _draw_logs(center, radius, rng)
		D.Terrain.MARSH: _draw_marsh(center, radius, rng)
		D.Terrain.DEPRESSION: _draw_rings(center, radius)
		D.Terrain.CRATER: _draw_crater(center, radius)
		D.Terrain.FOXHOLE: _draw_foxhole(center, radius)
		D.Terrain.FIELD: _draw_furrows(center, radius, rng)
		D.Terrain.LONG_GRASS: _draw_grass(center, radius, rng)


func _draw_canopies(center: Vector2, radius: float, rng: RandomNumberGenerator, n: int) -> void:
	for i in n:
		var off := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * radius * 0.42
		var rad := radius * rng.randf_range(0.30, 0.44)
		draw_circle(center + off, rad, C_CANOPY)
		draw_circle(center + off - Vector2(rad, rad) * 0.22, rad * 0.55, C_CANOPY_HI)


func _draw_hedge(center: Vector2, radius: float, rng: RandomNumberGenerator, col: Color, width: float) -> void:
	var ang := rng.randi_range(0, 2) * PI / 3.0  # orientata come un lato hex
	var dir := Vector2(cos(ang), sin(ang))
	var perp := Vector2(-dir.y, dir.x)
	var f := center - dir * radius * 0.95
	var t := center + dir * radius * 0.95
	draw_line(f, t, col, width)
	for i in 3:
		var p := f.lerp(t, (i + 0.5) / 3.0) + perp * rng.randf_range(-1, 1) * width * 0.25
		draw_circle(p, width * 0.6, col)


func _draw_rocks(center: Vector2, radius: float, rng: RandomNumberGenerator, n: int) -> void:
	for i in n:
		var off := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * radius * 0.5
		var rad := radius * rng.randf_range(0.14, 0.26)
		draw_circle(center + off, rad, C_ROCK)
		draw_circle(center + off - Vector2(rad, rad) * 0.25, rad * 0.5, C_ROCK_HI)
		draw_arc(center + off, rad, 0, TAU, 10, Color(0, 0, 0, 0.30), 1.0)


func _draw_building(center: Vector2, radius: float, rng: RandomNumberGenerator) -> void:
	var ang := rng.randf_range(-0.3, 0.3)
	var hw := radius * 0.60
	var hh := radius * 0.45
	var pts := PackedVector2Array()
	for corner in [Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)]:
		pts.append(center + corner.rotated(ang))
	draw_colored_polygon(pts, C_ROOF)
	draw_polyline(_closed(pts), Color(0, 0, 0, 0.55), 2.0)
	draw_line(center + Vector2(-hw, 0).rotated(ang), center + Vector2(hw, 0).rotated(ang),
		Color(0, 0, 0, 0.35), 1.5)


func _draw_band(center: Vector2, radius: float, rng: RandomNumberGenerator, col: Color, width: float) -> void:
	var ang := rng.randi_range(0, 2) * PI / 3.0
	var dir := Vector2(cos(ang), sin(ang))
	draw_line(center - dir * radius, center + dir * radius, col, width)


func _draw_logs(center: Vector2, radius: float, rng: RandomNumberGenerator) -> void:
	var ang := rng.randf_range(0, PI)
	var dir := Vector2(cos(ang), sin(ang))
	var perp := Vector2(-dir.y, dir.x)
	for i in 3:
		var o := perp * (i - 1) * radius * 0.28
		draw_line(center + o - dir * radius * 0.55, center + o + dir * radius * 0.55,
			C_LOG, radius * 0.12)


func _draw_marsh(center: Vector2, radius: float, rng: RandomNumberGenerator) -> void:
	for i in 4:
		var off := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * radius * 0.45
		draw_circle(center + off, radius * rng.randf_range(0.12, 0.20), C_WATER)
	for i in 5:
		var b := center + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * radius * 0.5
		draw_line(b, b + Vector2(0, -radius * 0.25), C_GRASS_DK, 1.5)


func _draw_rings(center: Vector2, radius: float) -> void:
	for s in [0.70, 0.45]:
		draw_arc(center, radius * s, 0, TAU, 20, C_DIRT_DK, 2.0)


func _draw_crater(center: Vector2, radius: float) -> void:
	draw_circle(center, radius * 0.55, C_DIRT)
	draw_circle(center, radius * 0.32, C_DIRT_DK)
	draw_arc(center, radius * 0.55, 0, TAU, 20, Color(0, 0, 0, 0.30), 1.5)


func _draw_foxhole(center: Vector2, radius: float) -> void:
	draw_circle(center, radius * 0.30, C_DIRT)
	draw_circle(center, radius * 0.18, C_DIRT_DK)


func _draw_furrows(center: Vector2, radius: float, rng: RandomNumberGenerator) -> void:
	var ang := rng.randf_range(0, PI)
	var dir := Vector2(cos(ang), sin(ang))
	var perp := Vector2(-dir.y, dir.x)
	for i in range(-2, 3):
		var o := perp * (i * radius * 0.22)
		draw_line(center + o - dir * radius * 0.70, center + o + dir * radius * 0.70,
			C_FURROW, 1.5)


func _draw_grass(center: Vector2, radius: float, rng: RandomNumberGenerator) -> void:
	for i in 8:
		var b := center + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * radius * 0.55
		draw_line(b, b + Vector2(rng.randf_range(-0.2, 0.2), -1) * radius * 0.22, C_GRASS_DK, 1.5)


static func _key_to_cell(key: String) -> Vector2i:
	var p := key.split(",")
	return Vector2i(int(p[0]), int(p[1]))


# Hexside: segmento spesso sul bordo condiviso tra i due hex.
const HEXSIDE_COLORS := {
	D.Terrain.HEDGEROW: Color(0.10, 0.45, 0.12),
	D.Terrain.BOCAGE: Color(0.06, 0.28, 0.08),
	D.Terrain.WALL: Color(0.55, 0.53, 0.48),
}


func _draw_hexsides(radius: float) -> void:
	for key in state.hexsides:
		var parts: PackedStringArray = String(key).split("|")
		var p1: PackedStringArray = parts[0].split(",")
		var p2: PackedStringArray = parts[1].split(",")
		var c1 := hex_center(int(p1[0]), int(p1[1]))
		var c2 := hex_center(int(p2[0]), int(p2[1]))
		var mid := (c1 + c2) * 0.5
		var dir := (c2 - c1).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var col: Color = HEXSIDE_COLORS.get(state.hexsides[key], Color.MAGENTA)
		draw_line(mid - perp * radius * 0.5, mid + perp * radius * 0.5,
			col, radius * 0.18)


# Tinte dell'overlay di verifica (tasto T), usate anche per la legenda.
const OVERLAY_TINTS := {
	D.Terrain.TREES: Color(0.0, 0.85, 0.1, 0.40),
	D.Terrain.FIELD: Color(1.0, 0.85, 0.0, 0.40),
	D.Terrain.ROCKS: Color(0.7, 0.7, 0.7, 0.45),
	D.Terrain.BUILDING: Color(1.0, 0.1, 0.1, 0.50),
	D.Terrain.STREAM: Color(0.1, 0.4, 1.0, 0.50),
	D.Terrain.MARSH: Color(0.0, 0.9, 0.9, 0.45),
	D.Terrain.LOGS: Color(0.55, 0.35, 0.1, 0.45),
	D.Terrain.OPEN_LEVEL_1: Color(0.95, 0.95, 0.4, 0.35),
	D.Terrain.OPEN_LEVEL_2: Color(1.0, 0.5, 0.0, 0.40),
}


# Overlay di verifica (tasto T): tinte di classificazione sopra la
# scansione. Confronta i colori con la mappa vera per trovare errori,
# poi si correggono a mano in Boards.gd.
func _draw_terrain_overlay(radius: float) -> void:
	for key in state.map:
		var hex: GameState.MapHex = state.map[key]
		if hex.terrain == D.Terrain.OPEN_LEVEL_0:
			continue
		var c := _key_to_cell(key)
		var base: Color = BASE_COLORS.get(hex.terrain, Color.MAGENTA)
		var tint: Color = OVERLAY_TINTS.get(hex.terrain,
			Color(base.r, base.g, base.b, 0.45))
		draw_colored_polygon(_hex_points(hex_center(c.x, c.y), radius * 0.92), tint)


# I sei vertici di un esagono flat-top attorno a un centro.
static func _hex_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(6):
		var angle := PI / 3.0 * i  # 0, 60, 120... gradi: vertice a destra
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	return points + PackedVector2Array([points[0]])


# Linea tratteggiata; phase > 0 fa "marciare" i trattini verso b.
func _draw_dashed(a: Vector2, b: Vector2, col: Color, width: float,
		dash: float, phase: float = 0.0) -> void:
	var total := a.distance_to(b)
	var dir := (b - a).normalized()
	var step := dash * 1.7
	var t := fmod(phase, step) - step
	while t < total:
		var seg_start := maxf(t, 0.0)
		var seg_end := clampf(t + dash, 0.0, total)
		if seg_end > seg_start:
			draw_line(a + dir * seg_start, a + dir * seg_end, col, width)
		t += step


# Colori dei balloon di esito.
const OUTCOME_COLORS := {
	"Mancato": Color(0.75, 0.75, 0.65),
	"Colpito!": Color(0.95, 0.65, 0.15),
	"Soppresso!": Color(0.95, 0.85, 0.20),
	"Ferito!": Color(0.95, 0.30, 0.20),
	"Ucciso!": Color(0.85, 0.10, 0.10),
}


# Balloon dell'esito: sale dal bersaglio e svanisce.
func _draw_balloon(font: Font, at: Vector2, text: String, age: float, radius: float) -> void:
	var t := clampf((age - 0.35) / 2.0, 0.0, 1.0)
	var alpha := clampf(1.4 - t * 1.5, 0.0, 1.0)
	if alpha <= 0.0:
		return
	var pos := at + Vector2(0, -radius * (0.9 + t * 1.1))
	var fsize := int(radius * 0.34)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var pad := radius * 0.14
	var rect := Rect2(pos - Vector2(w * 0.5 + pad, fsize * 0.85 + pad * 0.5),
		Vector2(w + pad * 2.0, fsize + pad))
	draw_rect(rect, Color(0.05, 0.07, 0.04, 0.85 * alpha))
	var col: Color = OUTCOME_COLORS.get(text, Color.WHITE)
	draw_rect(rect, Color(col.r, col.g, col.b, 0.9 * alpha), false, 1.5)
	draw_string(font, pos - Vector2(w * 0.5, 0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fsize,
		Color(col.r, col.g, col.b, alpha))
