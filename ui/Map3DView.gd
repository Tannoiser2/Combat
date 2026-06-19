## PROTOTIPO di vista 3D della mappa (richiesta utente, sessione giugno 2026).
##
## Estrude gli esagoni a quote diverse (hex.level 0..3) e texturizza le FACCE
## SUPERIORI con la scansione vera della board: l'art piatta resta intatta in
## cima, l'estrusione alza solo gli hex di quota e genera "pareti"/cliff sui
## fianchi in discesa. SOLO grafica e camera: NESSUNA logica di gioco, niente
## input di gioco. Serve a validare il LOOK del 3D estruso.
##
## Si lancia con COMBAT_MAP3D=1 (board da COMBAT_BOARD, default "hill"); se e'
## dato COMBAT_SCENARIO le pedine compaiono come billboard sopra il terreno.
##
## Controlli camera: trascina sinistro = orbita, rotella = zoom, trascina
## destro/centrale = pan, R = reset vista, 1..3 esagera/attenua le quote.
class_name Map3DView
extends Node3D

const D := preload("res://engine/Domain.gd")
const Area := preload("res://engine/Area.gd")

# Riuso la calibrazione della griglia da MapView (stesse costanti): origin e
# passo (cell) per board, cosi' 3D e 2D restano allineati pixel-per-pixel.
const PX_PER_UNIT := 100.0     # scala scansione->mondo (1 unita' = 100 px)
const LEVEL_HEIGHT := 0.9      # altezza per livello (quote piu' marcate: alture evidenti)

signal unit_activated(c: Character)  # emesso al clic su una pedina amica (Fase 3)
signal hex_clicked(hex: Vector2i)    # emesso al clic su un hex (Fase 4: azione)

var board_name := "hill"
var state: GameState = null    # opzionale: per disegnare le pedine

var _board_tex: Texture2D
var _origin := Vector2.ZERO
var _cell := Vector2.ZERO
var _first_col := 1
var _height_scale := 1.0       # moltiplicatore quote (tasti 1/2/3)
var _smooth := false           # scalini "dolci" (vertici mediati) vs a picco (tasto S)

# --- Camera rig orbitale ---
var _camera: Camera3D
var _pivot := Vector3.ZERO
var _yaw := 0.0                # rotazione attorno all'asse verticale
var _pitch := deg_to_rad(52.0) # elevazione (0 = orizzonte, ~90 = a piombo)
var _distance := 60.0
var _home_distance := 60.0
var _orbiting := false
var _panning := false

# --- Picking 3D (Fase 1: base per giocare in 3D) ---
var _picked := Vector2i(-99, -99)   # hex attualmente evidenziato
var _highlight: MeshInstance3D      # evidenziazione dell'hex
var _info_label: Label              # lettura terreno/quota/unita'
var _top_mesh: MeshInstance3D       # mesh facce superiori (per il raycast)

# --- Selezione pedina (Fase 2) ---
var _selected: Character = null     # pedina selezionata (clic)
var _sel_ring: MeshInstance3D       # cornice di selezione attorno al chit
var _unit_pos := {}                 # Character -> posizione mondo del chit

# --- Azione dal 3D (Fase 4) ---
var _units_root: Node3D             # contenitore pedine (rinfrescabile)
var _cue_root: Node3D               # contenitore cue hexes (mosse/bersagli)
var _marker_root: Node3D            # contenitore marker d'area (fumo/fuoco/...)
var _los_root: Node3D               # contenitore strumento LOS (linea + ostacolo)

# --- Proiettili animati (Fase 5: traccianti/colpi/bombe/granate in 3D) ---
var _fx_root: Node3D                 # contenitore proiettili + lampi
var _projectiles: Array = []         # colpi/bombe/granate in volo
var _flashes: Array = []             # lampi d'esplosione
var _seen_shots3d := 0               # shots gia' animati
var _seen_arcs3d := 0                # granate gia' animate
var _seen_marks3d := 0               # marker gia' visti (per le bombe dall'alto)

# --- Replay in 3D (Fase 5) ---
var _replay_active := false
var _replay_units := {}              # idx -> snapshot (vedi Replay.gd)
var _replay_paths := {}              # idx -> Array di Vector2i
var replay_progress := 0.0
var _ghosts := {}                    # idx -> Node3D (chit fantasma)


func _ready() -> void:
	if not MapView.BOARDS.has(board_name):
		push_warning("Map3DView: board sconosciuta '%s', uso 'hill'" % board_name)
		board_name = "hill"
	var info: Dictionary = MapView.BOARDS[board_name]
	_origin = info["origin"]
	_cell = info.get("cell", MapView.CELL)
	if ResourceLoader.exists(info["file"]):
		_board_tex = load(info["file"])
	_smooth = OS.get_environment("COMBAT_MAP3D_SMOOTH") != "0"  # dolce di default (S = a picco)
	_build_environment()
	_build_terrain()
	_units_root = Node3D.new()
	add_child(_units_root)
	_cue_root = Node3D.new()
	add_child(_cue_root)
	_marker_root = Node3D.new()
	add_child(_marker_root)
	_fx_root = Node3D.new()
	add_child(_fx_root)
	_los_root = Node3D.new()
	add_child(_los_root)
	_build_units()
	_build_markers()
	_build_camera()
	_build_hud()
	set_process_unhandled_input(true)
	set_process(true)
	_seen_shots3d = state.shots.size()
	_seen_arcs3d = state.throw_arcs.size()
	_seen_marks3d = state.area_markers.size()
	# Screenshot di validazione: COMBAT_MAP3D_SHOT=path -> salva e esce.
	var shot := OS.get_environment("COMBAT_MAP3D_SHOT")
	if not shot.is_empty():
		_shot_path = shot
		var t := Timer.new()
		t.wait_time = 1.2
		t.one_shot = true
		t.timeout.connect(_grab_screenshot)
		add_child(t)
		t.start()


var _shot_path := ""

