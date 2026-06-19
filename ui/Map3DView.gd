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

# Riuso la calibrazione della griglia da MapView (stesse costanti): origin e
# passo (cell) per board, cosi' 3D e 2D restano allineati pixel-per-pixel.
const PX_PER_UNIT := 100.0     # scala scansione->mondo (1 unita' = 100 px)
const LEVEL_HEIGHT := 0.55     # altezza in unita'-mondo per livello di quota

signal unit_activated(c: Character)  # emesso al clic su una pedina amica (Fase 3)

var board_name := "hill"
var state: GameState = null    # opzionale: per disegnare le pedine

var _board_tex: Texture2D
var _origin := Vector2.ZERO
var _cell := Vector2.ZERO
var _first_col := 1
var _height_scale := 1.0       # moltiplicatore quote (tasti 1/2/3)

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


func _ready() -> void:
	if not MapView.BOARDS.has(board_name):
		push_warning("Map3DView: board sconosciuta '%s', uso 'hill'" % board_name)
		board_name = "hill"
	var info: Dictionary = MapView.BOARDS[board_name]
	_origin = info["origin"]
	_cell = info.get("cell", MapView.CELL)
	if ResourceLoader.exists(info["file"]):
		_board_tex = load(info["file"])
	_build_environment()
	_build_terrain()
	_build_units()
	_build_camera()
	_build_hud()
	set_process_unhandled_input(true)
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
	else:
		_pick_at(get_viewport().get_visible_rect().size * 0.5, true)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot_path)
	get_tree().quit(0)


# Centro in pixel di una cella (col, riga): identico a MapView.hex_center.
func _hex_center_px(col: int, row: int) -> Vector2:
	var x := _origin.x + _cell.x * (col - _first_col)
	var y := _origin.y + _cell.y * (row + (0.5 if col % 2 == 0 else 0.0))
	return Vector2(x, y)


# Posizione mondo del centro di un hex alla sua quota.
func _world_center(col: int, row: int, level: int) -> Vector3:
	var px := _hex_center_px(col, row)
	return Vector3(px.x / PX_PER_UNIT, level * LEVEL_HEIGHT * _height_scale,
		px.y / PX_PER_UNIT)


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
			verts.append(Vector3(center.x + off.x, center.y, center.z + off.y))
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

		# Pareti: per ogni lato, se il vicino e' piu' basso (o assente) cala
		# un muro dal bordo superiore fino alla quota del vicino.
		var nb := _neighbors(col, row)
		for i in range(6):
			var nlv := _level_at(nb[i].x, nb[i].y)
			var base_lv: int = maxi(nlv, 0)
			if base_lv >= hex.level:
				continue  # vicino alla stessa quota o piu' alto: niente parete
			var j := (i + 1) % 6
			var top_a := verts[i]
			var top_b := verts[j]
			var by := base_lv * LEVEL_HEIGHT * _height_scale
			var bot_a := Vector3(top_a.x, by, top_a.z)
			var bot_b := Vector3(top_b.x, by, top_b.z)
			# Normale orizzontale uscente (verso l'esterno dell'hex).
			var mid := (top_a + top_b) * 0.5
			var n := Vector3(mid.x - center.x, 0, mid.z - center.z).normalized()
			# UV "colate": basso e alto condividono il pixel di bordo -> la
			# scansione si stira verticalmente lungo la parete (no blocco piatto).
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
		_add_counter(surface + off, TOKEN_W, TOKEN_T, top_tex, morale_col)


# Un segnalino fisico: corpo con spessore (bordi cartoncino, proietta ombra)
# + faccia superiore con l'art della pedina. Appoggiato a 'base' (superficie hex).
func _add_counter(base: Vector3, w: float, t: float, top_tex: Texture2D,
		border_color = null) -> void:
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, t, w)
	body.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.34, 0.31, 0.27)  # taglio del cartoncino (scuro, sottile)
	bmat.roughness = 0.95
	body.material_override = bmat
	body.position = base + Vector3(0, t * 0.5 + 0.02, 0)
	add_child(body)

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
	add_child(top)

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
		add_child(fr)


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
	var radius := _cell.x / 1.5 / PX_PER_UNIT * 1.01
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
	_highlight.mesh = st.commit()
	_highlight.visible = true


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
		+ "R = reset vista  •  1/2/3 = quote x1 / x2 / x3"
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


# Ricostruisce terreno + pedine (dopo aver cambiato la scala delle quote).
func _rebuild() -> void:
	for child in get_children():
		if child is MeshInstance3D or child is Sprite3D:
			child.queue_free()
	_highlight = null
	_sel_ring = null
	_picked = Vector2i(-99, -99)
	_build_terrain()
	_build_units()
	if _selected != null:
		_update_sel_ring()  # ricrea la cornice sulla pedina ancora selezionata
	_update_camera()
