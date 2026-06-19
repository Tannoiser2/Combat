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
	const TOKEN_T := 0.14    # spessore del cartoncino
	var seen := {}           # conteggio per hex (stacking)
	for c in state.characters:
		if c == null or c.is_dead() or c.embarked:
			continue
		var lv := _level_at(c.position.x, c.position.y)
		var surface := _world_center(c.position.x, c.position.y, maxi(lv, 0))
		var key := GameState.hex_key(c.position.x, c.position.y)
		var idx: int = seen.get(key, 0)
		seen[key] = idx + 1
		var tex := _counter_tex(c.counter)
		var fb := Color(0.25, 0.50, 0.95) if c.side == D.Side.FRIENDLY \
			else Color(0.70, 0.32, 0.28)  # blu vivo (amico) / rosso-terra (nemico)
		var top_tex: Texture2D = tex if tex != null else _token_tex(fb)
		# Scostamento a cascata per le pile (Rule 8): si impilano in altezza.
		var off := Vector3(0.22 * idx, idx * TOKEN_T, 0.14 * idx)
		_add_counter(surface + off, TOKEN_W, TOKEN_T, top_tex)


# Un segnalino fisico: corpo con spessore (bordi cartoncino, proietta ombra)
# + faccia superiore con l'art della pedina. Appoggiato a 'base' (superficie hex).
func _add_counter(base: Vector3, w: float, t: float, top_tex: Texture2D) -> void:
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, t, w)
	body.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.88, 0.85, 0.78)  # taglio del cartoncino
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
	env.ambient_light_energy = 0.6
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
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
	elif event is InputEventMouseMotion:
		if _orbiting:
			_yaw -= event.relative.x * 0.008
			_pitch = clampf(_pitch + event.relative.y * 0.008,
				deg_to_rad(8.0), deg_to_rad(89.0))
			_update_camera()
		elif _panning:
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
	_build_terrain()
	_build_units()
	_update_camera()