func _grab_screenshot() -> void:
	# COMBAT_MAP3D_PICK="col,row": inquadra e seleziona quell'hex (validazione
	# del picking/selezione); altrimenti pick al centro schermo.
	var pk := OS.get_environment("COMBAT_MAP3D_PICK").split(",")
	if pk.size() == 2 and state.map.has(GameState.hex_key(int(pk[0]), int(pk[1]))):
		var hx := Vector2i(int(pk[0]), int(pk[1]))
		_pivot = _world_center(hx.x, hx.y, state.map[GameState.hex_key(hx.x, hx.y)].level)
		_distance = 6.0  # ravvicinato per vedere il chit e la cornice
		_update_camera()
		_picked = hx
		_update_highlight(hx)
		_update_info(hx)
		_select_in_hex(hx)
		# Validazione cue: mostra i 6 vicini come hex-mossa (verde).
		var cues: Array = []
		for nb in _neighbors(hx.x, hx.y):
			if state.map.has(GameState.hex_key(nb.x, nb.y)):
				cues.append(nb)
		set_cues(cues, Color(0.3, 0.9, 0.3))
		_draw_fire_lines(hx, cues, Color(0.95, 0.55, 0.05))  # valida le linee
		# Valida il segnalino-ordine: assegna un ordine al selezionato e ricostruisce.
		if _selected != null:
			_selected.set_order(D.Order.AIMED_FIRE)
			_build_units()
			_update_sel_ring()
		# Valida lo strumento LOS: linea rossa con ostacolo evidenziato.
		if not OS.get_environment("COMBAT_MAP3D_LOS").is_empty():
			set_los(hx, hx + Vector2i(5, -2), false, hx + Vector2i(2, -1))
	else:
		_pick_at(get_viewport().get_visible_rect().size * 0.5, true)
	# Validazione proiettili: COMBAT_MAP3D_FX -> spawn demo a meta' volo.
	if not OS.get_environment("COMBAT_MAP3D_FX").is_empty():
		var c := _picked if _picked.x > -99 else Vector2i(18, 9)
		var nb := _neighbors(c.x, c.y)
		_spawn_gunfire({"from": c, "to": nb[0], "side": D.Side.ENEMY, "hit": true, "weapon": "MG42"})
		_spawn_gunfire({"from": c, "to": nb[2], "side": D.Side.FRIENDLY, "hit": false, "weapon": "M1 Garand"})
		_spawn_gunfire({"from": nb[4], "to": c, "side": D.Side.ENEMY, "hit": true, "weapon": "75mm L40 AP"})
		_spawn_grenade(c, nb[1])
		_spawn_bomb(nb[3])
		for p in _projectiles:
			p["t"] = 0.5
			p["delay"] = 0.0
		_advance_projectiles(0.0)
	# Validazione replay: frame sintetico con un percorso, fantasmi a meta' corsa.
	if not OS.get_environment("COMBAT_MAP3D_REPLAY").is_empty():
		var units := {}
		var paths := {}
		for i in state.characters.size():
			var c: Character = state.characters[i]
			if c.is_dead():
				continue
			units[i] = {"pos": c.position, "counter": c.counter, "side": c.side,
				"team": c.team, "morale": c.morale, "name": c.display_name,
				"hidden": c.side == D.Side.ENEMY and not c.known}
			if paths.is_empty() and c.side == D.Side.FRIENDLY:
				paths[i] = [c.position, c.position + Vector2i(1, 0),
					c.position + Vector2i(2, 1)]
		set_replay_frame(units, paths)
		update_replay_progress(0.5)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot_path)
	get_tree().quit(0)


# Centro in pixel di una cella (col, riga): identico a MapView.hex_center.
func _hex_center_px(col: int, row: int) -> Vector2:
	var x := _origin.x + _cell.x * (col - _first_col)
	var y := _origin.y + _cell.y * (row + (0.5 if col % 2 == 0 else 0.0))
	return Vector2(x, y)


# Posizione mondo del centro di un hex alla sua quota (piena): il centro resta
# alla quota dell'hex anche in modalita' dolce, cosi' pedine/cime restano alte.
func _world_center(col: int, row: int, level: int) -> Vector3:
	var px := _hex_center_px(col, row)
	return Vector3(px.x / PX_PER_UNIT, level * LEVEL_HEIGHT * _height_scale,
		px.y / PX_PER_UNIT)


# Quota (float) di un vertice dell'hex: media tra l'hex e i 2 vicini che
# condividono quel vertice (esistenti). Vertice i e' fra gli edge i-1 e i.
func _corner_level(col: int, row: int, i: int) -> float:
	var nb := _neighbors(col, row)
	var sum := float(maxi(_level_at(col, row), 0))
	var cnt := 1.0
	for k in [(i + 5) % 6, i]:
		var nl := _level_at(nb[k].x, nb[k].y)
		if nl >= 0:
			sum += nl
			cnt += 1.0
	return sum / cnt


# I 6 vicini di (col,row) in ordine di EDGE (i=0..5 = lati a 30,90,...,330 gradi).
# Sistema offset flat-top con le colonne PARI spostate in basso di mezzo passo.
func _neighbors(col: int, row: int) -> Array:
	if col % 2 == 1:  # colonna dispari
		return [Vector2i(col + 1, row), Vector2i(col, row + 1),
			Vector2i(col - 1, row), Vector2i(col - 1, row - 1),
			Vector2i(col, row - 1), Vector2i(col + 1, row - 1)]
	return [Vector2i(col + 1, row + 1), Vector2i(col, row + 1),
		Vector2i(col - 1, row + 1), Vector2i(col - 1, row),
		Vector2i(col, row - 1), Vector2i(col + 1, row)]


func _level_at(col: int, row: int) -> int:
	if state == null:
		return 0
	var key := GameState.hex_key(col, row)
	if not state.map.has(key):
		return -1  # fuori mappa: la parete scende fino a 0
	return state.map[key].level


# Costruisce la mesh del terreno: facce superiori texturizzate dalla scansione
# + pareti verticali dove un hex e' piu' alto del vicino.
func _build_terrain() -> void:
	if state == null:
		state = GameState.new()
		Boards.fill(state, board_name)

	# +0,5% sul raggio: gli hex si sovrappongono appena e chiudono le hairline
	# tra le facce (le UV cambiano in modo impercettibile).
	var radius := _cell.x / 1.5 / PX_PER_UNIT * 1.005
	var img_w := float(_board_tex.get_width()) if _board_tex != null else 5500.0
	var img_h := float(_board_tex.get_height()) if _board_tex != null else 6000.0

	var tops := SurfaceTool.new()
	tops.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)

	var bb_min := Vector3(INF, INF, INF)
	var bb_max := Vector3(-INF, -INF, -INF)

	for key in state.map:
		var hex: GameState.MapHex = state.map[key]
		var cell := _key_to_cell(key)
		var col: int = cell.x
		var row: int = cell.y
		var center := _world_center(col, row, hex.level)
		var nb := _neighbors(col, row)
		# Dolce (via di mezzo): il CENTRO resta alla quota piena dell'hex (cime
		# evidenti), i VERTICI di bordo sono mediati coi vicini -> i bordi
		# degradano dolci e la superficie resta continua, senza pareti a picco.
		var corner_y: Array[float] = []
		for i in range(6):
			corner_y.append(_corner_level(col, row, i) * LEVEL_HEIGHT * _height_scale
				if _smooth else center.y)
		bb_min.x = minf(bb_min.x, center.x); bb_max.x = maxf(bb_max.x, center.x)
		bb_min.y = minf(bb_min.y, center.y); bb_max.y = maxf(bb_max.y, center.y)
		bb_min.z = minf(bb_min.z, center.z); bb_max.z = maxf(bb_max.z, center.z)

		# 6 vertici dell'esagono (flat-top): angoli 0,60,...,300.
		var verts: Array[Vector3] = []
		var uvs: Array[Vector2] = []
		var center_px := _hex_center_px(col, row)
		for i in range(6):
			var ang := PI / 3.0 * i
			var off := Vector2(cos(ang), sin(ang)) * radius
			verts.append(Vector3(center.x + off.x, corner_y[i], center.z + off.y))
			var px := center_px + Vector2(cos(ang), sin(ang)) * (_cell.x / 1.5)
			uvs.append(Vector2(px.x / img_w, px.y / img_h))
		var center_uv := Vector2(center_px.x / img_w, center_px.y / img_h)

		# Faccia superiore: ventaglio di 6 triangoli (normale verso l'alto).
		for i in range(6):
			var j := (i + 1) % 6
			tops.set_normal(Vector3.UP)
			tops.set_uv(center_uv); tops.add_vertex(center)
			tops.set_uv(uvs[i]); tops.add_vertex(verts[i])
			tops.set_uv(uvs[j]); tops.add_vertex(verts[j])

		# Pareti: a picco -> dove il vicino e' piu' basso, cala alla sua quota;
		# dolce -> solo skirt al bordo mappa (i vertici interni gia' combaciano).
		for i in range(6):
			var nlv := _level_at(nb[i].x, nb[i].y)
			var by: float
			if _smooth:
				if nlv != -1:
					continue  # interno: superficie continua, nessuna parete
				by = 0.0
			else:
				var base_lv: int = maxi(nlv, 0)
				if base_lv >= hex.level:
					continue
				by = base_lv * LEVEL_HEIGHT * _height_scale
			var j := (i + 1) % 6
			var top_a := verts[i]
			var top_b := verts[j]
			var bot_a := Vector3(top_a.x, by, top_a.z)
			var bot_b := Vector3(top_b.x, by, top_b.z)
			var mid := (top_a + top_b) * 0.5
			var n := Vector3(mid.x - center.x, 0, mid.z - center.z).normalized()
			var ua := uvs[i]
			var ub := uvs[j]
			var quad := [top_a, top_b, bot_b, top_a, bot_b, bot_a]
			var quad_uv := [ua, ub, ub, ua, ub, ua]
			for k in range(6):
				walls.set_normal(n); walls.set_uv(quad_uv[k]); walls.add_vertex(quad[k])

	# Mesh facce superiori (texture scansione).
	var top_mesh := MeshInstance3D.new()
	top_mesh.mesh = tops.commit()
	var top_mat := StandardMaterial3D.new()
	top_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if _board_tex != null:
		top_mat.albedo_texture = _board_tex
	else:
		top_mat.albedo_color = Color(0.50, 0.60, 0.38)
	top_mat.roughness = 1.0
	top_mesh.material_override = top_mat
	add_child(top_mesh)
	_top_mesh = top_mesh
	top_mesh.create_trimesh_collision()  # corpo statico per il raycast del picking

	# Mesh pareti (colore terra/cliff).
	var wall_mesh := MeshInstance3D.new()
	wall_mesh.mesh = walls.commit()
	var wall_mat := StandardMaterial3D.new()
	wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wall_mat.roughness = 1.0
	if _board_tex != null:
		# Scansione colata sui fianchi, leggermente scurita (terra/roccia).
		wall_mat.albedo_texture = _board_tex
		wall_mat.albedo_color = Color(0.72, 0.66, 0.58)
	else:
		wall_mat.albedo_color = Color(0.42, 0.34, 0.26)
	wall_mesh.material_override = wall_mat
	add_child(wall_mesh)

	# Pivot e distanza camera dal bounding box reale.
	_pivot = (bb_min + bb_max) * 0.5
	var span := maxf(bb_max.x - bb_min.x, bb_max.z - bb_min.z)
	_distance = maxf(span * 0.9, 10.0)
	_home_distance = _distance


func _key_to_cell(key: String) -> Vector2i:
	var p := key.split(",")
	return Vector2i(int(p[0]), int(p[1]))


# Pedine come billboard sopra il terreno (solo se c'e' uno scenario caricato).
func _build_units() -> void:
	if state == null:
		return
	const TOKEN_W := 1.35    # lato segnalino in unita'-mondo (~ un hex)
	const TOKEN_T := 0.10    # spessore del cartoncino
	var seen := {}           # conteggio per hex (stacking)
	_unit_pos = {}
	if _units_root != null:
		for ch in _units_root.get_children():
			ch.queue_free()
	for c in state.characters:
		if c == null or c.is_dead() or c.embarked:
			continue
		var lv := _level_at(c.position.x, c.position.y)
		var surface := _world_center(c.position.x, c.position.y, maxi(lv, 0))
		var key := GameState.hex_key(c.position.x, c.position.y)
		var idx: int = seen.get(key, 0)
		seen[key] = idx + 1
		# Segnalino vero; per i nemici non rivelati e le esche uso il token-esca
		# del team (come la MapView 2D, la grafica esiste). Disco colorato solo
		# come ultimo ripiego se mancasse perfino quello.
		var hidden := c.side == D.Side.ENEMY and (not c.known or c.is_dummy)
		var cid: String = MapView.DUMMY_BY_TEAM.get(c.team, "GE-RedTeam-Dummy-1") \
			if hidden else c.counter
		var tex := _counter_tex(cid)
		var fb := Color(0.25, 0.50, 0.95) if c.side == D.Side.FRIENDLY \
			else Color(0.70, 0.32, 0.28)  # blu vivo (amico) / rosso-terra (nemico)
		var top_tex: Texture2D = tex if tex != null else _token_tex(fb)
		# Scostamento a cascata per le pile (Rule 8): si impilano in altezza.
		var off := Vector3(0.22 * idx, idx * TOKEN_T, 0.14 * idx)
		_unit_pos[c] = surface + off
		# Cornice del MORALE come in 2D (MapView.MORALE_COLORS); i nemici non
		# identificati non hanno morale noto -> nessuna cornice (come la 2D).
		var morale_col = null if hidden else MapView.MORALE_COLORS.get(c.morale, Color.WHITE)
		# Segnalino-ordine sopra la pedina (come in 2D), se ha un ordine e non e' nascosta.
		var order_tex: Texture2D = null
		if c.has_order and not hidden:
			var pref := "US" if c.side == D.Side.FRIENDLY else "GE"
			order_tex = _tex_named("ord-%s-%s" % [pref, D.Order.keys()[c.order]])
		var spotted: bool = c.side == D.Side.FRIENDLY and c.spotted
		var facing: int = c.facing if (c.is_vehicle and not hidden) else 0
		_add_counter(surface + off, TOKEN_W, TOKEN_T, top_tex, morale_col,
			order_tex, spotted, facing)


# Un segnalino fisico: corpo con spessore (bordi cartoncino, proietta ombra)
# + faccia superiore con l'art della pedina. Appoggiato a 'base' (superficie hex).
func _add_counter(base: Vector3, w: float, t: float, top_tex: Texture2D,
		border_color = null, order_tex: Texture2D = null,
		spotted: bool = false, facing: int = 0) -> void:
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, t, w)
	body.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.34, 0.31, 0.27)  # taglio del cartoncino (scuro, sottile)
	bmat.roughness = 0.95
	body.material_override = bmat
	body.position = base + Vector3(0, t * 0.5 + 0.02, 0)
	_units_root.add_child(body)

	var top := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w * 0.98, w * 0.98)  # faccia in su (PlaneMesh -> +Y)
	top.mesh = pm
	var tmat := StandardMaterial3D.new()
	tmat.albedo_texture = top_tex
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	top.material_override = tmat
	top.position = base + Vector3(0, t + 0.03, 0)
	# Niente ombra dalla faccia piatta: l'ombra la getta il corpo.
	top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_units_root.add_child(top)

	# Cornice del morale attorno al chit (convenzione 2D), se nota: sottile,
	# arrotondata e "soft" (semitrasparente).
	if border_color != null:
		var fr := MeshInstance3D.new()
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.cull_mode = BaseMaterial3D.CULL_DISABLED
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var sc: Color = border_color
		sc.a = 0.7
		fm.albedo_color = sc
		fr.material_override = fm
		fr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fr.mesh = _rounded_frame_mesh(base + Vector3(0, t + 0.05, 0),
			w * 0.52, w * 0.49, 0.12)
		_units_root.add_child(fr)

	# Segnalino-ordine (come in 2D): quad piatto nell'angolo basso-destra, sopra l'art.
	if order_tex != null:
		var ob := MeshInstance3D.new()
		var opm := PlaneMesh.new()
		opm.size = Vector2(w * 0.52, w * 0.52)
		ob.mesh = opm
		var omat := StandardMaterial3D.new()
		omat.albedo_texture = order_tex
		omat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		omat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		omat.cull_mode = BaseMaterial3D.CULL_DISABLED
		ob.material_override = omat
		ob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ob.position = base + Vector3(w * 0.28, t + 0.07, w * 0.28)
		_units_root.add_child(ob)

	# Pallino "spotted" (rosso) come in 2D, angolo alto-destra.
	if spotted:
		var sd := MeshInstance3D.new()
		var ssm := SphereMesh.new()
		ssm.radius = 0.09
		ssm.height = 0.18
		sd.mesh = ssm
		var smat := StandardMaterial3D.new()
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.albedo_color = Color(0.9, 0.15, 0.15)
		sd.material_override = smat
		sd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sd.position = base + Vector3(w * 0.34, t + 0.12, -w * 0.34)
		_units_root.add_child(sd)

	# Freccia di facing del veicolo (verso il vicino nella direzione di marcia).
	if facing >= 1:
		var dir := _facing_dir(facing)
		var ar := MeshInstance3D.new()
		var prism := BoxMesh.new()
		prism.size = Vector3(0.12, 0.06, w * 0.5)
		ar.mesh = prism
		var amat := StandardMaterial3D.new()
		amat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		amat.albedo_color = Color(1.0, 0.95, 0.3)
		ar.material_override = amat
		ar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var c := base + Vector3(0, t + 0.08, 0)
		ar.position = c + dir * (w * 0.32)
		if dir.length() > 0.001:
			ar.look_at_from_position(ar.position, ar.position + dir, Vector3.UP)
		_units_root.add_child(ar)


# Direzione mondo (XZ) del facing 1..6 verso il vicino corrispondente.
func _facing_dir(facing: int) -> Vector3:
	# I 6 vicini in ordine di EDGE (30,90,...330 gradi). facing 1..6 -> indice.
	var ang := deg_to_rad(30.0 + 60.0 * ((facing - 1) % 6))
	return Vector3(cos(ang), 0, sin(ang)).normalized()


func _counter_tex(counter_id: String) -> Texture2D:
	if counter_id.is_empty():
		return null
	var path := "res://assets/counters/%s-f.png" % counter_id
	return load(path) if ResourceLoader.exists(path) else null


# Segnalino di ripiego (counter mancante / esca / nemico non rivelato):
# disco tondo del colore del lato con anello scuro, cosi' si legge come una
# pedina e non come un quadrato vuoto. Una texture per colore (cache).
var _token_cache := {}

func _token_tex(col: Color) -> Texture2D:
	var ckey := col.to_rgba32()
	if _token_cache.has(ckey):
		return _token_cache[ckey]
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n - 1, n - 1) * 0.5
	var r := n * 0.46
	var ring := Color(0.10, 0.10, 0.10)
	for y in range(n):
		for x in range(n):
			var d := Vector2(x, y).distance_to(c)
			if d > r:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			elif d > r - 4.0:
				img.set_pixel(x, y, ring)
			else:
				img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	_token_cache[ckey] = tex
	return tex


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.52, 0.74)
	sky_mat.sky_horizon_color = Color(0.72, 0.78, 0.80)
	sky_mat.ground_horizon_color = Color(0.62, 0.62, 0.56)
	sky_mat.ground_bottom_color = Color(0.40, 0.40, 0.36)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.42  # piu' bassa -> le ombre staccano di piu'
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(-40.0), 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 1.5
	sun.directional_shadow_max_distance = 300.0
	add_child(sun)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.far = 5000.0
	add_child(_camera)
	_camera.make_current()
	# Manopole opzionali per inquadrare gli screenshot di validazione.
	var z := OS.get_environment("COMBAT_MAP3D_ZOOM")
	if z.is_valid_float():
		_distance *= float(z)
	var yw := OS.get_environment("COMBAT_MAP3D_YAW")
	if yw.is_valid_float():
		_yaw = deg_to_rad(float(yw))
	var pt := OS.get_environment("COMBAT_MAP3D_PITCH")
	if pt.is_valid_float():
		_pitch = deg_to_rad(float(pt))
	_update_camera()


func _update_camera() -> void:
	if _camera == null:
		return
	var dir := Vector3(
		cos(_pitch) * sin(_yaw),
		sin(_pitch),
		cos(_pitch) * cos(_yaw))
	_camera.position = _pivot + dir * _distance
	_camera.look_at(_pivot, Vector3.UP)


# Raycast dal mouse sul terreno -> hex (col,row), come pick_hex in 3D.
# select=true (clic): seleziona la pedina amica nell'hex (cicla sulle pile).
func _pick_at(screen_pos: Vector2, select: bool = false) -> void:
	if _camera == null:
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var from := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 10000.0)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var p: Vector3 = hit["position"]
	var hex := _pick_hex_from_px(Vector2(p.x * PX_PER_UNIT, p.z * PX_PER_UNIT))
	if not select and hex == _picked:
		return
	_picked = hex
	_update_highlight(hex)
	_update_info(hex)
	if select:
		hex_clicked.emit(hex)   # Fase 4: Main lo usa come bersaglio se 'acting'
		_select_in_hex(hex)


# Seleziona una pedina amica nell'hex; ri-cliccando lo stesso hex cicla tra le
# unita' impilate (Rule 8). Aggiorna cornice di selezione e info.
func _select_in_hex(hex: Vector2i) -> void:
	var units: Array = []
	for c in state.characters:
		if c == null or c.is_dead() or c.embarked:
			continue
		if c.position == hex and c.side == D.Side.FRIENDLY:
			units.append(c)
	if units.is_empty():
		return
	var i := 0
	if _selected != null and _selected in units:
		i = (units.find(_selected) + 1) % units.size()
	_selected = units[i]
	_update_sel_ring()
	var ms: String = D.Morale.keys()[_selected.morale]
	var txt := "Selezionato: %s — morale %s" % [_selected.display_name, ms]
	if _selected.has_order:
		txt += " — ordine %s" % D.ORDER_NAMES[_selected.order]
	if units.size() > 1:
		txt += "  (%d/%d nell'hex, ri-clicca per ciclare)" % [i + 1, units.size()]
	_info_label.text = txt
	unit_activated.emit(_selected)  # Fase 3: apre il pannello ordini (in Main)


# Cornice di selezione: un riquadro luminoso attorno al chit selezionato.
func _update_sel_ring() -> void:
	if _sel_ring == null or not is_instance_valid(_sel_ring):
		_sel_ring = MeshInstance3D.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = Color(0.2, 0.95, 1.0, 0.9)  # ciano = selezione
		_sel_ring.material_override = m
		_sel_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_sel_ring)
	if _selected == null or not _unit_pos.has(_selected):
		_sel_ring.visible = false
		return
	var base: Vector3 = _unit_pos[_selected]
	# Cornice di selezione (ciano) PIU' ESTERNA della cornice morale del chit.
	_sel_ring.mesh = _rounded_frame_mesh(base + Vector3(0, 0.20, 0), 0.84, 0.78, 0.16)
	_sel_ring.visible = true


# Loop di punti (XZ) di un rettangolo arrotondato: semi-lato 'h', raggio
# angolo 'r', 'seg' segmenti per angolo. Usato per le cornici soft.
func _rounded_rect_loop(h: float, r: float, seg: int = 6) -> Array:
	var pts: Array = []
	var corners := [Vector2(h - r, h - r), Vector2(-(h - r), h - r),
		Vector2(-(h - r), -(h - r)), Vector2(h - r, -(h - r))]
	var start := [0.0, PI * 0.5, PI, PI * 1.5]
	for ci in range(4):
		for s in range(seg + 1):
			var a: float = start[ci] + (PI * 0.5) * (float(s) / seg)
			pts.append(corners[ci] + Vector2(cos(a), sin(a)) * r)
	return pts


# Cornice cava ARROTONDATA orizzontale (banda sottile fra due rettangoli
# arrotondati), centrata in 'center'. Per i tracciati morale/selezione "soft".
func _rounded_frame_mesh(center: Vector3, outer: float, inner: float,
		corner: float = 0.14) -> ArrayMesh:
	var o := _rounded_rect_loop(outer, corner)
	var ii := _rounded_rect_loop(inner, maxf(corner - (outer - inner), 0.02))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = o.size()
	for k in range(n):
		var k2 := (k + 1) % n
		var oa := Vector3(o[k].x, 0, o[k].y)
		var ob := Vector3(o[k2].x, 0, o[k2].y)
		var ia := Vector3(ii[k].x, 0, ii[k].y)
		var ib := Vector3(ii[k2].x, 0, ii[k2].y)
		for v in [oa, ob, ib, oa, ib, ia]:
			st.set_normal(Vector3.UP); st.add_vertex(center + v)
	return st.commit()


# Inverso di _hex_center_px: il pixel piu' vicino a un centro di hex valido.
func _pick_hex_from_px(px: Vector2) -> Vector2i:
	var best := Vector2i(-99, -99)
	var best_d := INF
	var col_guess := int(round((px.x - _origin.x) / _cell.x)) + _first_col
	for col in range(col_guess - 1, col_guess + 2):
		var row_guess := int(round((px.y - _origin.y) / _cell.y \
			- (0.5 if col % 2 == 0 else 0.0)))
		for row in range(row_guess - 1, row_guess + 2):
			if not state.map.has(GameState.hex_key(col, row)):
				continue
			var d := _hex_center_px(col, row).distance_to(px)
			if d < best_d:
				best_d = d
				best = Vector2i(col, row)
	return best if best_d <= _cell.x / 1.5 * 1.05 else Vector2i(-99, -99)


# Evidenziazione: un esagono semitrasparente sopra la faccia dell'hex scelto.
func _update_highlight(hex: Vector2i) -> void:
	if _highlight == null or not is_instance_valid(_highlight):
		_highlight = MeshInstance3D.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = Color(1.0, 0.95, 0.2, 0.45)
		_highlight.material_override = m
		_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_highlight)
	if not state.map.has(GameState.hex_key(hex.x, hex.y)):
		_highlight.visible = false
		return
	var lv: int = state.map[GameState.hex_key(hex.x, hex.y)].level
	var center := _world_center(hex.x, hex.y, lv) + Vector3(0, 0.04, 0)
	_highlight.mesh = _hex_fan_mesh(center, _cell.x / 1.5 / PX_PER_UNIT * 1.01)
	_highlight.visible = true


# Ventaglio esagonale orizzontale (faccia in su) centrato in 'center'.
func _hex_fan_mesh(center: Vector3, radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts: Array[Vector3] = []
	for i in range(6):
		var ang := PI / 3.0 * i
		verts.append(center + Vector3(cos(ang) * radius, 0, sin(ang) * radius))
	for i in range(6):
		var j := (i + 1) % 6
		st.set_normal(Vector3.UP); st.add_vertex(center)
		st.set_normal(Vector3.UP); st.add_vertex(verts[i])
		st.set_normal(Vector3.UP); st.add_vertex(verts[j])
	return st.commit()


# Disegna i cue hexes (mosse/bersagli) come esagoni semitrasparenti (Fase 4).
func set_cues(hexes: Array, color: Color) -> void:
	if _cue_root == null:
		return
	for ch in _cue_root.get_children():
		ch.queue_free()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cc := color
	cc.a = 0.45
	mat.albedo_color = cc
	var radius := _cell.x / 1.5 / PX_PER_UNIT * 0.9
	for h in hexes:
		var hx: Vector2i = h
		if not state.map.has(GameState.hex_key(hx.x, hx.y)):
			continue
		var lv: int = state.map[GameState.hex_key(hx.x, hx.y)].level
		var mi := MeshInstance3D.new()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.mesh = _hex_fan_mesh(_world_center(hx.x, hx.y, lv) + Vector3(0, 0.07, 0), radius)
		_cue_root.add_child(mi)


# Rinfresca pedine + cue + selezione dopo un'azione (Fase 4), senza ricostruire
# il terreno. Chiamato da Main quando il preview e' attivo e lo stato cambia.
# ---- Replay in 3D: fantasmi lungo i percorsi + traccianti/bombe ----

func set_replay_frame(units: Dictionary, paths: Dictionary) -> void:
	_replay_active = true
	_replay_units = units
	_replay_paths = paths
	replay_progress = 0.0
	for ch in _units_root.get_children():
		ch.queue_free()
	_ghosts = {}
	for idx in units:
		var g := _make_ghost(units[idx])
		_units_root.add_child(g)
		_ghosts[idx] = g
	if _cue_root != null:
		for ch in _cue_root.get_children():
			ch.queue_free()
	if _sel_ring != null and is_instance_valid(_sel_ring):
		_sel_ring.visible = false
	_position_ghosts()


func update_replay_progress(p: float) -> void:
	replay_progress = p
	_position_ghosts()


func end_replay() -> void:
	_replay_active = false
	_ghosts = {}
	_replay_units = {}
	_replay_paths = {}
	_build_units()


func replay_shot(s: Dictionary) -> void:
	_spawn_gunfire(s)


func replay_boom(hex: Vector2i, type: int) -> void:
	if type in [Area.Type.MORTAR_60, Area.Type.MORTAR_81, Area.Type.ARTILLERY_105]:
		_spawn_bomb(hex)
	else:
		_spawn_flash(_hex_top(hex) + Vector3(0, 0.2, 0), 1.4)


func _position_ghosts() -> void:
	for idx in _ghosts:
		_ghosts[idx].position = _replay_world(idx)


# Posizione mondo del fantasma idx: interpolata lungo il percorso (replay_progress).
func _replay_world(idx) -> Vector3:
	if _replay_paths.has(idx):
		var path: Array = _replay_paths[idx]
		if path.size() >= 2:
			var s: float = replay_progress * (path.size() - 1)
			var i: int = mini(int(s), path.size() - 2)
			var frac: float = s - i
			return _hex_top(path[i]).lerp(_hex_top(path[i + 1]), frac)
	return _hex_top(_replay_units[idx]["pos"])


# Chit fantasma (corpo + faccia) a origine locale: lo si sposta col replay.
func _make_ghost(u: Dictionary) -> Node3D:
	var w := 1.35
	var t := 0.10
	var node := Node3D.new()
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, t, w)
	body.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.34, 0.31, 0.27)
	bmat.roughness = 0.95
	body.material_override = bmat
	body.position = Vector3(0, t * 0.5 + 0.02, 0)
	node.add_child(body)
	var hidden := bool(u.get("hidden", false))
	var tex: Texture2D = _counter_tex(MapView.DUMMY_BY_TEAM.get(u.get("team", ""),
		"GE-RedTeam-Dummy-1")) if hidden else _counter_tex(u.get("counter", ""))
	var fb := Color(0.25, 0.50, 0.95) if int(u["side"]) == D.Side.FRIENDLY \
		else Color(0.70, 0.32, 0.28)
	var top := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w * 0.98, w * 0.98)
	top.mesh = pm
	var tmat := StandardMaterial3D.new()
	tmat.albedo_texture = tex if tex != null else _token_tex(fb)
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	top.material_override = tmat
	top.position = Vector3(0, t + 0.03, 0)
	top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(top)
	# Segnalino-ordine sul fantasma (come in 2D durante il replay).
	var ordv: int = int(u.get("order", -1))
	if ordv >= 0 and not hidden:
		var pref := "US" if int(u["side"]) == D.Side.FRIENDLY else "GE"
		var otex := _tex_named("ord-%s-%s" % [pref, D.Order.keys()[ordv]])
		if otex != null:
			var ob := MeshInstance3D.new()
			var opm := PlaneMesh.new()
			opm.size = Vector2(w * 0.52, w * 0.52)
			ob.mesh = opm
			var omat := StandardMaterial3D.new()
			omat.albedo_texture = otex
			omat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			omat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			omat.cull_mode = BaseMaterial3D.CULL_DISABLED
			ob.material_override = omat
			ob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ob.position = Vector3(w * 0.28, t + 0.07, w * 0.28)
			node.add_child(ob)
	return node


func refresh_dynamic(cues: Array, color: Color,
		fire_src: Vector2i = Vector2i(-99, -99)) -> void:
	if _replay_active:
		return  # durante il replay i fantasmi gestiscono le pedine
	_build_units()
	_build_markers()
	set_cues(cues, color)
	if fire_src.x > -99:
		_draw_fire_lines(fire_src, cues, color)
	_update_sel_ring()


# Linee di fuoco/LOS dal tiratore a ogni bersaglio (cue), aggiunte ai cue.
func _draw_fire_lines(src: Vector2i, targets: Array, color: Color) -> void:
	if _cue_root == null or not state.map.has(GameState.hex_key(src.x, src.y)):
		return
	var slv: int = state.map[GameState.hex_key(src.x, src.y)].level
	var a := _world_center(src.x, src.y, slv) + Vector3(0, 0.45, 0)
	for t in targets:
		var tx: Vector2i = t
		if not state.map.has(GameState.hex_key(tx.x, tx.y)):
			continue
		var tlv: int = state.map[GameState.hex_key(tx.x, tx.y)].level
		var b := _world_center(tx.x, tx.y, tlv) + Vector3(0, 0.45, 0)
		_add_line(a, b, color)


# Strumento LOS in 3D: linea verde (libera) / rossa (bloccata) fra due hex,
# con l'esagono che blocca evidenziato. clear_los() la rimuove.
func set_los(from_hex: Vector2i, to_hex: Vector2i, clear: bool,
		blocker: Vector2i = Vector2i(-99, -99)) -> void:
	clear_los()
	var col := Color(0.2, 0.95, 0.3) if clear else Color(0.95, 0.2, 0.15)
	var a := _hex_top(from_hex) + Vector3(0, 0.5, 0)
	var b := _hex_top(to_hex) + Vector3(0, 0.5, 0)
	_add_line(a, b, col, 0.08, _los_root)
	for h in [from_hex, to_hex]:
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new(); sm.radius = 0.18; sm.height = 0.36
		s.mesh = sm
		var mt := StandardMaterial3D.new()
		mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mt.albedo_color = col
		s.material_override = mt
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.position = _hex_top(h) + Vector3(0, 0.5, 0)
		_los_root.add_child(s)
	if not clear and blocker.x > -99 and state.map.has(GameState.hex_key(blocker.x, blocker.y)):
		var blv: int = state.map[GameState.hex_key(blocker.x, blocker.y)].level
		var mi := MeshInstance3D.new()
		mi.mesh = _hex_fan_mesh(_world_center(blocker.x, blocker.y, blv) + Vector3(0, 0.06, 0),
			_cell.x / 1.5 / PX_PER_UNIT * 0.95)
		var bmat := StandardMaterial3D.new()
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		bmat.albedo_color = Color(0.95, 0.2, 0.15, 0.5)
		mi.material_override = bmat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_los_root.add_child(mi)


func clear_los() -> void:
	if _los_root == null:
		return
	for ch in _los_root.get_children():
		ch.queue_free()


# Un segmento 3D come BoxMesh sottile orientato da 'a' a 'b'.
func _add_line(a: Vector3, b: Vector3, color: Color, width: float = 0.05,
		parent: Node3D = null) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, width, a.distance_to(b))
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = (a + b) * 0.5
	if a.distance_to(b) > 0.001:
		mi.look_at_from_position((a + b) * 0.5, b, Vector3.UP)
	(parent if parent != null else _cue_root).add_child(mi)


# ---- Proiettili animati (colpi, granate a parabola, bombe dall'alto) ----

func _process(delta: float) -> void:
	if state == null:
		return
	# Nuovi colpi -> traccianti (variano per arma).
	if state.shots.size() < _seen_shots3d:
		_seen_shots3d = 0  # azzerati a inizio impulse
	while _seen_shots3d < state.shots.size():
		_spawn_gunfire(state.shots[_seen_shots3d])
		_seen_shots3d += 1
	# Nuove granate -> parabola.
	if state.throw_arcs.size() < _seen_arcs3d:
		_seen_arcs3d = 0
	while _seen_arcs3d < state.throw_arcs.size():
		var ar: Dictionary = state.throw_arcs[_seen_arcs3d]
		_spawn_grenade(ar["from"], ar["to"])
		_seen_arcs3d += 1
	# Nuovi marker mortaio/artiglieria -> bomba che cade dall'alto.
	if state.area_markers.size() < _seen_marks3d:
		_seen_marks3d = state.area_markers.size()
	while _seen_marks3d < state.area_markers.size():
		var mk: Dictionary = state.area_markers[_seen_marks3d]
		if int(mk["type"]) in [Area.Type.MORTAR_60, Area.Type.MORTAR_81, Area.Type.ARTILLERY_105]:
			_spawn_bomb(mk["hex"])
		_seen_marks3d += 1
	_advance_projectiles(delta)
	_advance_flashes(delta)


func _hex_top(hex: Vector2i) -> Vector3:
	var lv := 0
	if state.map.has(GameState.hex_key(hex.x, hex.y)):
		lv = state.map[GameState.hex_key(hex.x, hex.y)].level
	return _world_center(hex.x, hex.y, lv)


# Classe d'arma per la resa del colpo: shell (tank/bazooka), auto (mitra/MG),
# rifle (fucile/pistola).
func _weapon_class(weapon: String) -> String:
	var w := weapon.to_lower()
	for k in ["mm", "kwk", "bazooka", "panzerfaust"]:
		if k in w:
			return "shell"
	for k in ["mg", "thompson", "grease", "stg", "mp40", "bar", "m1919", "m1918", ".50"]:
		if k in w:
			return "auto"
	return "rifle"


func _spawn_gunfire(s: Dictionary) -> void:
	var a := _hex_top(s["from"]) + Vector3(0, 0.5, 0)
	var b := _hex_top(s["to"]) + Vector3(0, 0.5, 0)
	var side := int(s.get("side", D.Side.FRIENDLY))
	var hit := bool(s.get("hit", false))
	var col := Color(0.65, 0.85, 1.0) if side == D.Side.FRIENDLY else Color(1.0, 0.7, 0.3)
	match _weapon_class(String(s.get("weapon", ""))):
		"shell":
			_add_projectile("shell", a, b, 0.0, 0.55, Color(1.0, 0.9, 0.5), 0.15, hit, true)
		"auto":
			for i in range(8):  # raffica: molti colpi sfalsati
				_add_projectile("bullet", a, b, i * 0.05, 0.22, col, 0.05, hit and i == 7, false)
		_:
			for i in range(2):  # fucile/pistola: pochi colpi
				_add_projectile("bullet", a, b, i * 0.13, 0.24, col, 0.06, hit and i == 1, false)


func _spawn_grenade(fromh: Vector2i, toh: Vector2i) -> void:
	var a := _hex_top(fromh) + Vector3(0, 0.4, 0)
	var b := _hex_top(toh) + Vector3(0, 0.15, 0)
	_add_projectile("grenade", a, b, 0.0, 0.75, Color(0.35, 0.45, 0.3), 0.09, true, true)


func _spawn_bomb(hex: Vector2i) -> void:
	var b := _hex_top(hex) + Vector3(0, 0.1, 0)
	var a := b + Vector3(0, 9.0, 0)  # cade verticalmente dall'alto
	_add_projectile("bomb", a, b, 0.0, 0.6, Color(0.18, 0.18, 0.18), 0.16, true, true)


func _add_projectile(kind: String, a: Vector3, b: Vector3, delay: float,
		dur: float, color: Color, radius: float, hit: bool, explosive: bool) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	_fx_root.add_child(mi)
	_projectiles.append({"node": mi, "kind": kind, "a": a, "b": b, "t": 0.0,
		"dur": dur, "delay": delay, "hit": hit, "explosive": explosive})


func _advance_projectiles(delta: float) -> void:
	if _projectiles.is_empty():
		return
	var keep: Array = []
	for p in _projectiles:
		if p["delay"] > 0.0:
			p["delay"] -= delta
			keep.append(p)
			continue
		p["node"].visible = true
		p["t"] += delta / p["dur"]
		var t: float = clampf(p["t"], 0.0, 1.0)
		var pos: Vector3
		match p["kind"]:
			"grenade":
				pos = p["a"].lerp(p["b"], t)
				pos.y += 2.4 * t * (1.0 - t)  # arco a parabola
			"bomb":
				pos = p["a"].lerp(p["b"], t * t)  # accelera in caduta
			_:
				pos = p["a"].lerp(p["b"], t)
		p["node"].position = pos
		if p["t"] >= 1.0:
			p["node"].queue_free()
			if p["explosive"]:
				_spawn_flash(p["b"], 1.6 if p["kind"] != "shell" else 1.3)
			elif p["hit"]:
				_spawn_flash(p["b"], 0.6)
		else:
			keep.append(p)
	_projectiles = keep


func _spawn_flash(pos: Vector3, max_r: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.4
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.8, 0.3, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.2)
	mat.emission_energy_multiplier = 3.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos + Vector3(0, 0.2, 0)
	_fx_root.add_child(mi)
	_flashes.append({"node": mi, "t": 0.0, "dur": 0.45, "max_r": max_r})


func _advance_flashes(delta: float) -> void:
	if _flashes.is_empty():
		return
	var keep: Array = []
	for f in _flashes:
		f["t"] += delta / f["dur"]
		if f["t"] >= 1.0:
			f["node"].queue_free()
			continue
		var s: float = lerpf(0.3, f["max_r"], f["t"])
		f["node"].scale = Vector3(s, s, s)
		var m: StandardMaterial3D = f["node"].material_override
		m.albedo_color.a = (1.0 - f["t"]) * 0.9
		keep.append(f)
	_flashes = keep


# Texture da assets/counters/<name>.png per nome esatto (come MapView._named_tex).
func _tex_named(name: String) -> Texture2D:
	var path := "res://assets/counters/%s.png" % name
	return load(path) if ResourceLoader.exists(path) else null


# Marker d'area (fumo/fuoco/mortaio/illuminazione/C4/ordigni) come quad piatti
# texturizzati sull'hex, con le stesse grafiche del 2D (MapView).
func _build_markers() -> void:
	if _marker_root == null:
		return
	for ch in _marker_root.get_children():
		ch.queue_free()
	for m in state.area_markers:
		var hx: Vector2i = m["hex"]
		if not state.map.has(GameState.hex_key(hx.x, hx.y)):
			continue
		var tname := "marker-TARGET"  # ordigni in attesa di esplodere
		var alpha := 0.9
		match int(m["type"]):
			Area.Type.SMOKE:
				var full: bool = int(m.get("turns_left", 2)) >= 2
				tname = "marker-SMOKE-f" if full else "marker-SMOKE-r"
				alpha = 0.8 if full else 0.6
			Area.Type.ILLUM:
				tname = "marker-ILLUM"; alpha = 0.75
			Area.Type.FIRE:
				tname = "GEN-Fire-Marker-f"
			Area.Type.RAGING_FIRE:
				tname = "GEN-Raging-Marker-f"
			Area.Type.MORTAR_60:
				tname = "US-60mmMortar-Marker-1-f"
			Area.Type.MORTAR_81:
				tname = "US-81mmMortar-Marker-1-f"
			Area.Type.C4:
				tname = "marker-C4"
		_add_flat_marker(hx, _tex_named(tname), alpha)
	# Marker di terreno di scenario (come in 2D): filo spinato, trincea,
	# edificio fortificato, foxhole, rubble. Le grafiche stanno in assets/counters.
	for key in state.map:
		var sh: GameState.MapHex = state.map[key]
		var cell := _key_to_cell(key)
		if sh.wire:
			_add_flat_marker(cell, _tex_named("GEN-Wire-Marker-f"), 0.85)
		match sh.terrain:
			D.Terrain.TRENCH:
				_add_flat_marker(cell, _tex_named("GEN-Trench-Marker-f"), 0.9)
			D.Terrain.FORTIFIED_BUILDING:
				_add_flat_marker(cell, _tex_named("GEN-Fortified-Marker-f"), 0.9)
			D.Terrain.FOXHOLE:
				_add_flat_marker(cell, _tex_named("GEN-Foxhole-Marker-1-f"), 0.9)
			D.Terrain.RUBBLE:
				_add_flat_marker(cell, _tex_named("GEN-Rubble-Marker-1-f"), 0.9)
	# Obiettivi di scenario (come in 2D): cannoni (GUN) e punti di ricognizione.
	if not state.scenario_id.is_empty() and Scenario.SCENARIOS.has(state.scenario_id):
		var sc: Dictionary = Scenario.SCENARIOS[state.scenario_id]
		for gun in sc.get("gun_hexes", []):
			var gp: PackedStringArray = String(gun).split(",")
			var col := Color(0.9, 0.1, 0.1) if String(gun) in state.guns_destroyed \
				else Color(0.22, 0.22, 0.2)
			_add_flat_marker(Vector2i(int(gp[0]), int(gp[1])), _token_tex(col), 0.95, 1.0)
		for obj in sc.get("objective_hexes", []):
			var op: PackedStringArray = String(obj).split(",")
			var oc := Color(0.2, 0.8, 0.3) if String(obj) in state.visited_objectives \
				else Color(0.95, 0.8, 0.1)
			_add_flat_marker(Vector2i(int(op[0]), int(op[1])), _token_tex(oc), 0.95, 0.8)


# Quad piatto texturizzato appoggiato a un hex (marker d'area/terreno).
func _add_flat_marker(hx: Vector2i, tex: Texture2D, alpha: float,
		size: float = 1.55) -> void:
	if tex == null or not state.map.has(GameState.hex_key(hx.x, hx.y)):
		return
	var lv: int = state.map[GameState.hex_key(hx.x, hx.y)].level
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, alpha)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = _world_center(hx.x, hx.y, lv) + Vector3(0, 0.09, 0)
	_marker_root.add_child(mi)


func _update_info(hex: Vector2i) -> void:
	if _info_label == null:
		return
	if not state.map.has(GameState.hex_key(hex.x, hex.y)):
		_info_label.text = "(fuori mappa)"
		return
	var h: GameState.MapHex = state.map[GameState.hex_key(hex.x, hex.y)]
	var tname: String = D.Terrain.keys()[h.terrain]
	var txt := "Hex %02d,%02d — %s (quota %d)" % [hex.x, hex.y, tname, h.level]
	var c := state.character_at(hex.x, hex.y)
	if c != null and not c.is_dead():
		var who: String = c.display_name if c.side == D.Side.FRIENDLY or c.known \
			else "nemico non identificato"
		txt += "  •  " + who
	_info_label.text = txt


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.text = "MAPPA 3D (prototipo) — board: %s\n" % board_name \
		+ "trascina sx = orbita  •  rotella = zoom  •  trascina dx = pan\n" \
		+ "R = reset vista  •  1/2/3 = quote x1 / x2 / x3  •  S = scalini dolci/a picco"
	label.position = Vector2(12, 10)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	layer.add_child(label)
	# Lettura dell'hex sotto il puntatore (picking 3D, Fase 1).
	_info_label = Label.new()
	_info_label.text = "(passa il mouse / clicca un esagono)"
	_info_label.position = Vector2(12, 92)
	_info_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	_info_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_info_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(_info_label)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_distance = maxf(_distance * 0.9, 3.0)
					_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_distance = minf(_distance * 1.1, 2000.0)
					_update_camera()
			MOUSE_BUTTON_LEFT:
				_orbiting = event.pressed
				if event.pressed:
					_pick_at(event.position, true)  # clic = seleziona
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
	elif event is InputEventMouseMotion:
		if _orbiting:
			_yaw -= event.relative.x * 0.008
			_pitch = clampf(_pitch + event.relative.y * 0.008,
				deg_to_rad(8.0), deg_to_rad(89.0))
			_update_camera()
		elif not _panning:
			_pick_at(event.position)  # hover = evidenzia l'hex sotto il mouse
		if _panning:
			# Pan nel piano orizzontale relativo all'orientamento camera.
			var right := _camera.global_transform.basis.x
			var fwd := Vector3(sin(_yaw), 0, cos(_yaw))
			var k := _distance * 0.0016
			_pivot += (-right * event.relative.x + fwd * event.relative.y) * k
			_update_camera()
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_R:
				_yaw = 0.0
				_pitch = deg_to_rad(52.0)
				_distance = _home_distance
				_update_camera()
			KEY_1, KEY_2, KEY_3:
				_height_scale = float(event.keycode - KEY_0)
				_rebuild()
			KEY_S:
				_smooth = not _smooth  # scalini dolci <-> a picco
				_rebuild()


# Ricostruisce terreno + pedine (dopo aver cambiato la scala delle quote).
func _rebuild() -> void:
	for child in get_children():
		if child is MeshInstance3D or child is Sprite3D:
			child.queue_free()
	_highlight = null
	_sel_ring = null
	_picked = Vector2i(-99, -99)
	if _cue_root != null:
		for ch in _cue_root.get_children():
			ch.queue_free()
	_build_terrain()
	_build_units()
	_build_markers()
	if _selected != null:
		_update_sel_ring()  # ricrea la cornice sulla pedina ancora selezionata
	_update_camera()
