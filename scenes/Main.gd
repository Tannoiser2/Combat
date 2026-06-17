## Scena principale: controller del gioco interattivo.
##
## Guida il giocatore lungo la Sequence of Play: gioca una Friendly Card
## dalla mano, assegna gli ordini ai propri uomini cliccandoli sulla
## mappa, poi scandisce fase nemica e impulsi col pulsante "Avanti".
## La logica resta tutta in engine/; qui solo input, HUD e regia.
##
## Controlli: click sinistro = seleziona hex/personaggio (in fase ordini,
## sui propri uomini apre il menu degli ordini); trascina con tasto
## destro/centrale = pan; rotella = zoom.
##
## Variabili d'ambiente di servizio:
## - COMBAT_AUTO=1: gioca da solo (per test senza interazione)
## - COMBAT_SCREENSHOT=path: salva screenshot a ogni avanzamento
extends Node

enum Phase { DEPLOY, CARD, ORDERS, ENEMY, ACTION, END_TURN, GAME_OVER }

var state: GameState
var map_view: MapView
var camera: Camera2D
var phase: int = Phase.CARD
var impulse_next := 1
var auto_play := false

var turn_label: Label
var hint_label: Label
var next_button: Button
var hand_panel: PanelContainer
var hand_box: HBoxContainer
var log_text: RichTextLabel
var info_text: RichTextLabel
# Diario: cronologia completa + filtro delle righe di dettaglio ("·",
# la formula del combattimento) attivabile dal toggle in testata.
var log_history: Array[String] = []
var log_show_detail := false
var order_panel: PanelContainer   # selettore ordini con spiegazioni
var order_list: VBoxContainer
var order_title_label: Label      # testo della barra-titolo (trascinabile)
var order_desc: RichTextLabel
var order_target: Character
var enemy_card_rect: TextureRect
var card_preview: TextureRect   # anteprima ingrandita della carta sotto il mouse
var roster_box: VBoxContainer   # elenco della squadra a sinistra (= roster_body)
var roster_body: VBoxContainer  # contenuto collassabile del roster
var roster_collapsed := false
var enemy_roster_box: VBoxContainer    # nemici noti (pannello destra)
var enemy_roster_body: VBoxContainer
var enemy_roster_collapsed := true
var overlay_legend: PanelContainer  # legenda dell'overlay terreno (tasto T)
var played_card_bar: PanelContainer  # banner carta giocata (ORDER phase in poi)
var played_card_text: RichTextLabel
var hand_discard_button: Button  # "Carte in mano (N)" visibile fuori dalla CARD phase
var discard_popup: PanelContainer  # popup con le DISCARD cards rimanenti
var vehicle_popup: PanelContainer  # Vehicle Display: equipaggio e stato del mezzo
var _display_vehicle: Character = null  # veicolo attualmente mostrato nel Vehicle Display
var _initiative_card_pending: bool = false  # carta Initiative giocata: attende click su un uomo

# Strumento LOS: il gioco si congela e due click tracciano una linea
# di vista tra hex qualsiasi (verde libera / rossa bloccata).
var los_button: Button
var editor_button: Button
var los_mode := false
# Touch input (mobile/iPad): traccia le dita attive per pan e pinch-zoom.
var _touch_points: Dictionary = {}
var los_hex_a := Vector2i(-99, -99)  # prima estremita' strumento LOS
var los_hex_b := Vector2i(-99, -99)  # seconda estremita'
var los_dragging := -1               # -1=nessuno, 0=trascina A, 1=trascina B

# Editor di mappa: pannello pittura terreno (tasto E).
var editor_panel: PanelContainer
var editor_brush: int = -1        # >= 0 = terreno hex da dipingere
var editor_is_hexside: bool = false  # true = si dipinge lato (hexside)
var editor_hexside_brush: int = -1   # >= 0 = tipo lato; -1 = rimuovi lato

# Action Phase interattiva: coda di attivazione e personaggio in attesa
# di una scelta del giocatore (fuoco/movimento).
var action_queue: Array = []
var acting: Character = null
var action_kind: int = 0   # TurnSequence.Act
var moves_left: int = 0

# Selezione ciclica delle pedine impilate (stacking, Rule 8): riclicca lo
# stesso hex per passare all'uomo successivo nella pila.
var _stack_cycle_hex := Vector2i(-99, -99)
var _stack_cycle_i := 0

# Fase di schieramento: uomini ancora da piazzare e zona valida.
var deploy_queue: Array = []
var deploy_zone: Array[Vector2i] = []

# Replay: riproduzione dei frame registrati dal motore (Replay.gd).
# Ogni frame = un impulse, con tutte le azioni animate in simultanea.
var replay_button: Button
var replay_frames: Array = []
var _large_battle_override: Dictionary = {}  # sid -> bool (override toggle UI)
var replay_idx := -1            # -1 = nessun replay in corso
var replay_t := 0.0
var replay_events: Array = []   # colpi/boom/suoni del frame, ordinati per "at"
var replay_evt_idx := 0
var replay_hidden_banner: CanvasLayer = null   # banner di vittoria sospeso
const REPLAY_MOVE_T := 1.3      # durata della parte di movimento (frame impulse)
const REPLAY_TURN_T := 2.6      # durata di un TURNO fuso (replay partita)
const REPLAY_PAUSE_T := 0.6     # coda del frame (esiti dei colpi)

# Audio: player per tipo di suono (nil se il file non e' installato).
var _sfx: Dictionary = {}
const WEAPON_SFX := {
	"M1 Garand": "garand", "KAR 98K": "kar98", "Rifle": "kar98",
	"M3 Grease Gun": "smg", "MP40": "smg", "SMG": "smg",
	"M1 Thompson": "thompson", "StG 44": "stg44",
	"M1903 Springfield": "springfield",
	"Thrown Knife": "throw",
	"BAR": "bar", "M1919": "m1919", "MG42": "mg42", "MG34 Vehicle": "mg42",
	"M1911": "pistol", "P38": "pistol",
	"M7 Grenade Launcher": "grenade",
	# Rule 31-32: armi anticarro e cannoni.
	"Bazooka M9": "grenade", "Panzerfaust 60": "grenade", "Panzerfaust 100": "grenade",
	"75mm L40 HE": "artillery", "75mm L40 AP": "artillery",
	"KwK 7.5cm HE": "artillery", "KwK 7.5cm AP": "artillery",
	"M2 .50cal": "m1919",
}
const AREA_SFX := {
	Area.Type.GRENADE: "grenade",   Area.Type.MORTAR_60: "grenade",
	Area.Type.MORTAR_81: "artillery", Area.Type.ARTILLERY_105: "artillery",
	Area.Type.C4: "artillery",
	Area.Type.SMOKE: "smoke",
}
# Esito del fuoco (Fire.fire_action) -> suono di reazione.
const OUTCOME_SFX := {
	"Ucciso!": "kill", "Ferito!": "wound",
	"Soppresso!": "suppress", "Colpito!": "suppress", "Mancato": "miss",
}


func _ready() -> void:
	if not OS.get_environment("COMBAT_SELFTEST").is_empty():
		_selftest()
		return
	if not OS.get_environment("COMBAT_BALANCE").is_empty():
		_balance_test()
		return
	auto_play = not OS.get_environment("COMBAT_AUTO").is_empty()
	if auto_play:
		# Modalita' test: parte subito (scenario da env, default intro1).
		var sid := OS.get_environment("COMBAT_SCENARIO")
		_start_scenario(sid if not sid.is_empty() else "intro1")
		var timer := Timer.new()
		timer.wait_time = 0.4
		timer.timeout.connect(_auto_step)
		add_child(timer)
		timer.start()
	else:
		_show_scenario_menu()


# Avvia (o riavvia) uno scenario: stato nuovo, mappa, camera, HUD.
func _start_scenario(scenario_id: String) -> void:
	for child in get_children():
		child.queue_free()
	log_history.clear()
	state = GameState.new()
	# Seed fisso per partite riproducibili; COMBAT_SEED per variarlo
	# (nei test) o "time" per una partita sempre diversa.
	var seed_env := OS.get_environment("COMBAT_SEED")
	if seed_env == "time" or (seed_env.is_empty() and not auto_play):
		state.rng.randomize()
	elif not seed_env.is_empty():
		state.rng.seed = hash(seed_env)
	else:
		state.rng.seed = hash("combat-test")
	Scenario.build(state, scenario_id)
	# Override Grande Battaglia dal toggle UI (se il giocatore l'ha cambiato).
	if _large_battle_override.has(scenario_id):
		state.large_battle = _large_battle_override[scenario_id]

	map_view = MapView.new()
	# Con la scansione in assets/maps si gioca sull'artwork vero; senza
	# la mappa viene disegnata proceduralmente dal terreno di Boards.gd.
	if not map_view.load_board(Scenario.SCENARIOS[scenario_id]["map"]):
		print("Scansione non trovata: mappa in modalita' procedurale")
	map_view.state = state
	add_child(map_view)

	# Camera centrata sulla squadra.
	camera = Camera2D.new()
	var centroid := Vector2.ZERO
	var n := 0
	for c in state.characters:
		if c.side == Domain.Side.FRIENDLY:
			centroid += map_view.hex_center(c.position.x, c.position.y)
			n += 1
	camera.position = centroid / maxf(1.0, float(n))
	var z := 60.0 / map_view.cell.x
	camera.zoom = Vector2(z, z)
	add_child(camera)
	_load_sfx()
	_build_hud()
	# Fase di schieramento, se lo scenario ha una zona e siamo interattivi.
	deploy_zone = Scenario.deploy_hexes(state, scenario_id)
	if not auto_play and not deploy_zone.is_empty():
		_start_deploy()
	else:
		_start_turn()


# --------------------------------------------------------- audio

func _load_sfx() -> void:
	_sfx.clear()
	for s in ["rifle", "mg", "pistol", "grenade", "artillery", "melee", "scream",
			"garand", "kar98", "mg42", "m1919", "bar", "smg",
			"thompson", "springfield", "stg44",
			"kill", "wound", "suppress", "miss", "throw",
			"vehicle", "click"]:
		var path := "res://assets/audio/%s.ogg" % s
		if ResourceLoader.exists(path):
			var p := AudioStreamPlayer.new()
			p.stream = load(path)
			p.max_polyphony = 3
			add_child(p)
			_sfx[s] = p

func _play_sfx(key: String) -> void:
	if _sfx.has(key):
		_sfx[key].play()

func _consume_audio_events() -> void:
	for ev in state.audio_events:
		match ev["type"]:
			"shot":
				_play_sfx(WEAPON_SFX.get(ev["weapon"], "rifle"))
				_play_sfx(OUTCOME_SFX.get(ev.get("outcome", ""), ""))
			"boom":  _play_sfx(AREA_SFX.get(ev["area_type"], "artillery"))
			"melee": _play_sfx("melee")
			"scream": _play_sfx("scream")
			"throw": _play_sfx("throw")
			"vehicle":  _play_sfx("vehicle")
	state.audio_events.clear()


# --------------------------------------------------------- schieramento

# Il giocatore piazza i suoi uomini uno per uno nella zona evidenziata.
func _start_deploy() -> void:
	phase = Phase.DEPLOY
	deploy_queue = []
	for c in state.characters:
		if c.side == Domain.Side.FRIENDLY:
			deploy_queue.append(c)
	map_view.cue_hexes = deploy_zone
	map_view.cue_color = Color(0.3, 0.7, 0.95, 0.9)
	_prompt_deploy()
	next_button.text = "Posizioni standard"
	next_button.disabled = false
	hand_panel.hide()
	_refresh()


func _prompt_deploy() -> void:
	if deploy_queue.is_empty():
		map_view.cue_hexes = []
		_start_turn()
		return
	var c: Character = deploy_queue[0]
	map_view.selected = c
	hint_label.text = "Schieramento: piazza %s su un hex azzurro" % c.display_name
	map_view.queue_redraw()


func _handle_deploy_click(hex: Vector2i) -> void:
	if not hex in deploy_zone:
		return
	if state.character_at(hex.x, hex.y) != null:
		return  # occupato
	var c: Character = deploy_queue.pop_front()
	c.position = hex
	_refresh()
	_prompt_deploy()


# ------------------------------------------------------- menu scenari

func _show_scenario_menu() -> void:
	var hud := CanvasLayer.new()
	hud.name = "menu"
	add_child(hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = _make_theme()
	hud.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.10, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	# Due colonne: copertina a sinistra, card delle missioni a destra.
	var split := HBoxContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	split.offset_left = 60
	split.offset_right = -60
	split.offset_top = 30
	split.offset_bottom = -30
	split.add_theme_constant_override("separation", 40)
	root.add_child(split)

	# --- colonna sinistra: copertina (o titolo di ripiego) + build tag
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(440, 0)
	left.add_theme_constant_override("separation", 10)
	split.add_child(left)
	if ResourceLoader.exists("res://assets/menu/cover.jpg"):
		var cover := TextureRect.new()
		cover.texture = load("res://assets/menu/cover.jpg")
		cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cover.size_flags_vertical = Control.SIZE_EXPAND_FILL
		left.add_child(cover)
	else:
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		left.add_child(spacer)
		var title := Label.new()
		title.text = "COMBAT!"
		title.add_theme_font_size_override("font_size", 84)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		left.add_child(title)
		var sub := Label.new()
		sub.text = "Volume 1 - Normandia, 1944\n\nUn solitario tattico uomo-a-uomo.\nTu guidi la squadra: il sistema\ncomanda il nemico."
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.modulate = Color(0.8, 0.8, 0.7)
		left.add_child(sub)
		var spacer2 := Control.new()
		spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
		left.add_child(spacer2)
	var tag := Label.new()
	tag.text = "build: " + _build_tag()
	tag.modulate = Color(0.55, 0.55, 0.50)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(tag)
	# Changelog della build: cosa c'e' di nuovo, per riconoscere la versione.
	if FileAccess.file_exists("res://changelog.txt"):
		var clog := RichTextLabel.new()
		clog.text = FileAccess.get_file_as_string("res://changelog.txt").strip_edges()
		clog.custom_minimum_size = Vector2(0, 170)
		clog.add_theme_font_size_override("normal_font_size", 12)
		clog.modulate = Color(0.65, 0.65, 0.58)
		clog.scroll_active = true
		left.add_child(clog)

	# --- colonna destra: card scorrevoli delle missioni
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	split.add_child(right)
	var head := Label.new()
	head.text = "SCEGLI LA MISSIONE"
	head.add_theme_font_size_override("font_size", 22)
	head.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
	right.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for sid in Scenario.SCENARIOS:
		list.add_child(_mission_card(hud, sid))
	_maybe_screenshot()


# Card di missione: thumbnail della mappa + titolo + sottotitolo + sinossi.
func _mission_card(menu: CanvasLayer, sid: String) -> Button:
	var sc: Dictionary = Scenario.SCENARIOS[sid]
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 104)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.pressed.connect(func():
		menu.queue_free()
		_start_scenario(sid))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -8
	row.offset_top = 6
	row.offset_bottom = -6
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var thumb_path := "res://assets/menu/thumb_%s.jpg" % sc["map"]
	if ResourceLoader.exists(thumb_path):
		var thumb := TextureRect.new()
		thumb.texture = load(thumb_path)
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		thumb.custom_minimum_size = Vector2(140, 0)
		thumb.clip_contents = true
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(thumb)
	var txt := VBoxContainer.new()
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(txt)
	var name := Label.new()
	name.text = sc["name"]
	name.add_theme_font_size_override("font_size", 18)
	name.add_theme_color_override("font_color", Color(0.95, 0.90, 0.65))
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	txt.add_child(name)
	var meta := Label.new()
	var n_men: int = (Scenario.FULL_SQUAD.size() if sc.get("squad_full", false)
		else Scenario.FULL_SQUAD_VOL2.size() if sc.get("squad_vol2", false)
		else sc.get("friendly", []).size())
	meta.text = "%s - %d turni - %d uomini" % [sc["map"].capitalize(), sc["turns"], n_men]
	meta.add_theme_font_size_override("font_size", 12)
	meta.modulate = Color(0.7, 0.72, 0.6)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	txt.add_child(meta)
	var desc := Label.new()
	desc.text = String(sc.get("desc", "")).replace("\n", " ")
	desc.add_theme_font_size_override("font_size", 13)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.modulate = Color(0.85, 0.85, 0.78)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	txt.add_child(desc)
	# Toggle Grande Battaglia (Rule 9.2) per scenari con piu' di un team.
	if sc.get("cup_spec", {}).size() > 1:
		var gb := CheckButton.new()
		gb.text = "Grande Battaglia (Rule 9.2)"
		gb.button_pressed = _large_battle_override.get(sid, sc.get("large_battle", false))
		gb.add_theme_font_size_override("font_size", 11)
		gb.modulate = Color(0.85, 0.78, 0.55)
		gb.mouse_filter = Control.MOUSE_FILTER_STOP
		gb.toggled.connect(func(v: bool) -> void: _large_battle_override[sid] = v)
		txt.add_child(gb)
	return card


func _build_tag() -> String:
	if FileAccess.file_exists("res://build_tag.txt"):
		return FileAccess.get_file_as_string("res://build_tag.txt").strip_edges()
	return "dev locale"


# ---------------------------------------------------------------- fasi

func _start_turn() -> void:
	phase = Phase.CARD
	acting = null
	map_view.cue_hexes = []
	if replay_button != null:
		replay_button.disabled = true
	TurnSequence.friendly_card_phase_prepare(state)
	_show_hand()
	next_button.disabled = true
	next_button.text = "Avanti"
	hint_label.text = "Friendly Card Phase: scegli una carta dalla mano e giocala"
	_initiative_card_pending = false
	played_card_bar.hide()
	if hand_discard_button != null:
		hand_discard_button.hide()
	if discard_popup != null:
		discard_popup.hide()
	_refresh()


func _on_card_chosen(index: int) -> void:
	if phase != Phase.CARD:
		return
	TurnSequence.friendly_card_play(state, index)
	hand_panel.hide()
	phase = Phase.ORDERS
	hint_label.text = "Order Phase: clicca i tuoi uomini e assegna gli ordini"
	_update_played_card_bar()
	_update_orders_button()
	_refresh()


func _on_next_pressed() -> void:
	# Durante un replay il pulsante lo salta.
	if replay_idx >= 0:
		_end_replay()
		return
	# In schieramento: "Posizioni standard" = accetta i default del libro.
	if phase == Phase.DEPLOY:
		deploy_queue = []
		map_view.cue_hexes = []
		_start_turn()
		return
	# Durante l'attesa di un'azione friendly, il pulsante = "passa/fine".
	if acting != null:
		# Veicolo in fase di fuoco Gunner: risolvi bow MG prima di passare.
		if acting.is_vehicle and action_kind == TurnSequence.Act.FIRE:
			TurnSequence.resolve_vehicle_bow_mg(state, acting)
			_consume_audio_events()
		_finish_friendly_action()
		return
	match phase:
		Phase.ORDERS:
			order_panel.hide()
			phase = Phase.ENEMY
			TurnSequence.friendly_order_phase(state)
			TurnSequence.enemy_order_phase(state)
			hint_label.text = "Enemy Card Phase: ordini del nemico assegnati"
			next_button.text = "Inizia azione"
			_refresh()
		Phase.ENEMY:
			phase = Phase.ACTION
			impulse_next = 1
			state.impulse = 1
			state.shots.clear()
			state.move_paths.clear()
			state.booms.clear()
			state.melee_events.clear()
			state.audio_events.clear()
			state.log_event("--- Impulse 1 ---")
			action_queue = TurnSequence.impulse_order(state)
			_advance_action()
		Phase.END_TURN:
			_start_turn()


# Percorre la coda dell'impulse: i nemici (e i friendly in demo) agiscono
# da soli; sui friendly con un'azione discrezionale si ferma e passa la
# scelta al giocatore (fuoco/movimento).
func _advance_action() -> void:
	while true:
		if action_queue.is_empty():
			impulse_next += 1
			if impulse_next > 4:
				_end_action_phase()
				return
			state.impulse = impulse_next
			state.shots.clear()
			state.move_paths.clear()
			state.audio_events.clear()
			state.log_event("--- Impulse %d ---" % impulse_next)
			action_queue = TurnSequence.impulse_order(state)
			continue
		var c: Character = action_queue.pop_front()
		if c.is_dead():
			continue
		TurnSequence.activate_passive(state, c)
		var act := TurnSequence.discretionary_action(c, state.impulse, state)
		if c.side == Domain.Side.FRIENDLY and not auto_play and not c.is_dead() \
				and _has_options(c, act):
			_begin_friendly_action(c, act)
			_refresh()
			return
		TurnSequence.resolve_action(state, c)
		_consume_audio_events()
	# (non raggiunto)


func _begin_friendly_action(c: Character, act: Dictionary) -> void:
	acting = c
	action_kind = act["kind"]
	moves_left = act["hexes"]
	map_view.selected = c
	_refresh_roster()
	_refresh_enemy_roster()
	if action_kind == TurnSequence.Act.FIRE:
		var targets := TurnSequence.valid_fire_targets(state, c)
		map_view.cue_hexes = _hexes_of(targets)
		map_view.cue_color = Color(0.95, 0.55, 0.05, 0.95)
		map_view.fire_lines_source = c.position
		hint_label.text = "%s: clicca un bersaglio (arancio) o premi Passa" % c.display_name
		next_button.text = "Passa"
	elif action_kind == TurnSequence.Act.THROW:
		var throw_hexes := TurnSequence.valid_throw_hexes(state, c)
		map_view.cue_hexes = throw_hexes
		map_view.cue_color = Color(0.95, 0.6, 0.15, 0.9)
		var r := TurnSequence.throw_range(c)
		if throw_hexes.is_empty():
			hint_label.text = "%s: nessun hex valido (gittata %d-%d hex, LOS necessaria)" % [
				c.display_name, r[0], r[1]]
		else:
			hint_label.text = "%s: clicca l'hex bersaglio arancio (%d-%d hex, LOS necessaria) o premi Passa" % [
				c.display_name, r[0], r[1]]
		next_button.text = "Passa"
	else:
		map_view.cue_hexes = _passable_neighbors(c)
		map_view.cue_color = Color(0.3, 0.9, 0.3, 0.9)
		hint_label.text = "%s: muovi (%d) su un hex verde o premi Fine" % [
			c.display_name, moves_left]
		next_button.text = "Fine mossa"
	next_button.disabled = false


func _finish_friendly_action() -> void:
	acting = null
	map_view.cue_hexes = []
	map_view.fire_lines_source = Vector2i(-99, -99)
	_advance_action()


func _end_action_phase() -> void:
	TurnSequence.end_phase(state)
	# Le granate esplodono in End Phase: senza questo i boom non suonano
	# mai (gli eventi venivano azzerati all'impulse 1 del turno dopo).
	_consume_audio_events()
	replay_button.disabled = false
	if state.game_over:
		phase = Phase.GAME_OVER
		var v := Scenario.victory(state, state.scenario_id)
		hint_label.text = "Fine partita: %s" % v["outcome"]
		state.log_event("=== %s === %s" % [v["outcome"], v["detail"]])
		next_button.text = "Partita finita"
		next_button.disabled = true
		if not auto_play:
			_show_victory_banner(v)
	else:
		phase = Phase.END_TURN
		hint_label.text = "End Phase: ordini rimossi (Replay turno per rivederlo)"
		next_button.text = "Turno %d" % state.turn
		next_button.disabled = false
	_refresh()


# Banner di fine partita con esito, VP e ritorno al menu.
func _show_victory_banner(v: Dictionary) -> void:
	var hud := CanvasLayer.new()
	hud.layer = 10
	add_child(hud)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	hud.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(520, 0)
	panel.add_child(box)
	var title := Label.new()
	title.text = v["outcome"]
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var win := "vittoria" in String(v["outcome"]).to_lower()
	title.modulate = Color(0.5, 0.95, 0.4) if win else Color(0.95, 0.45, 0.35)
	box.add_child(title)
	var detail := Label.new()
	detail.text = v["detail"]
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail)
	var rewatch := Button.new()
	rewatch.text = "Rivedi la partita"
	rewatch.custom_minimum_size = Vector2(0, 48)
	rewatch.pressed.connect(func():
		hud.hide()
		replay_hidden_banner = hud
		_start_replay(_merge_turn_frames(state.replay)))
	box.add_child(rewatch)
	var back := Button.new()
	back.text = "Torna al menu"
	back.custom_minimum_size = Vector2(0, 48)
	back.pressed.connect(func():
		for child in get_children():
			child.queue_free()
		_show_scenario_menu())
	box.add_child(back)


func _hexes_of(chars: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in chars:
		out.append(c.position)
	return out


func _passable_neighbors(c: Character) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for n in Move.neighbors(state, c.position):
		if Move.can_enter(state, c, n):
			out.append(n)
	return out


# C'e' davvero una scelta da fare (bersagli o hex liberi)?
func _has_options(c: Character, act: Dictionary) -> bool:
	match act["kind"]:
		TurnSequence.Act.FIRE:
			return not TurnSequence.valid_fire_targets(state, c).is_empty()
		TurnSequence.Act.MOVE:
			return not _passable_neighbors(c).is_empty()
		TurnSequence.Act.THROW:
			return not TurnSequence.valid_throw_hexes(state, c).is_empty()
		_:
			return false




# --------------------------------------------------------------- replay

# Replay del turno appena concluso (a fine partita: dell'ultimo turno).
# Usa _merge_turn_frames per animare il turno come flusso continuo
# (stesso effetto cinematografico del replay di fine partita).
func _on_replay_turn() -> void:
	var tno := state.turn - 1
	var frames := state.replay.filter(func(f): return f["turn"] == tno)
	_start_replay(_merge_turn_frames(frames))


func _start_replay(frames: Array) -> void:
	if frames.is_empty() or replay_idx >= 0:
		hint_label.text = "Niente da rivedere"
		return
	replay_frames = frames
	replay_idx = 0
	map_view.replay_mode = true
	map_view.selected = null
	map_view.cue_hexes = []
	map_view.los_lines = []
	order_panel.hide()
	replay_button.disabled = true
	next_button.text = "Salta replay"
	next_button.disabled = false
	_replay_apply(frames[0])


# Fonde i frame per-impulse di ogni turno in un unico frame continuo
# (per il replay dell'intera partita): tutti i percorsi del turno
# animati in simultanea sulla stessa durata - chi ha fatto piu' strada
# si muove piu' veloce - con colpi/boom/suoni programmati al momento
# dell'impulso in cui sono avvenuti ("at" = frazione del turno).
func _merge_turn_frames(frames: Array) -> Array:
	var out: Array = []
	for f in frames:
		if out.is_empty() or out.back()["turn"] != f["turn"]:
			out.append({
				"turn": f["turn"], "impulse": 0, "merged": true,
				"units": {}, "moves": {}, "shots": [], "booms": [], "sfx": [],
			})
		var m: Dictionary = out.back()
		var at := (float(f["impulse"]) - 0.5) / 4.0
		for idx in f["units"]:
			if not m["units"].has(idx):
				m["units"][idx] = f["units"][idx]
		for idx in f["moves"]:
			var path: Array = f["moves"][idx]
			if not m["moves"].has(idx):
				m["moves"][idx] = path.duplicate()
			else:
				var done: Array = m["moves"][idx]
				m["moves"][idx] = done + (path.slice(1) if done.back() == path[0] else path)
		for s in f["shots"]:
			var s2: Dictionary = s.duplicate()
			s2["at"] = at
			m["shots"].append(s2)
		for b in f["booms"]:
			var b2: Dictionary = b.duplicate()
			b2["at"] = at
			m["booms"].append(b2)
		for key in f.get("sfx", []):
			m["sfx"].append({"key": key, "at": at})
	return out


func _replay_apply(f: Dictionary) -> void:
	replay_t = 0.0
	# Coda degli eventi del frame, ciascuno al suo istante "at" (frazione
	# della durata; nei frame per-impulse tutto a meta' corsa).
	replay_events = []
	replay_evt_idx = 0
	for s in f["shots"]:
		replay_events.append({"at": s.get("at", 0.5), "kind": "shot", "data": s})
	for b in f["booms"]:
		replay_events.append({"at": b.get("at", 0.5), "kind": "boom", "data": b})
	for e in f.get("sfx", []):
		if e is Dictionary:
			replay_events.append({"at": e["at"], "kind": "sfx", "data": e["key"]})
		else:
			replay_events.append({"at": 0.5, "kind": "sfx", "data": e})
	replay_events.sort_custom(func(a, b): return a["at"] < b["at"])
	map_view.replay_units = f["units"]
	map_view.replay_paths = f["moves"]
	map_view.replay_progress = 0.0
	if f.get("merged", false):
		hint_label.text = "REPLAY - Turno %d   (%d/%d)" % [
			f["turn"], replay_idx + 1, replay_frames.size()]
	else:
		hint_label.text = "REPLAY - Turno %d, Impulse %d   (%d/%d)" % [
			f["turn"], f["impulse"], replay_idx + 1, replay_frames.size()]
	_maybe_screenshot()


# Scandisce il replay: movimento simultaneo, con gli eventi (colpi,
# esplosioni, suoni) al loro istante. I frame si incatenano senza pause
# (i traccianti sopravvivono al cambio frame per conto loro); solo
# l'ultimo lascia una coda per gli esiti.
func _process(delta: float) -> void:
	if replay_idx < 0:
		return
	replay_t += delta
	var f: Dictionary = replay_frames[replay_idx]
	var has_moves: bool = not f["moves"].is_empty()
	var has_fx: bool = not replay_events.is_empty()
	var move_t: float
	if f.get("merged", false):
		move_t = REPLAY_TURN_T if has_moves else (0.9 if has_fx else 0.3)
	else:
		move_t = REPLAY_MOVE_T if has_moves else (0.7 if has_fx else 0.2)
	map_view.replay_progress = clampf(replay_t / move_t, 0.0, 1.0)
	while replay_evt_idx < replay_events.size() \
			and replay_t >= replay_events[replay_evt_idx]["at"] * move_t:
		var ev: Dictionary = replay_events[replay_evt_idx]
		replay_evt_idx += 1
		match ev["kind"]:
			"shot":
				map_view.add_tracer(ev["data"])
				_play_sfx(WEAPON_SFX.get(ev["data"].get("weapon", ""), "rifle"))
				_play_sfx(OUTCOME_SFX.get(ev["data"].get("outcome", ""), ""))
			"boom":
				map_view.add_blast(ev["data"]["hex"])
				_play_sfx(AREA_SFX.get(ev["data"]["type"], "artillery"))
			"sfx":
				_play_sfx(ev["data"])
	var last: bool = replay_idx == replay_frames.size() - 1
	var tail: float = (REPLAY_PAUSE_T + 1.2) if last and has_fx else 0.0
	if replay_t >= move_t + tail:
		replay_idx += 1
		if replay_idx >= replay_frames.size():
			_end_replay()
		else:
			_replay_apply(replay_frames[replay_idx])


func _end_replay() -> void:
	replay_idx = -1
	replay_frames = []
	map_view.replay_mode = false
	map_view.replay_units = {}
	map_view.replay_paths = {}
	map_view.queue_redraw()
	hint_label.text = "Replay terminato"
	match phase:
		Phase.END_TURN:
			next_button.text = "Turno %d" % state.turn
			next_button.disabled = false
			replay_button.disabled = false
		Phase.GAME_OVER:
			next_button.text = "Partita finita"
			next_button.disabled = true
			replay_button.disabled = false
			if replay_hidden_banner != null:
				replay_hidden_banner.show()
	replay_hidden_banner = null


# ---------------------------------------------------------------- input

# Gestione touch (iPad/mobile): intercetta i gesti PRIMA dei nodi figli.
# _input ha priorita' massima: i Control della HUD non possono consumare questi eventi.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_points[event.index] = event.position
		else:
			_touch_points.erase(event.index)
		# NON marcare come handled: il rilascio del tocco deve generare il clic sulla mappa
		# tramite l'emulazione MouseButton che Godot inietta per i Control.
	elif event is InputEventScreenDrag:
		if _touch_points.size() >= 2:
			# Pinch-zoom: prende qualunque altra dita nel dict (indipendente dall'indice).
			var other_pos := Vector2.ZERO
			for k: int in _touch_points:
				if k != event.index:
					other_pos = _touch_points[k]
					break
			var old_pos: Vector2 = event.position - event.relative
			var old_dist: float = old_pos.distance_to(other_pos)
			var new_dist: float = event.position.distance_to(other_pos)
			if old_dist > 1.0:
				_zoom(new_dist / old_dist)
		else:
			# Una sola dita: pan della mappa.
			camera.position -= event.relative / camera.zoom.x
		_touch_points[event.index] = event.position
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	# Tasto F: adatta la vista all'intera mappa.
	if event is InputEventKey and event.pressed and event.keycode == KEY_F \
			and map_view != null:
		_fit_map()
		return
	# Tasto T: overlay di verifica del terreno (confronto con la scansione).
	if event is InputEventKey and event.pressed and event.keycode == KEY_T \
			and map_view != null:
		map_view.debug_terrain = not map_view.debug_terrain
		map_view.queue_redraw()
		overlay_legend.visible = map_view.debug_terrain
		hint_label.text = "Overlay terreno: %s (T per cambiare)" % \
			("ON - confronta i colori con la mappa" if map_view.debug_terrain else "off")
		return
	# Tasto E: editor di mappa (pittura terreno + slider opacita').
	if event is InputEventKey and event.pressed and event.keycode == KEY_E \
			and map_view != null:
		map_view.editor_mode = not map_view.editor_mode
		editor_panel.visible = map_view.editor_mode
		map_view.debug_terrain = map_view.editor_mode
		overlay_legend.visible = false
		map_view.queue_redraw()
		hint_label.text = "Editor mappa: %s (E per uscire)" % \
			("ON — clicca hex + trascina per dipingere terreno" if map_view.editor_mode else "off")
		if editor_button != null:
			editor_button.set_pressed_no_signal(map_view.editor_mode)
		return
	# Tasto A: overlay archi di blindatura (Front/Rear) sul veicolo selezionato.
	if event is InputEventKey and event.pressed and event.keycode == KEY_A \
			and map_view != null:
		map_view.show_arc_overlay = not map_view.show_arc_overlay
		map_view.queue_redraw()
		hint_label.text = "Archi di blindatura: %s (A per nascondere)" % \
			("ON" if map_view.show_arc_overlay else "off")
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_points[event.index] = event.position
		else:
			_touch_points.erase(event.index)
	elif event is InputEventScreenDrag:
		var other_idx: int = 0 if event.index == 1 else 1
		if other_idx in _touch_points:
			# Pinch-zoom: confronta distanza vecchia vs nuova tra le due dita.
			var old_pos: Vector2 = event.position - event.relative
			var other_pos: Vector2 = _touch_points[other_idx]
			var old_dist: float = old_pos.distance_to(other_pos)
			var new_dist: float = event.position.distance_to(other_pos)
			if old_dist > 1.0:
				_zoom(new_dist / old_dist)
		else:
			# Una sola dita: pan della mappa.
			camera.position -= event.relative / camera.zoom.x
		_touch_points[event.index] = event.position
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(1.15)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(1.0 / 1.15)
			MOUSE_BUTTON_LEFT:
				if los_mode and map_view != null:
					_los_handle_press(map_view.get_local_mouse_position())
				else:
					_on_map_clicked()
	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and los_mode:
			los_dragging = -1
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT and map_view != null:
			if map_view.editor_mode:
				_editor_act(map_view.get_local_mouse_position())
			elif los_mode and los_dragging >= 0:
				_los_drag_update(map_view.get_local_mouse_position())
		if event.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
			camera.position -= event.relative / camera.zoom.x


func _zoom(factor: float) -> void:
	var z: float = clamp(camera.zoom.x * factor, 0.15, 2.5)
	camera.zoom = Vector2(z, z)


func _fit_map() -> void:
	if map_view == null or state == null or state.map.is_empty():
		return
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for key in state.map:
		var p: PackedStringArray = String(key).split(",")
		var c: Vector2 = map_view.hex_center(int(p[0]), int(p[1]))
		mn = mn.min(c)
		mx = mx.max(c)
	var pad: float = map_view.cell.x * 1.2
	mn -= Vector2(pad, pad)
	mx += Vector2(pad, pad)
	var bounds: Vector2 = mx - mn
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var z: float = clampf(minf(vp.x / bounds.x, vp.y / bounds.y), 0.15, 2.5)
	camera.position = (mn + mx) * 0.5
	camera.zoom = Vector2(z, z)


# Strumento LOS: ON mostra due estremita' trascinabili con LOS in tempo reale.
func _on_los_toggled(on: bool) -> void:
	los_mode = on
	los_dragging = -1
	map_view.los_tool = {}
	next_button.disabled = on
	if on and state != null and not state.map.is_empty():
		# Posiziona le estremita' agli estremi della mappa (angolo top-left / bottom-right).
		var mn := Vector2i(9999, 9999)
		var mx := Vector2i(-9999, -9999)
		for key in state.map:
			var parts: PackedStringArray = (key as String).split(",")
			var h := Vector2i(int(parts[0]), int(parts[1]))
			if h.x < mn.x or (h.x == mn.x and h.y < mn.y): mn = h
			if h.x > mx.x or (h.x == mx.x and h.y > mx.y): mx = h
		los_hex_a = mn
		los_hex_b = mx
		_los_update()
		hint_label.text = "LOS: trascina i cerchi — %02d.%02d → %02d.%02d" % [mn.x, mn.y, mx.x, mx.y]
	else:
		los_hex_a = Vector2i(-99, -99)
		los_hex_b = Vector2i(-99, -99)
		hint_label.text = "Strumento LOS chiuso"
	map_view.queue_redraw()


func _los_handle_press(local_pos: Vector2) -> void:
	var snap := MapView.HEX_SIZE * 0.9
	var pa := map_view.hex_center(los_hex_a.x, los_hex_a.y)
	var pb := map_view.hex_center(los_hex_b.x, los_hex_b.y)
	if local_pos.distance_to(pa) <= snap:
		los_dragging = 0
	elif local_pos.distance_to(pb) <= snap:
		los_dragging = 1
	else:
		# Click lontano: sposta l'estremita' piu' vicina a quell'hex.
		var hex := map_view.pick_hex(local_pos)
		if hex.x <= -99:
			return
		if local_pos.distance_to(pa) <= local_pos.distance_to(pb):
			los_hex_a = hex
		else:
			los_hex_b = hex
		_los_update()


func _los_drag_update(local_pos: Vector2) -> void:
	var hex := map_view.pick_hex(local_pos)
	if hex.x <= -99:
		return
	if los_dragging == 0:
		los_hex_a = hex
	else:
		los_hex_b = hex
	_los_update()


func _los_update() -> void:
	if los_hex_a.x <= -99 or los_hex_b.x <= -99:
		return
	var free := LOS.clear_hexes(state, los_hex_a, los_hex_b)
	map_view.los_tool = {
		"from": map_view.hex_center(los_hex_a.x, los_hex_a.y),
		"to": map_view.hex_center(los_hex_b.x, los_hex_b.y),
		"clear": free,
	}
	hint_label.text = "LOS %02d.%02d → %02d.%02d: %s" % [
		los_hex_a.x, los_hex_a.y, los_hex_b.x, los_hex_b.y,
		"LIBERA" if free else "BLOCCATA"]
	map_view.queue_redraw()


func _on_map_clicked() -> void:
	if replay_idx >= 0:
		return
	var hex := map_view.pick_hex(map_view.get_local_mouse_position())
	if hex.x <= -99:
		return
	_play_sfx("click")
	if map_view.editor_mode:
		_editor_act(map_view.get_local_mouse_position())
		return
	if phase == Phase.DEPLOY:
		_handle_deploy_click(hex)
		return
	# Durante l'azione di un proprio uomo, il click esegue fuoco/movimento.
	if acting != null:
		_handle_action_click(hex)
		return
	# Selezione: con piu' pedine vive nell'hex (stacking, Rule 8) ogni clic
	# successivo sullo stesso hex passa all'uomo seguente nella pila.
	var here: Array = []
	for cc in state.characters:
		if not cc.is_dead() and cc.position == hex:
			here.append(cc)
	var c: Character = null
	if not here.is_empty():
		if hex == _stack_cycle_hex:
			_stack_cycle_i = (_stack_cycle_i + 1) % here.size()
		else:
			_stack_cycle_hex = hex
			_stack_cycle_i = 0
		c = here[_stack_cycle_i]
	else:
		_stack_cycle_hex = Vector2i(-99, -99)
		_stack_cycle_i = 0
	map_view.selected = c
	map_view.highlight_hex = hex
	map_view.queue_redraw()
	_show_info(hex, c)
	_refresh_roster()
	_refresh_enemy_roster()
	if here.size() > 1:
		hint_label.text = "Pila di %d uomini: riclicca l'hex per il prossimo (%s)" % [
			here.size(), c.display_name]
	# Carta Initiative (DISCARD): click su un friendly per cambiarne l'ordine.
	if _initiative_card_pending:
		_initiative_card_pending = false
		order_panel.hide()
		vehicle_popup.hide()
		if c != null and c.side == Domain.Side.FRIENDLY and not c.is_dead():
			_open_order_panel(c)
		else:
			hint_label.text = "Initiative annullata (nessun uomo selezionato)"
		return
	# Clic su un veicolo: apre il Vehicle Display con l'equipaggio.
	if c != null and c.is_vehicle:
		_show_vehicle_display(c)
	else:
		vehicle_popup.hide()
	# Deselezione o selezione di altro: il pannello ordini si chiude.
	order_panel.hide()
	if phase == Phase.ORDERS and c != null \
			and c.side == Domain.Side.FRIENDLY and not c.is_dead():
		_open_order_panel(c)


# Selettore ordini: bottoni a sinistra (solo quelli legali), descrizione
# con track degli impulsi a destra quando passi sopra un ordine.
func _open_order_panel(c: Character) -> void:
	# Veicoli: apre la scheda equipaggio (ogni membro ha il suo pannello ordini).
	if c.is_vehicle:
		_show_vehicle_display(c)
		return
	order_target = c
	for child in order_list.get_children():
		child.queue_free()
	order_title_label.text = "⠿  Ordine: %s" % c.display_name
	for o in TurnSequence.legal_orders(state, c):
		var b := Button.new()
		b.text = Domain.ORDER_NAMES[o]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(190, 0)
		b.pressed.connect(_on_order_selected.bind(o))
		b.mouse_entered.connect(_describe_order.bind(o))
		order_list.add_child(b)
	# Lasciare un uomo SENZA ordine e' lecito (le tabelle hanno la colonna
	# 'No Order'): non agira' negli impulsi, ma allo scoperto e' piu'
	# facile da colpire.
	var none := Button.new()
	none.text = "Senza ordine"
	none.alignment = HORIZONTAL_ALIGNMENT_LEFT
	none.modulate = Color(0.8, 0.8, 0.65)
	none.mouse_entered.connect(func():
		order_desc.text = "[b][color=#f3e88a]Senza ordine[/color][/b]\n\nNon agisce negli impulsi (puo' comunque avvistare). Attenzione: un uomo senza ordine allo scoperto e' PIU' facile da colpire.")
	none.pressed.connect(func():
		order_panel.hide()
		if order_target != null:
			order_target.clear_order()
			state.log_event("%s resta senza ordine" % order_target.display_name)
			_update_orders_button()
			_refresh())
	order_list.add_child(none)
	# Mount Up: se c'e' un veicolo amico in questo hex o adiacente, offri
	# l'opzione di salire a bordo come passeggero.
	var nearby_vehicle := _find_nearby_friendly_vehicle(c)
	if nearby_vehicle != null:
		var mount_sep := HSeparator.new()
		order_list.add_child(mount_sep)
		var mount_btn := Button.new()
		mount_btn.text = "Sali sul mezzo"
		mount_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		mount_btn.custom_minimum_size = Vector2(190, 0)
		mount_btn.modulate = Color(0.75, 0.92, 1.0)
		var vname := nearby_vehicle.display_name
		mount_btn.mouse_entered.connect(func():
			order_desc.text = "[b][color=#aadfff]Sali sul mezzo[/color][/b]\n\n%s sale sul [b]%s[/b]. Non agira' piu' sul campo finche' rimane a bordo. Scende automaticamente con Bail Out o alla distruzione del mezzo." % [c.display_name, vname])
		var cv := c
		var veh := nearby_vehicle
		mount_btn.pressed.connect(func():
			order_panel.hide()
			VehicleCombat.mount_up(state, cv, veh)
			_update_orders_button()
			_refresh())
		order_list.add_child(mount_btn)
	var cancel := Button.new()
	cancel.text = "Annulla"
	cancel.modulate = Color(0.85, 0.7, 0.7)
	cancel.pressed.connect(func(): order_panel.hide())
	order_list.add_child(cancel)
	order_desc.text = "[i]Passa il mouse su un ordine per la spiegazione.[/i]"
	order_panel.show()


# Cerca un veicolo amico in questo hex o adiacente (per il Mount Up).
func _find_nearby_friendly_vehicle(c: Character) -> Character:
	for other in state.characters:
		if not other.is_vehicle or other.side != Domain.Side.FRIENDLY or other.is_dead():
			continue
		var d := Spotting.hex_distance(c.position, other.position)
		if d <= 1:
			return other
	return null


func _describe_order(o: int) -> void:
	var ws_mod: int = Orders.FIRE_WS_MOD.get(o, 0)
	var lines: Array[String] = []
	lines.append("[b][color=#f3e88a]%s[/color][/b]" % Domain.ORDER_NAMES[o])
	# Il segnalino dell'ordine sotto il nome (se disponibile).
	var marker := "res://assets/counters/ord-US-%s.png" % Domain.Order.keys()[o]
	if ResourceLoader.exists(marker):
		lines.append("[img=72]%s[/img]" % marker)
	lines.append("")
	lines.append(Orders.DESC.get(o, ""))
	lines.append("")
	lines.append("[b]Impulsi:[/b]")
	for row in Orders.track_lines(o):
		# evidenzia il numero d'impulso; il resto in chiaro
		lines.append("  [b][color=#f3e88a]%s[/color][/b] - %s" % [
			row.substr(0, 1), row.substr(4)])
	if ws_mod != 0:
		lines.append("")
		lines.append("[b]Mod. al fuoco:[/b] %+d WS" % ws_mod)
	order_desc.text = "\n".join(lines)


func _handle_action_click(hex: Vector2i) -> void:
	if action_kind == TurnSequence.Act.FIRE:
		# Cerca il primo bersaglio valido nella hex cliccata.
		var valid_targets := TurnSequence.valid_fire_targets(state, acting)
		var target: Character = null
		for t in valid_targets:
			if t.position == hex:
				target = t
				break
		if target == null:
			return  # click non valido: si ignora
		if acting.is_vehicle:
			# Veicolo: Gunner spara sul bersaglio scelto, poi bow MG auto.
			TurnSequence.fire_vehicle_gunner_at(state, acting, target)
			TurnSequence.resolve_vehicle_bow_mg(state, acting)
		else:
			# Fanteria: usa il primo weapon disponibile (con preferenza fire_mode).
			Fire.fire_action(state, acting, target, acting.weapon_skills.keys()[0])
		_consume_audio_events()
		_finish_friendly_action()
	elif action_kind == TurnSequence.Act.THROW:
		if not hex in TurnSequence.valid_throw_hexes(state, acting):
			return  # click non valido: si ignora
		TurnSequence.throw_grenade(state, acting, hex)
		_consume_audio_events()
		_finish_friendly_action()
	else:  # MOVE
		var from := acting.position
		if not Move.step_to(state, acting, hex):
			return
		if acting.is_vehicle:
			_play_sfx("vehicle")
		moves_left -= 1
		# Scavalcare un BOCAGE esaurisce il movimento dell'impulse.
		if state.hexside_between(from, hex) == Domain.Terrain.BOCAGE:
			moves_left = 0
			state.log_event("%s scavalca il bocage e si ferma" % acting.display_name)
		if moves_left <= 0:
			# Move-and-shoot: dopo il movimento del veicolo, il Gunner spara
			# interattivamente se ha un ordine di fuoco attivo questo impulse.
			if acting.is_vehicle and TurnSequence.vehicle_gunner_fires_impulse(acting, state.impulse):
				var targets := TurnSequence.valid_fire_targets(state, acting)
				if not targets.is_empty():
					action_kind = TurnSequence.Act.FIRE
					map_view.cue_hexes = _hexes_of(targets)
					map_view.cue_color = Color(0.95, 0.55, 0.05, 0.95)
					map_view.fire_lines_source = acting.position
					hint_label.text = "%s Gunner: clicca un bersaglio (arancio) o premi Passa" % \
						acting.display_name
					next_button.text = "Passa"
					_refresh()
					return
				# Nessun bersaglio: risolvi bow MG e concludi.
				TurnSequence.resolve_vehicle_bow_mg(state, acting)
			_finish_friendly_action()
		else:
			# aggiorna evidenziazione e prompt per il passo successivo
			map_view.cue_hexes = _passable_neighbors(acting)
			hint_label.text = "%s: muovi ancora (%d) o premi Fine" % [
				acting.display_name, moves_left]
			_refresh()


func _on_order_selected(id: int) -> void:
	if order_target == null:
		return
	order_panel.hide()
	order_target.set_order(id)
	# I veicoli usano la terminologia di marcia (Crawl/Ahead Slow/...).
	var order_name: String = DRIVER_ORDER_NAMES.get(id, Domain.ORDER_NAMES[id]) \
		if order_target.is_vehicle else Domain.ORDER_NAMES[id]
	state.log_event("%s riceve l'ordine %s" % [
		order_target.display_name, order_name])
	_update_orders_button()
	_refresh()
	_refresh_vehicle_display()


# Conferma sempre possibile: il pulsante segnala quanti sono senza ordine.
func _update_orders_button() -> void:
	if phase != Phase.ORDERS:
		return
	next_button.disabled = false
	var missing := 0
	for c in state.characters:
		if c.side == Domain.Side.FRIENDLY and not c.is_dead() and not c.has_order:
			missing += 1
	next_button.text = "Conferma ordini" if missing == 0 \
		else "Conferma (%d senza ordine)" % missing


# ---------------------------------------------------------------- HUD

# Tema "militare": pannelli verde oliva scuro semi-trasparenti, bordi
# morbidi, pulsanti coerenti. Tutto in codice, niente risorse esterne.
func _make_theme() -> Theme:
	var theme := Theme.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.09, 0.11, 0.07, 0.93)
	panel.border_color = Color(0.35, 0.40, 0.25)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(10)
	theme.set_stylebox("panel", "PanelContainer", panel)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.18, 0.22, 0.13)
	btn.border_color = Color(0.45, 0.52, 0.30)
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(4)
	btn.set_content_margin_all(6)
	theme.set_stylebox("normal", "Button", btn)
	var btn_h := btn.duplicate()
	btn_h.bg_color = Color(0.28, 0.34, 0.18)
	theme.set_stylebox("hover", "Button", btn_h)
	var btn_p := btn.duplicate()
	btn_p.bg_color = Color(0.40, 0.46, 0.24)
	theme.set_stylebox("pressed", "Button", btn_p)
	var btn_d := btn.duplicate()
	btn_d.bg_color = Color(0.12, 0.13, 0.10)
	theme.set_stylebox("disabled", "Button", btn_d)
	theme.set_color("font_color", "Label", Color(0.92, 0.92, 0.85))
	theme.set_color("default_color", "RichTextLabel", Color(0.92, 0.92, 0.85))
	return theme


# --------------------------------------------------------- editor mappa

func _editor_act(local_pos: Vector2) -> void:
	if editor_is_hexside:
		var hs := _pick_hexside(local_pos)
		if hs.is_empty():
			return
		if editor_hexside_brush < 0:
			state.hexsides.erase(hs)
		else:
			state.hexsides[hs] = editor_hexside_brush
		map_view.queue_redraw()
	elif editor_brush >= 0:
		var hex := map_view.pick_hex(local_pos)
		if hex.x <= -99:
			return
		var key := GameState.hex_key(hex.x, hex.y)
		if not state.map.has(key):
			return
		state.map[key].terrain = editor_brush
		map_view.queue_redraw()
	else:
		hint_label.text = "Editor: scegli un terreno o un lato dal pannello a sinistra"


func _pick_hexside(local_pos: Vector2) -> String:
	var h1 := map_view.pick_hex(local_pos)
	if h1.x <= -99:
		return ""
	var best_n := Vector2i(-99, -99)
	var best_d := INF
	for n in Move.neighbors(state, h1):
		var d := map_view.hex_center(n.x, n.y).distance_to(local_pos)
		if d < best_d:
			best_d = d
			best_n = n
	if best_n.x <= -99:
		return ""
	return GameState.hexside_key(h1, best_n)


func _export_map_data() -> void:
	var map_name: String = Scenario.SCENARIOS[state.scenario_id]["map"]
	# Raggruppa hex per terreno.
	var by_terrain: Dictionary = {}
	for key in state.map:
		var hex: GameState.MapHex = state.map[key]
		if hex.terrain == Domain.Terrain.OPEN_LEVEL_0:
			continue  # non serve esportare il terreno di default
		if not by_terrain.has(hex.terrain):
			by_terrain[hex.terrain] = []
		by_terrain[hex.terrain].append(key)
	# Genera codice GDScript compatibile con Boards.gd.
	var lines: Array[String] = []
	lines.append("# Dati esportati dall'editor — incolla in Boards.gd sotto \"%s\":" % map_name)
	lines.append('"%s": {' % map_name)
	for t in by_terrain:
		var tname: String = Domain.Terrain.keys()[t]
		var entries: Array = by_terrain[t]
		entries.sort()
		var quoted: Array[String] = []
		for e in entries:
			quoted.append('"%s"' % e)
		lines.append('\tD.Terrain.%s: [%s],' % [tname, ", ".join(quoted)])
	lines.append("},")
	# Hexside (siepi/bocage/muri).
	var hs_abbrev := {
		Domain.Terrain.HEDGEROW: "H",
		Domain.Terrain.BOCAGE: "B",
		Domain.Terrain.WALL: "W",
	}
	if not state.hexsides.is_empty():
		lines.append("")
		lines.append("# Hexside per \"%s\" — incolla in HEXSIDES[\"%s\"]:" % [map_name, map_name])
		lines.append('"%s": [' % map_name)
		var hs_entries: Array[String] = []
		for key in state.hexsides:
			var t_hs: int = state.hexsides[key]
			var ab: String = hs_abbrev.get(t_hs, "?")
			hs_entries.append('\t"%s|%s"' % [key, ab])
		hs_entries.sort()
		for e in hs_entries:
			lines.append(e + ",")
		lines.append("],")
	var text := "\n".join(lines)
	var fname := "map_export_%s.txt" % map_name
	var n_hex := by_terrain.size()
	var n_hs := state.hexsides.size()
	if OS.get_name() == "Web":
		# Su web non si puo' scrivere su path arbitrari: scarica il file tramite
		# il browser (Blob API), che apre la finestra "Salva come..." del sistema.
		var js_content: String = JSON.stringify(text)
		JavaScriptBridge.eval("""
(function() {
	var blob = new Blob([%s], {type: 'text/plain'});
	var url = URL.createObjectURL(blob);
	var a = document.createElement('a');
	a.href = url; a.download = '%s';
	document.body.appendChild(a); a.click(); document.body.removeChild(a);
	setTimeout(function(){ URL.revokeObjectURL(url); }, 2000);
})();
""" % [js_content, fname])
		hint_label.text = "Download: %s (%d terreni, %d hexside)" % [fname, n_hex, n_hs]
	else:
		var path := "/tmp/%s" % fname
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
			hint_label.text = "Esportato in %s (%d terreni, %d hexside)" % [path, n_hex, n_hs]
		else:
			hint_label.text = "Errore scrittura %s" % path


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	# Radice Control a tutto schermo: i figli ereditano il tema.
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = _make_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)

	# Barra superiore: turno/fase + pulsante Avanti
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	root.add_child(top)
	var top_box := HBoxContainer.new()
	top.add_child(top_box)
	turn_label = Label.new()
	turn_label.add_theme_font_size_override("font_size", 18)
	top_box.add_child(turn_label)
	hint_label = Label.new()
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 17)
	hint_label.add_theme_color_override("font_color", Color(0.98, 0.92, 0.55))
	top_box.add_child(hint_label)
	los_button = Button.new()
	los_button.text = "LOS"
	los_button.toggle_mode = true
	los_button.tooltip_text = "Strumento linea di vista: congela il gioco,\nclicca due hex per verificare se si vedono."
	los_button.custom_minimum_size = Vector2(70, 40)
	los_button.toggled.connect(_on_los_toggled)
	top_box.add_child(los_button)
	editor_button = Button.new()
	editor_button.text = "Mappa"
	editor_button.toggle_mode = true
	editor_button.tooltip_text = "Editor mappa (E): clicca e trascina per dipingere terreno."
	editor_button.custom_minimum_size = Vector2(80, 40)
	editor_button.toggled.connect(func(on: bool) -> void:
		if map_view == null:
			return
		map_view.editor_mode = on
		editor_panel.visible = on
		map_view.debug_terrain = on
		overlay_legend.visible = false
		map_view.queue_redraw()
		hint_label.text = "Editor mappa: %s (E per uscire)" % \
			("ON — clicca hex + trascina per dipingere terreno" if on else "off")
	)
	top_box.add_child(editor_button)
	replay_button = Button.new()
	replay_button.text = "Replay turno"
	replay_button.tooltip_text = "Rivedi il turno appena giocato: percorsi e\ncombattimenti in flusso cinematografico continuo."
	replay_button.custom_minimum_size = Vector2(120, 40)
	replay_button.disabled = true
	replay_button.pressed.connect(_on_replay_turn)
	top_box.add_child(replay_button)
	next_button = Button.new()
	next_button.text = "Avanti"
	next_button.custom_minimum_size = Vector2(180, 40)
	next_button.pressed.connect(_on_next_pressed)
	top_box.add_child(next_button)

	# SIDEBAR destra unificata: INFO sopra, LOG sotto, legenda morale.
	var side := PanelContainer.new()
	side.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	side.offset_left = -330
	side.offset_top = 46
	side.offset_bottom = -8
	side.offset_right = -8
	root.add_child(side)
	var side_box := VBoxContainer.new()
	side_box.add_theme_constant_override("separation", 6)
	side.add_child(side_box)
	side_box.add_child(_section_label("UNITA' / HEX"))
	info_text = RichTextLabel.new()
	info_text.bbcode_enabled = true
	info_text.fit_content = false
	info_text.custom_minimum_size = Vector2(0, 200)
	info_text.add_theme_font_size_override("normal_font_size", 15)
	side_box.add_child(info_text)
	side_box.add_child(HSeparator.new())
	# Diario di battaglia (il roster nemici e' nel pannello squadra a sinistra)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 13)
	side_box.add_child(tabs)
	var log_tab := VBoxContainer.new()
	log_tab.name = "Diario"
	log_tab.add_theme_constant_override("separation", 2)
	tabs.add_child(log_tab)
	var log_head := HBoxContainer.new()
	var log_title := _section_label("DIARIO DI BATTAGLIA")
	log_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_head.add_child(log_title)
	var detail_toggle := CheckButton.new()
	detail_toggle.text = "Formule"
	detail_toggle.tooltip_text = "Mostra il calcolo del fuoco: WS, modificatori e tiro di dado"
	detail_toggle.add_theme_font_size_override("font_size", 12)
	detail_toggle.toggled.connect(func(on: bool):
		log_show_detail = on
		_rebuild_log())
	log_head.add_child(detail_toggle)
	log_tab.add_child(log_head)
	log_text = RichTextLabel.new()
	log_text.bbcode_enabled = true
	log_text.scroll_following = true
	log_text.fit_content = false
	log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_text.add_theme_font_size_override("normal_font_size", 13)
	log_tab.add_child(log_text)
	side_box.add_child(HSeparator.new())
	# Legenda dei pallini di morale.
	var legend := RichTextLabel.new()
	legend.bbcode_enabled = true
	legend.fit_content = true
	legend.add_theme_font_size_override("normal_font_size", 12)
	var parts: Array[String] = []
	for m in Domain.MORALE_NAMES:
		parts.append("[bgcolor=#%s]  [/bgcolor] %s" % [
			MapView.MORALE_COLORS[m].to_html(false), Domain.MORALE_NAMES[m]])
	legend.text = "Morale:  " + "  ".join(parts)
	side_box.add_child(legend)

	# Roster della squadra: pannello sinistro alto tutta la finestra, collassabile.
	var roster_panel := PanelContainer.new()
	roster_panel.anchor_left = 0.0
	roster_panel.anchor_right = 0.0
	roster_panel.anchor_top = 0.0
	roster_panel.anchor_bottom = 1.0
	roster_panel.offset_left = 8
	roster_panel.offset_top = 46
	roster_panel.offset_bottom = -8
	roster_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(roster_panel)
	var roster_outer := VBoxContainer.new()
	roster_outer.custom_minimum_size = Vector2(230, 0)
	roster_outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_outer.add_theme_constant_override("separation", 0)
	roster_panel.add_child(roster_outer)
	# Header con pulsante collassa ◄
	var roster_hdr_row := HBoxContainer.new()
	roster_hdr_row.add_theme_constant_override("separation", 0)
	roster_outer.add_child(roster_hdr_row)
	var roster_title := Label.new()
	roster_title.text = "SQUADRA"
	roster_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_title.add_theme_font_size_override("font_size", 13)
	roster_title.add_theme_color_override("font_color", Color(0.98, 0.92, 0.55))
	roster_title.add_theme_constant_override("margin_left", 6)
	roster_hdr_row.add_child(roster_title)
	var roster_collapse_btn := Button.new()
	roster_collapse_btn.text = "▼"
	roster_collapse_btn.flat = true
	roster_collapse_btn.add_theme_font_size_override("font_size", 14)
	roster_hdr_row.add_child(roster_collapse_btn)
	var roster_tabs := TabContainer.new()
	roster_tabs.add_theme_font_size_override("font_size", 13)
	roster_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_outer.add_child(roster_tabs)
	# Tab Squadra
	var squad_scroll := ScrollContainer.new()
	squad_scroll.name = "Squadra"
	squad_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	squad_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	squad_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_tabs.add_child(squad_scroll)
	roster_body = VBoxContainer.new()
	roster_body.add_theme_constant_override("separation", 2)
	roster_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	squad_scroll.add_child(roster_body)
	roster_box = roster_body
	# Tab Nemici
	var enemy_scroll := ScrollContainer.new()
	enemy_scroll.name = "Nemici"
	enemy_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	enemy_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	enemy_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_tabs.add_child(enemy_scroll)
	enemy_roster_body = VBoxContainer.new()
	enemy_roster_body.add_theme_constant_override("separation", 2)
	enemy_roster_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_scroll.add_child(enemy_roster_body)
	enemy_roster_box = enemy_roster_body
	roster_collapse_btn.pressed.connect(func():
		roster_collapsed = not roster_collapsed
		roster_tabs.visible = not roster_collapsed
		roster_title.visible = not roster_collapsed
		roster_collapse_btn.text = "▲" if roster_collapsed else "▼"
		if roster_collapsed:
			roster_panel.anchor_bottom = 0.0
			roster_panel.offset_bottom = 80
		else:
			roster_panel.anchor_bottom = 1.0
			roster_panel.offset_bottom = -8)

	# La mano di carte, in basso al centro
	hand_panel = PanelContainer.new()
	hand_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hand_panel.offset_top = -224
	hand_panel.offset_bottom = -12
	hand_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(hand_panel)
	var hand_vbox := VBoxContainer.new()
	hand_vbox.add_theme_constant_override("separation", 4)
	hand_panel.add_child(hand_vbox)
	var hand_header := Label.new()
	hand_header.text = "— Scegli la carta da giocare sull'Initiative Track —"
	hand_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hand_header.add_theme_font_size_override("font_size", 13)
	hand_header.add_theme_color_override("font_color", Color(0.98, 0.92, 0.55))
	hand_vbox.add_child(hand_header)
	hand_box = HBoxContainer.new()
	hand_box.add_theme_constant_override("separation", 6)
	hand_vbox.add_child(hand_box)

	# Banner carta giocata: visibile da ORDER phase in poi, in basso al centro.
	played_card_bar = PanelContainer.new()
	played_card_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	played_card_bar.offset_top = -68
	played_card_bar.offset_bottom = -12
	played_card_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(played_card_bar)
	played_card_text = RichTextLabel.new()
	played_card_text.bbcode_enabled = true
	played_card_text.fit_content = true
	played_card_text.custom_minimum_size = Vector2(400, 0)
	played_card_text.add_theme_font_size_override("normal_font_size", 13)
	played_card_bar.add_child(played_card_text)
	played_card_bar.hide()

	# Pulsante "Carte (%d)" per vedere le DISCARD cards in mano.
	hand_discard_button = Button.new()
	hand_discard_button.text = "Carte in mano"
	hand_discard_button.custom_minimum_size = Vector2(120, 36)
	hand_discard_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hand_discard_button.offset_left = 8
	hand_discard_button.offset_bottom = -12
	hand_discard_button.offset_top = -56
	hand_discard_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hand_discard_button.pressed.connect(_toggle_discard_popup)
	hand_discard_button.hide()
	root.add_child(hand_discard_button)

	# Popup carte DISCARD in mano (nascosto di default).
	discard_popup = PanelContainer.new()
	discard_popup.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	discard_popup.offset_left = 8
	discard_popup.offset_bottom = -52
	discard_popup.grow_vertical = Control.GROW_DIRECTION_BEGIN
	discard_popup.grow_horizontal = Control.GROW_DIRECTION_END
	discard_popup.hide()
	root.add_child(discard_popup)

	# Vehicle Display: pannello equipaggio del mezzo (clic su un veicolo).
	vehicle_popup = PanelContainer.new()
	vehicle_popup.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	vehicle_popup.offset_right = -340
	vehicle_popup.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	vehicle_popup.grow_vertical = Control.GROW_DIRECTION_BOTH
	vehicle_popup.hide()
	root.add_child(vehicle_popup)

	# Carta nemica pescata (grafica originale), in alto a sinistra.
	enemy_card_rect = TextureRect.new()
	enemy_card_rect.set_anchors_preset(Control.PRESET_TOP_LEFT)
	enemy_card_rect.offset_left = 8
	enemy_card_rect.offset_top = 48
	enemy_card_rect.custom_minimum_size = Vector2(120, 167)
	enemy_card_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	enemy_card_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	enemy_card_rect.hide()
	root.add_child(enemy_card_rect)

	# Anteprima ingrandita della carta (al passaggio del mouse sulla mano).
	card_preview = TextureRect.new()
	card_preview.set_anchors_preset(Control.PRESET_CENTER)
	card_preview.offset_left = -185
	card_preview.offset_right = 185
	card_preview.offset_top = -390
	card_preview.offset_bottom = 130
	card_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	card_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_preview.hide()
	root.add_child(card_preview)

	# Legenda dell'overlay terreno (compare col tasto T), in basso a sinistra.
	overlay_legend = PanelContainer.new()
	overlay_legend.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	overlay_legend.offset_left = 8
	overlay_legend.offset_bottom = -8
	overlay_legend.grow_vertical = Control.GROW_DIRECTION_BEGIN
	overlay_legend.hide()
	root.add_child(overlay_legend)
	var leg := RichTextLabel.new()
	leg.bbcode_enabled = true
	leg.fit_content = true
	leg.custom_minimum_size = Vector2(240, 0)
	leg.add_theme_font_size_override("normal_font_size", 13)
	var rows: Array[String] = []
	rows.append("[b]OVERLAY TERRENO[/b] (T per chiudere)")
	rows.append("[i]Riempimenti (hex):[/i]")
	for t in MapView.OVERLAY_TINTS:
		var c: Color = MapView.OVERLAY_TINTS[t]
		rows.append("[bgcolor=#%s]  [/bgcolor] %s" % [
			Color(c.r, c.g, c.b).to_html(false), Domain.TERRAIN_NAMES[t]])
	rows.append("[i]Hexside (bordi):[/i]")
	for t in MapView.HEXSIDE_COLORS:
		rows.append("[bgcolor=#%s]  [/bgcolor] %s (bordo)" % [
			MapView.HEXSIDE_COLORS[t].to_html(false), Domain.TERRAIN_NAMES[t]])
	rows.append("[i]Hex senza tinta = Open L0[/i]")
	leg.text = "\n".join(rows)
	overlay_legend.add_child(leg)

	# Pannello ordini con spiegazioni (al posto del vecchio PopupMenu):
	# bottoni a sinistra, descrizione al passaggio del mouse a destra.
	order_panel = PanelContainer.new()
	order_panel.set_anchors_preset(Control.PRESET_CENTER)
	order_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	order_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	order_panel.hide()
	root.add_child(order_panel)
	var order_outer := VBoxContainer.new()
	order_outer.add_theme_constant_override("separation", 4)
	order_panel.add_child(order_outer)
	# Barra-titolo trascinabile.
	var order_titlebar := _title_bar("Ordini")
	order_title_label = order_titlebar.get_child(0) as Label
	order_outer.add_child(order_titlebar)
	_make_draggable(order_panel, order_titlebar)
	var order_h := HBoxContainer.new()
	order_h.add_theme_constant_override("separation", 10)
	order_outer.add_child(order_h)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(210, 430)
	order_h.add_child(scroll)
	order_list = VBoxContainer.new()
	order_list.add_theme_constant_override("separation", 2)
	scroll.add_child(order_list)
	order_desc = RichTextLabel.new()
	order_desc.bbcode_enabled = true
	order_desc.fit_content = false
	order_desc.custom_minimum_size = Vector2(300, 430)
	order_desc.add_theme_font_size_override("normal_font_size", 15)
	order_h.add_child(order_desc)

	# Pannello editor mappa (tasto E): opacita' + palette terreni + export.
	editor_panel = PanelContainer.new()
	editor_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	editor_panel.offset_right = 220
	editor_panel.offset_top = 46
	editor_panel.offset_bottom = -8
	editor_panel.hide()
	root.add_child(editor_panel)
	var ep_box := VBoxContainer.new()
	ep_box.add_theme_constant_override("separation", 4)
	editor_panel.add_child(ep_box)
	ep_box.add_child(_section_label("EDITOR MAPPA (E per uscire)"))
	var op_label := Label.new()
	op_label.text = "Opacita' mappa:"
	op_label.add_theme_font_size_override("font_size", 12)
	ep_box.add_child(op_label)
	var op_slider := HSlider.new()
	op_slider.min_value = 0.0
	op_slider.max_value = 1.0
	op_slider.step = 0.05
	op_slider.value = 1.0
	op_slider.custom_minimum_size = Vector2(200, 24)
	op_slider.value_changed.connect(func(v: float):
		map_view.map_opacity = v
		map_view.queue_redraw())
	ep_box.add_child(op_slider)
	# Opacita' dell'overlay di terreno rigenerato (i poligoni colorati sopra la board).
	var ov_label := Label.new()
	ov_label.text = "Opacita' mappa rigenerata:"
	ov_label.add_theme_font_size_override("font_size", 12)
	ep_box.add_child(ov_label)
	var ov_slider := HSlider.new()
	ov_slider.min_value = 0.0
	ov_slider.max_value = 1.0
	ov_slider.step = 0.05
	ov_slider.value = 1.0
	ov_slider.custom_minimum_size = Vector2(200, 24)
	ov_slider.value_changed.connect(func(v: float):
		map_view.overlay_opacity = v
		map_view.queue_redraw())
	ep_box.add_child(ov_slider)
	ep_box.add_child(HSeparator.new())
	ep_box.add_child(_section_label("Terreno da dipingere:"))
	var ep_scroll := ScrollContainer.new()
	ep_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ep_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ep_box.add_child(ep_scroll)
	var ep_list := VBoxContainer.new()
	ep_list.add_theme_constant_override("separation", 2)
	ep_scroll.add_child(ep_list)
	# Lista unificata di tutti i pulsanti (hex + hexside) per la deselezione.
	var all_brush_buttons: Array = []
	# -- sezione HEX --
	ep_list.add_child(_section_label("HEX (terreno interno)"))
	var none_btn := Button.new()
	none_btn.text = "— Nessuno —"
	none_btn.toggle_mode = true
	none_btn.custom_minimum_size = Vector2(200, 26)
	none_btn.pressed.connect(func():
		editor_brush = -1
		editor_is_hexside = false)
	ep_list.add_child(none_btn)
	all_brush_buttons.append(none_btn)
	for t in Domain.TERRAIN_NAMES:
		var tname: String = Domain.TERRAIN_NAMES[t]
		var tb := Button.new()
		tb.text = tname
		tb.toggle_mode = true
		tb.custom_minimum_size = Vector2(200, 26)
		var tint: Color = MapView.OVERLAY_TINTS.get(t,
			Color(MapView.BASE_COLORS.get(t, Color.MAGENTA)))
		tb.add_theme_color_override("font_color",
			Color.WHITE if tint.get_luminance() < 0.5 else Color.BLACK)
		tb.add_theme_stylebox_override("normal",
			_colored_stylebox(Color(tint.r, tint.g, tint.b, 0.7)))
		tb.add_theme_stylebox_override("pressed",
			_colored_stylebox(Color(tint.r, tint.g, tint.b, 1.0)))
		var t_val: int = t
		tb.pressed.connect(func():
			editor_brush = t_val
			editor_is_hexside = false
			for b in all_brush_buttons:
				if b != tb:
					b.button_pressed = false)
		all_brush_buttons.append(tb)
		ep_list.add_child(tb)
	# -- sezione HEXSIDE --
	ep_list.add_child(HSeparator.new())
	ep_list.add_child(_section_label("LATO (hexside)"))
	var hexside_entries: Array = [
		[Domain.Terrain.HEDGEROW, "Hedgerow",  MapView.HEXSIDE_COLORS[Domain.Terrain.HEDGEROW]],
		[Domain.Terrain.BOCAGE,   "Bocage",    MapView.HEXSIDE_COLORS[Domain.Terrain.BOCAGE]],
		[Domain.Terrain.WALL,     "Wall",      MapView.HEXSIDE_COLORS[Domain.Terrain.WALL]],
	]
	for entry in hexside_entries:
		var ht: int = entry[0]
		var hn: String = entry[1]
		var hc: Color = entry[2]
		var hb := Button.new()
		hb.text = hn
		hb.toggle_mode = true
		hb.custom_minimum_size = Vector2(200, 26)
		hb.add_theme_color_override("font_color", Color.WHITE)
		hb.add_theme_stylebox_override("normal",  _colored_stylebox(Color(hc.r, hc.g, hc.b, 0.8)))
		hb.add_theme_stylebox_override("pressed", _colored_stylebox(Color(hc.r, hc.g, hc.b, 1.0)))
		var ht_val: int = ht
		hb.pressed.connect(func():
			editor_is_hexside = true
			editor_hexside_brush = ht_val
			editor_brush = -1
			for b in all_brush_buttons:
				if b != hb:
					b.button_pressed = false)
		all_brush_buttons.append(hb)
		ep_list.add_child(hb)
	var rem_btn := Button.new()
	rem_btn.text = "Rimuovi lato"
	rem_btn.toggle_mode = true
	rem_btn.custom_minimum_size = Vector2(200, 26)
	rem_btn.modulate = Color(1.0, 0.7, 0.7)
	rem_btn.pressed.connect(func():
		editor_is_hexside = true
		editor_hexside_brush = -1
		editor_brush = -1
		for b in all_brush_buttons:
			if b != rem_btn:
				b.button_pressed = false)
	all_brush_buttons.append(rem_btn)
	ep_list.add_child(rem_btn)
	ep_box.add_child(HSeparator.new())
	var export_btn := Button.new()
	export_btn.text = "Esporta dati mappa"
	export_btn.custom_minimum_size = Vector2(200, 36)
	export_btn.pressed.connect(_export_map_data)
	ep_box.add_child(export_btn)


func _colored_stylebox(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	return sb


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.65, 0.72, 0.50))
	return l


const WOUND_SYMBOLS := {
	FriendlyCards.WoundDraw.CLOSE_CALL: "MC",
	FriendlyCards.WoundDraw.LIGHT_WOUND: "LW",
	FriendlyCards.WoundDraw.BAD_WOUND: "BW",
	FriendlyCards.WoundDraw.KIA: "KIA",
}
const WOUND_COLORS := {
	FriendlyCards.WoundDraw.CLOSE_CALL: Color(0.7, 0.85, 0.7),
	FriendlyCards.WoundDraw.LIGHT_WOUND: Color(0.95, 0.85, 0.35),
	FriendlyCards.WoundDraw.BAD_WOUND: Color(0.95, 0.50, 0.20),
	FriendlyCards.WoundDraw.KIA: Color(0.95, 0.25, 0.20),
}
# Segnalini morale nel roster (int key = Domain.Morale enum value, 0..6).
const MORALE_MARKERS: Dictionary = {
	0: "res://assets/counters/Morale_Fanatic-f.png",        # BERSERK
	1: "res://assets/counters/Morale_High--f.png",           # AGGRESSIVE
	2: "res://assets/counters/GEN-Bold-Marker-12-f.png",     # BOLD
	3: "res://assets/counters/GEN-Normal-Marker-10-f.png",   # NORMAL
	4: "res://assets/counters/GEN-Cautious-Marker-10-f.png", # CAUTIOUS
	5: "res://assets/counters/Morale_Low-f.png",             # SHAKEN
	6: "res://assets/counters/GEN-Rout-Marker-10-f.png",     # ROUT
}
# Segnalini arma speciali nel roster (solo le armi con counter dedicato).
const WEAPON_COUNTER_ID: Dictionary = {
	"M1919":        "US-M1919-Marker-1",
	"M2 .50cal":    "US-M2-Marker-1",
	"Panzerfaust 60":  "GEN-Panzerfaust-60-Marker",
	"Panzerfaust 100": "GEN-Panzerfaust-100-Marker",
}
const KIND_LABELS := {
	FriendlyCards.Kind.ORDER: "ORDER",
	FriendlyCards.Kind.DISCARD: "DISCARD",
	FriendlyCards.Kind.EVENT: "EVENT",
}


func _show_hand() -> void:
	for child in hand_box.get_children():
		child.queue_free()
	for i in range(state.friendly_hand.size()):
		var serial: int = state.friendly_hand[i]
		var kind: int = FriendlyCards.kind_of(serial)
		var wound: int = FriendlyCards.wound_of(serial)
		var tip := "Carta %d - %s [%s]\nAble %d  Baker %d  Charlie %d\nFerita: %s\n%s" % [
			serial, FriendlyCards.title_of(serial), KIND_LABELS.get(kind, ""),
			FriendlyCards.initiative_for(serial, "Able"),
			FriendlyCards.initiative_for(serial, "Baker"),
			FriendlyCards.initiative_for(serial, "Charlie"),
			WOUND_SYMBOLS.get(wound, "?"),
			FriendlyCards.text_of(serial),
		]
		# Wrapper verticale: immagine + riga info + pulsante Gioca
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 2)
		hand_box.add_child(cv)
		var img := FriendlyCards.image(serial)
		var tex_to_preview: Texture2D = null
		if not img.is_empty():
			var tb := TextureButton.new()
			tb.texture_normal = load(img)
			tb.ignore_texture_size = true
			tb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			tb.custom_minimum_size = Vector2(150, 188)
			tb.tooltip_text = tip
			tb.pressed.connect(_on_card_chosen.bind(i))
			tex_to_preview = tb.texture_normal
			tb.mouse_entered.connect(_show_card_preview.bind(tex_to_preview))
			tb.mouse_exited.connect(_hide_card_preview)
			cv.add_child(tb)
		else:
			var button := Button.new()
			button.custom_minimum_size = Vector2(150, 120)
			button.text = "%s\n%s" % [FriendlyCards.title_of(serial), FriendlyCards.text_of(serial)]
			button.tooltip_text = tip
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.pressed.connect(_on_card_chosen.bind(i))
			cv.add_child(button)
		# Riga: iniziative A/B/C + tipo ferita + tipo carta
		var info_row := HBoxContainer.new()
		info_row.add_theme_constant_override("separation", 4)
		cv.add_child(info_row)
		var init_lbl := Label.new()
		var ia := FriendlyCards.initiative_for(serial, "Able")
		var ib := FriendlyCards.initiative_for(serial, "Baker")
		var ic := FriendlyCards.initiative_for(serial, "Charlie")
		init_lbl.text = "A:%d B:%d C:%d" % [ia, ib, ic] if ia >= 0 else "EVENT"
		init_lbl.add_theme_font_size_override("font_size", 11)
		init_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		init_lbl.add_theme_color_override("font_color", Color(0.80, 0.85, 0.75))
		info_row.add_child(init_lbl)
		if wound >= 0:
			var wound_lbl := Label.new()
			wound_lbl.text = WOUND_SYMBOLS.get(wound, "")
			wound_lbl.add_theme_font_size_override("font_size", 11)
			wound_lbl.add_theme_color_override("font_color", WOUND_COLORS.get(wound, Color.WHITE))
			info_row.add_child(wound_lbl)
		# Badge tipo carta
		var kind_lbl := Label.new()
		kind_lbl.text = KIND_LABELS.get(kind, "")
		kind_lbl.add_theme_font_size_override("font_size", 10)
		var kind_col := Color(0.65, 0.80, 0.95) if kind == FriendlyCards.Kind.DISCARD \
			else Color(0.95, 0.88, 0.55) if kind == FriendlyCards.Kind.ORDER \
			else Color(0.95, 0.60, 0.30)
		kind_lbl.add_theme_color_override("font_color", kind_col)
		cv.add_child(kind_lbl)
	hand_panel.show()


# Linee di vista dall'unita' selezionata verso ogni avversario in vista
# di mappa (verde = LOS libera, rosso = bloccata). Risponde alla domanda
# "questi due si vedono?" con un click sul tuo uomo.
func _update_los_lines(c: Character) -> void:
	map_view.los_lines = []
	if c == null or c.is_dead():
		map_view.queue_redraw()
		return
	# Mostra solo i bersagli effettivamente colpibili, non tutti i visibili:
	# evita di evidenziare nemici fuori gittata, in abbazia, incompatibili
	# con l'arma corrente, ecc.
	for target in TurnSequence.valid_fire_targets(state, c):
		map_view.los_lines.append({
			"to": map_view.hex_center(target.position.x, target.position.y),
			"clear": true,
		})
	map_view.queue_redraw()


func _update_played_card_bar() -> void:
	if state == null or state.friendly_card_played < 0:
		played_card_bar.hide()
		if hand_discard_button != null:
			hand_discard_button.hide()
		return
	var serial := state.friendly_card_played
	var kind := FriendlyCards.kind_of(serial)
	var wound := FriendlyCards.wound_of(serial)
	var kind_str: String = KIND_LABELS.get(kind, "")
	var wound_str: String = WOUND_SYMBOLS.get(wound, "")
	var wound_color: Color = WOUND_COLORS.get(wound, Color.WHITE)
	var wound_col: String = wound_color.to_html(false)
	var effect := FriendlyCards.text_of(serial)
	var lines: Array[String] = []
	lines.append("[b]Carta giocata:[/b] %s [color=#%s][b]%s[/b][/color]  " % [
		FriendlyCards.title_of(serial), kind_col_hex(kind), kind_str])
	if not effect.is_empty():
		lines.append("[i]%s[/i]  " % effect)
	lines.append("Ferita: [color=#%s][b]%s[/b][/color]" % [wound_col, wound_str])
	played_card_text.text = "  ".join(lines)
	played_card_bar.show()
	# Mostra il pulsante "Carte in mano" se ci sono DISCARD cards rimanenti.
	var discard_count := _count_discard_in_hand()
	if hand_discard_button != null:
		if discard_count > 0:
			hand_discard_button.text = "Carte (%d)" % discard_count
			hand_discard_button.show()
		else:
			hand_discard_button.hide()


func kind_col_hex(kind: int) -> String:
	match kind:
		FriendlyCards.Kind.ORDER:   return "f3e88a"
		FriendlyCards.Kind.DISCARD: return "88ccff"
		_:                          return "ff9944"


func _count_discard_in_hand() -> int:
	var n := 0
	for s in state.friendly_hand:
		if FriendlyCards.kind_of(s) == FriendlyCards.Kind.DISCARD:
			n += 1
	return n


# Apre/chiude il popup con le DISCARD cards rimaste in mano durante il turno.
func _toggle_discard_popup() -> void:
	if discard_popup.visible:
		discard_popup.hide()
		return
	# Ricostruisce il contenuto ogni volta.
	for child in discard_popup.get_children():
		child.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.custom_minimum_size = Vector2(280, 0)
	discard_popup.add_child(box)
	var title := Label.new()
	title.text = "Carte DISCARD in mano"
	title.add_theme_color_override("font_color", Color(0.88, 0.95, 0.65))
	box.add_child(title)
	box.add_child(HSeparator.new())
	var found := false
	for s in state.friendly_hand:
		if FriendlyCards.kind_of(s) != FriendlyCards.Kind.DISCARD:
			continue
		found = true
		var row := HBoxContainer.new()
		box.add_child(row)
		var lbl := Label.new()
		lbl.text = "[%d] %s" % [s, FriendlyCards.title_of(s)]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 13)
		row.add_child(lbl)
		# Carta Initiative (14/18): pulsante "Usa" per cambiare l'ordine di
		# un uomo immediatamente (giocabile in ORDERS e ACTION phase).
		if s in FriendlyCards.INITIATIVE and phase in [Phase.ORDERS, Phase.ACTION]:
			var use_btn := Button.new()
			use_btn.text = "Usa"
			use_btn.custom_minimum_size = Vector2(50, 0)
			var serial_cap: int = s
			use_btn.pressed.connect(func():
				discard_popup.hide()
				FriendlyCards.use_from_hand(state, [serial_cap],
					"cambia l'ordine di un uomo")
				_initiative_card_pending = true
				hint_label.text = "Carta Initiative: clicca un uomo per cambiarne l'ordine"
				_update_played_card_bar()
				_refresh())
			row.add_child(use_btn)
		var desc := Label.new()
		desc.text = FriendlyCards.text_of(s)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 11)
		desc.modulate = Color(0.78, 0.78, 0.70)
		desc.custom_minimum_size = Vector2(280, 0)
		box.add_child(desc)
	if not found:
		var empty := Label.new()
		empty.text = "(nessuna carta DISCARD in mano)"
		empty.modulate = Color(0.6, 0.6, 0.6)
		box.add_child(empty)
	var close := Button.new()
	close.text = "Chiudi"
	close.pressed.connect(func(): discard_popup.hide())
	box.add_child(close)
	discard_popup.show()


# Vehicle Display (Rule 31): stato del mezzo + roster dell'equipaggio.
# Mostra ruolo, morale e ferite di ogni crew, e se e' a bordo o sceso.
func _show_vehicle_display(vehicle: Character) -> void:
	_display_vehicle = vehicle
	for child in vehicle_popup.get_children():
		child.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.custom_minimum_size = Vector2(140, 0)
	vehicle_popup.add_child(box)
	# Barra-titolo: afferrala per spostare la finestra col mouse.
	var header := _title_bar(vehicle.vehicle_type)
	box.add_child(header)
	_make_draggable(vehicle_popup, header)
	# Stato dello scafo.
	var hull_str := "Intatto"
	var hull_col := Color(0.6, 0.85, 0.6)
	if vehicle.hull_damage >= 2:
		hull_str = "DISTRUTTO"
		hull_col = Color(0.95, 0.30, 0.20)
	elif vehicle.hull_damage == 1:
		hull_str = "Immobilizzato"
		hull_col = Color(0.95, 0.70, 0.25)
	var hull := Label.new()
	hull.text = "Scafo: %s" % hull_str
	hull.add_theme_color_override("font_color", hull_col)
	box.add_child(hull)
	# Rule 31.1.3: stato di carica del cannone principale (AFV con torretta).
	if VehicleCombat.has_turret(vehicle):
		var gun := Label.new()
		gun.text = "Cannone: %s" % ("carico" if vehicle.main_gun_loaded else "da ricaricare")
		gun.add_theme_color_override("font_color",
			Color(0.55, 0.8, 0.55) if vehicle.main_gun_loaded else Color(0.9, 0.75, 0.3))
		box.add_child(gun)
	# Rule 31.7/31.10: boccaporto (AFV) o mezzo scoperto.
	var hatch := Label.new()
	if VehicleCombat.has_turret(vehicle):
		hatch.text = "Boccaporto: %s" % ("chiuso" if vehicle.is_buttoned_up else "aperto (equipaggio esposto)")
	else:
		hatch.text = "Mezzo scoperto (equipaggio esposto)"
	hatch.add_theme_color_override("font_color",
		Color(0.6, 0.75, 0.95) if (VehicleCombat.has_turret(vehicle) and vehicle.is_buttoned_up) else Color(0.9, 0.75, 0.4))
	box.add_child(hatch)
	box.add_child(HSeparator.new())
	var crew_head := _section_label("EQUIPAGGIO")
	box.add_child(crew_head)
	if vehicle.crew.is_empty():
		var none := Label.new()
		none.text = "(nessun equipaggio modellato)"
		none.modulate = Color(0.6, 0.6, 0.6)
		box.add_child(none)
	else:
		box.add_child(_build_vehicle_schematic(vehicle))
		if vehicle.side == Domain.Side.FRIENDLY:
			var hint := Label.new()
			hint.text = "Clic su un membro per assegnare l'ordine"
			hint.add_theme_font_size_override("font_size", 10)
			hint.modulate = Color(0.65, 0.65, 0.6)
			box.add_child(hint)
	box.add_child(HSeparator.new())
	var close := Button.new()
	close.text = "Chiudi"
	close.pressed.connect(func():
		_display_vehicle = null
		vehicle_popup.hide())
	box.add_child(close)
	vehicle_popup.show()


# Ricostruisce il Vehicle Display (segnalini ordine sull'equipaggio) se aperto.
func _refresh_vehicle_display() -> void:
	if _display_vehicle != null and vehicle_popup.visible:
		_show_vehicle_display(_display_vehicle)


# Display mat del veicolo (assets/displays/<stem>.png) per tipo.
const VEHICLE_DISPLAYS := {
	"M4A3 Sherman":   "display-M4A3",
	"PzIVH":          "display-PzIVH",
	"Jeep":           "display-Jeep",
	"M3A1 Halftrack": "display-M3A1",
	"GMC 2.5t":       "display-GMC",
	"Opel Blitz":     "display-Opel",
}

# Centro della casella di ogni ruolo sul mat, in frazione di larghezza/altezza.
# Valori rilevati dai bordi reali dei box (tools di analisi sui mat).
const DISPLAY_BOXES := {
	"M4A3 Sherman": {
		"Driver": Vector2(0.526, 0.162), "Loader": Vector2(0.526, 0.293),
		"Co-Driver": Vector2(0.859, 0.162), "Gunner": Vector2(0.859, 0.293),
		"Commander": Vector2(0.859, 0.398),
	},
	"PzIVH": {
		"Driver": Vector2(0.526, 0.162), "Loader": Vector2(0.526, 0.293),
		"Co-Driver": Vector2(0.859, 0.162), "Gunner": Vector2(0.859, 0.293),
		"Commander": Vector2(0.859, 0.398),
	},
	"Jeep": {
		"Driver": Vector2(0.525, 0.206), "Co-Driver": Vector2(0.859, 0.206),
	},
	"M3A1 Halftrack": {
		"Driver": Vector2(0.475, 0.155), "Co-Driver": Vector2(0.645, 0.155),
		"Gunner": Vector2(0.875, 0.155),
	},
	"GMC 2.5t": {
		"Driver": Vector2(0.345, 0.175), "Co-Driver": Vector2(0.695, 0.175),
	},
	"Opel Blitz": {
		"Driver": Vector2(0.345, 0.250), "Co-Driver": Vector2(0.695, 0.250),
	},
}

# Nomi e descrizioni degli ordini di movimento del Driver (terminologia veicoli).
const DRIVER_ORDER_NAMES: Dictionary = {
	Domain.Order.HIDE:        "Spot & Halt",
	Domain.Order.SNEAK:       "Crawl",
	Domain.Order.RUN_AND_GUN: "Ahead Slow",
	Domain.Order.SPRINT:      "Forward / Fast",
	Domain.Order.EVADE:       "Evasive Maneuver",
	Domain.Order.DUCK_BACK:   "Stop!",
}
const DRIVER_ORDER_DESC: Dictionary = {
	Domain.Order.HIDE:        "Ferma il veicolo; il Commander avvista normalmente. Nessun movimento.",
	Domain.Order.SNEAK:       "Movimento lento e cauto (1 hex agli impulsi 2 e 4). Difficile da individuare.",
	Domain.Order.RUN_AND_GUN: "Avanza e spara: muove 1 hex agli impulsi 1 e 3, il Gunner puo' sparare agli impulsi 2 e 4 con -2 WS.",
	Domain.Order.SPRINT:      "Avanzata rapida (1-2-2-2 hex per impulso). Molto esposto al fuoco nemico.",
	Domain.Order.EVADE:       "Movimento evasivo zigzag (1 hex a ogni impulso). Difficile da colpire.",
	Domain.Order.DUCK_BACK:   "Fermata d'emergenza (Duck Back). Nessun movimento.",
}
const DRIVER_ORDER_MARKER: Dictionary = {
	Domain.Order.HIDE:        "Spot-Marker-f",
	Domain.Order.SNEAK:       "Crawl-Marker-f",
	Domain.Order.RUN_AND_GUN: "Ahead-Slow-Marker-f",
	Domain.Order.SPRINT:      "Forwrd-Marker-f",
	Domain.Order.EVADE:       "Evade-Marker-1-f",
	Domain.Order.DUCK_BACK:   "STOP-Marker-f",
}

const VEHICLE_DISPLAY_W := 240.0


# Vehicle Display: il mat reale del veicolo come sfondo, con le pedine
# dell'equipaggio piazzate nelle caselle dei rispettivi ruoli (Rule 31). Su un
# veicolo amico le pedine di Gunner/Co-Driver sono cliccabili per il fuoco.
func _build_vehicle_schematic(vehicle: Character) -> Control:
	var boxes: Dictionary = DISPLAY_BOXES.get(vehicle.vehicle_type, {})
	if boxes.is_empty():
		return _crew_text_list(vehicle)
	# Griglia posizionale: col=sinistra/destra dello scafo, riga=fronte/retro.
	# I token sono grandi come quelli sulla mappa (64px), piazzati nelle caselle
	# del rispettivo ruolo in disposizione spaziale fedele al regolamento.
	const CS := 64.0
	const PAD := 10.0
	const BADGE_H := 16.0
	const CELL_W := CS + PAD
	const CELL_H := CS + BADGE_H + PAD
	# Coordinate x e y uniche (tolleranza 4%) per ricavare col/riga di griglia.
	var xs := []
	var ys := []
	for ctr in boxes.values():
		var found := false
		for ex in xs:
			if abs(ex - ctr.x) < 0.04: found = true; break
		if not found: xs.append(ctr.x)
		found = false
		for ey in ys:
			if abs(ey - ctr.y) < 0.04: found = true; break
		if not found: ys.append(ctr.y)
	xs.sort()
	ys.sort()
	var gw := xs.size() * CELL_W + PAD
	var gh := ys.size() * CELL_H + PAD
	var grid := Control.new()
	grid.custom_minimum_size = Vector2(gw, gh)
	var crew_by_role := {}
	for cm in vehicle.crew:
		crew_by_role[cm.crew_role] = cm
	for role in boxes:
		var ctr: Vector2 = boxes[role]
		var col := 0
		for i in xs.size():
			if abs(xs[i] - ctr.x) < 0.04: col = i; break
		var row := 0
		for i in ys.size():
			if abs(ys[i] - ctr.y) < 0.04: row = i; break
		var ox := PAD * 0.5 + col * CELL_W
		var oy := PAD * 0.5 + row * CELL_H
		# Casella di sfondo con nome del ruolo come tooltip.
		var bg := Panel.new()
		bg.position = Vector2(ox, oy)
		bg.size = Vector2(CS, CS)
		bg.tooltip_text = role
		var bgsb := StyleBoxFlat.new()
		bgsb.bg_color = Color(0.12, 0.14, 0.20)
		bgsb.set_border_width_all(1)
		bgsb.border_color = Color(0.35, 0.38, 0.52)
		bgsb.set_corner_radius_all(3)
		bg.add_theme_stylebox_override("panel", bgsb)
		bg.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(bg)
		var cm = crew_by_role.get(role, null)
		if cm != null:
			_add_crew_token(grid, vehicle, cm, Vector2(ox, oy), CS)
	return grid


# Piazza la pedina di un membro sul mat (pos = angolo, cs = lato), con bordo per
# stato, badge dell'azione e — se amica e con fuoco — un bottone cliccabile.
func _add_crew_token(parent: Control, vehicle: Character, cm: Character, pos: Vector2, cs: float) -> void:
	var cpath := "res://assets/counters/%s-f.png" % cm.counter
	var ctex: Texture2D = load(cpath) if (not cm.counter.is_empty() and ResourceLoader.exists(cpath)) else null
	var token: Control
	if ctex != null:
		var tr := TextureRect.new()
		tr.texture = ctex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		token = tr
	else:
		var lbl := Label.new()
		lbl.text = cm.crew_role.left(3)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		token = lbl
	token.position = pos
	token.size = Vector2(cs, cs)
	token.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cm.is_dead():
		token.modulate = Color(0.55, 0.22, 0.18)
	elif not cm.embarked:
		token.modulate = Color(0.78, 0.72, 0.45)
	parent.add_child(token)
	# Bordo colorato per stato.
	var status_col := Color(0.4, 0.85, 0.4)
	if cm.is_dead():
		status_col = Color(0.85, 0.3, 0.25)
	elif not cm.embarked:
		status_col = Color(0.9, 0.8, 0.4)
	elif not cm.wounds.is_empty():
		status_col = Color(0.95, 0.7, 0.35)
	var frame := Panel.new()
	frame.position = pos
	frame.size = Vector2(cs, cs)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0, 0, 0, 0)
	fsb.set_border_width_all(3)
	fsb.border_color = status_col
	fsb.set_corner_radius_all(3)
	frame.add_theme_stylebox_override("panel", fsb)
	parent.add_child(frame)
	# Segnalino ordine corrente: sovrapposto e centrato sul counter.
	var mpath := _crew_order_marker(vehicle, cm)
	if not mpath.is_empty():
		var mtex: Texture2D = load(mpath)
		if mtex != null:
			var osz := cs * 0.78
			var mo := TextureRect.new()
			mo.texture = mtex
			mo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			mo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			mo.size = Vector2(osz, osz)
			mo.position = pos + Vector2((cs - osz) * 0.5, (cs - osz) * 0.15)
			mo.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent.add_child(mo)
	# Badge dell'azione/stato sotto la pedina.
	var act := _crew_action_text(vehicle, cm)
	if not cm.wounds.is_empty() and not cm.is_dead():
		act = "♥".repeat(cm.wounds.size()) + " " + act
	if not act.is_empty():
		var badge := Label.new()
		badge.text = act
		badge.position = Vector2(pos.x - 8, pos.y + cs - 1)
		badge.size = Vector2(cs + 16, 15)
		badge.add_theme_font_size_override("font_size", 10)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_theme_color_override("font_color", Color(1, 1, 1))
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(0.1, 0.1, 0.12, 0.85)
		bsb.set_corner_radius_all(3)
		badge.add_theme_stylebox_override("normal", bsb)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(badge)
	# Pedina cliccabile: ogni membro vivo e a bordo di un veicolo amico.
	var interactive := vehicle.side == Domain.Side.FRIENDLY and cm.embarked \
		and not cm.is_dead()
	if interactive:
		var btn := Button.new()
		btn.position = pos
		btn.size = Vector2(cs, cs)
		btn.tooltip_text = "%s — assegna ordine" % cm.crew_role
		var tsb := StyleBoxFlat.new()
		tsb.bg_color = Color(0.3, 0.6, 1.0, 0.12)
		tsb.set_border_width_all(2)
		tsb.border_color = Color(0.5, 0.75, 1.0, 0.85)
		tsb.set_corner_radius_all(3)
		btn.add_theme_stylebox_override("normal", tsb)
		btn.add_theme_stylebox_override("hover", tsb)
		btn.add_theme_stylebox_override("pressed", tsb)
		btn.pressed.connect(func() -> void:
			_open_crew_order_panel(vehicle, cm))
		parent.add_child(btn)


# Azione/stato corrente di un membro per il badge del Vehicle Display.
func _crew_action_text(vehicle: Character, cm: Character) -> String:
	if cm.is_dead():
		return "KIA" if cm.is_killed() else "fuori"
	if not cm.embarked:
		return "sceso"
	match cm.crew_role:
		"Driver":
			return DRIVER_ORDER_NAMES.get(vehicle.order,
				Domain.ORDER_NAMES[vehicle.order]) if vehicle.has_order else "—"
		"Gunner":
			if cm.has_order:
				if cm.fires_coax:
					return "coassiale"
				match cm.order:
					Domain.Order.AIMED_FIRE:       return "cannone"
					Domain.Order.SUPPRESSIVE_FIRE: return "suppressive"
					Domain.Order.RAPID_FIRE:       return "rapid"
			return "—"
		"Co-Driver":
			if not VehicleCombat.bow_mg_weapon(vehicle).is_empty() and cm.has_order:
				match cm.order:
					Domain.Order.AIMED_FIRE:       return "bow MG"
					Domain.Order.SUPPRESSIVE_FIRE: return "bow supp."
					Domain.Order.RAPID_FIRE:       return "bow rapid"
		"Loader":
			if VehicleCombat.has_turret(vehicle):
				var loaded := "carico" if vehicle.main_gun_loaded else "ricarica"
				var mode := " (%s)" % vehicle.fire_mode if not vehicle.fire_mode.is_empty() else ""
				return loaded + mode
		"Commander":
			if VehicleCombat.has_turret(vehicle):
				return "BU" if vehicle.is_buttoned_up else "aperto"
	return ""


# Pannello ordini per un membro specifico dell'equipaggio (Rule 31.11.2).
# Apre il pannello ordini sinistro con i controlli appropriati al ruolo.
func _open_crew_order_panel(vehicle: Character, cm: Character) -> void:
	for child in order_list.get_children():
		child.queue_free()
	order_title_label.text = "⠿  %s — %s" % [cm.crew_role, vehicle.vehicle_type]
	order_desc.text = "[i]Passa il mouse su un'azione per la spiegazione.[/i]"
	var side := "US" if vehicle.side == Domain.Side.FRIENDLY else "GE"
	var base := "res://assets/counters/"
	match cm.crew_role:
		"Driver":
			order_target = vehicle
			var driver_orders: Array[int] = [
				Domain.Order.HIDE, Domain.Order.SNEAK,
				Domain.Order.RUN_AND_GUN, Domain.Order.SPRINT,
				Domain.Order.EVADE, Domain.Order.DUCK_BACK,
			]
			for o: int in driver_orders:
				if Weather.order_forbidden(state.ground, o):
					continue
				var b := Button.new()
				b.text = DRIVER_ORDER_NAMES.get(o, Domain.ORDER_NAMES[o])
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				b.custom_minimum_size = Vector2(200, 0)
				if vehicle.has_order and vehicle.order == o:
					b.modulate = Color(0.5, 1.0, 0.5)
				var mk: String = DRIVER_ORDER_MARKER.get(o, "")
				var mpath := ("%s%s-%s.png" % [base, side, mk]) if not mk.is_empty() else ""
				var d := _crew_order_desc(DRIVER_ORDER_NAMES.get(o, ""), mpath,
					DRIVER_ORDER_DESC.get(o, ""), o)
				b.mouse_entered.connect(func() -> void: order_desc.text = d)
				b.pressed.connect(_on_order_selected.bind(o))
				order_list.add_child(b)
			var none := Button.new()
			none.text = "Senza ordine (fermo)"
			none.alignment = HORIZONTAL_ALIGNMENT_LEFT
			none.modulate = Color(0.8, 0.8, 0.65)
			none.mouse_entered.connect(func() -> void:
				order_desc.text = _crew_order_desc("Senza ordine", "",
					"Il veicolo non si muove questo impulso."))
			none.pressed.connect(func() -> void:
				order_panel.hide()
				vehicle.clear_order()
				state.log_event("%s resta fermo" % vehicle.vehicle_type)
				_update_orders_button()
				_refresh()
				_refresh_vehicle_display())
			order_list.add_child(none)
		"Gunner":
			var has_coax: bool = not VehicleCombat.coax_mg_weapon(vehicle).is_empty()
			var gstate := 0
			if cm.has_order:
				if cm.fires_coax:                              gstate = 4
				elif cm.order == Domain.Order.AIMED_FIRE:      gstate = 1
				elif cm.order == Domain.Order.SUPPRESSIVE_FIRE: gstate = 2
				elif cm.order == Domain.Order.RAPID_FIRE:       gstate = 3
			_add_crew_fire_btn(order_list, order_desc, "Non spara", gstate == 0,
				_crew_order_desc("Non spara", "",
					"Il Gunner non apre il fuoco questo impulso."),
				func() -> void:
					cm.fires_coax = false
					cm.clear_order()
					_update_orders_button()
					_open_crew_order_panel(vehicle, cm))
			_add_crew_fire_btn(order_list, order_desc, "Cannone Aimed", gstate == 1,
				_crew_order_desc("Cannone — Aimed Fire",
					"%s%s-Fire-Main-Marker-f.png" % [base, side],
					"Spara agli impulsi 2 e 4. Mira precisa; consuma la carica del cannone.",
					Domain.Order.AIMED_FIRE),
				func() -> void:
					cm.fires_coax = false
					cm.set_order(Domain.Order.AIMED_FIRE)
					_update_orders_button()
					_open_crew_order_panel(vehicle, cm))
			_add_crew_fire_btn(order_list, order_desc, "Cannone Supp.", gstate == 2,
				_crew_order_desc("Cannone — Suppressive Fire",
					"%s%s-SupprFire-Marker-1-f.png" % [base, side],
					"-2 WS, spara a tutti e 4 gli impulsi. Forza morale check sul bersaglio.",
					Domain.Order.SUPPRESSIVE_FIRE),
				func() -> void:
					cm.fires_coax = false
					cm.set_order(Domain.Order.SUPPRESSIVE_FIRE)
					_update_orders_button()
					_open_crew_order_panel(vehicle, cm))
			_add_crew_fire_btn(order_list, order_desc, "Cannone Rapid", gstate == 3,
				_crew_order_desc("Cannone — Rapid Fire",
					"%s%s-Fire-Main-Marker-f.png" % [base, side],
					"-2 WS, spara a tutti e 4 gli impulsi. Alta cadenza.",
					Domain.Order.RAPID_FIRE),
				func() -> void:
					cm.fires_coax = false
					cm.set_order(Domain.Order.RAPID_FIRE)
					_update_orders_button()
					_open_crew_order_panel(vehicle, cm))
			if has_coax:
				_add_crew_fire_btn(order_list, order_desc, "MG coassiale", gstate == 4,
					_crew_order_desc("MG coassiale",
						"%s%s-MG-Aimed-Marker-f.png" % [base, side],
						"Spara la MG coassiale agli impulsi 2 e 4. Non consuma la carica del cannone; richiede torretta allineata.",
						Domain.Order.AIMED_FIRE),
					func() -> void:
						cm.fires_coax = true
						cm.set_order(Domain.Order.AIMED_FIRE)
						_update_orders_button()
						_open_crew_order_panel(vehicle, cm))
		"Co-Driver":
			if not VehicleCombat.bow_mg_weapon(vehicle).is_empty():
				var border := 0
				if cm.has_order:
					match cm.order:
						Domain.Order.AIMED_FIRE:       border = 1
						Domain.Order.SUPPRESSIVE_FIRE: border = 2
						Domain.Order.RAPID_FIRE:       border = 3
				_add_crew_fire_btn(order_list, order_desc, "Non spara", border == 0,
					_crew_order_desc("Non spara", "",
						"Il Co-Driver non apre il fuoco questo impulso."),
					func() -> void:
						cm.clear_order()
						_update_orders_button()
						_open_crew_order_panel(vehicle, cm))
				_add_crew_fire_btn(order_list, order_desc, "Bow MG Aimed", border == 1,
					_crew_order_desc("Bow MG — Aimed Fire",
						"%s%s-MG-Aimed-Marker-f.png" % [base, side],
						"Serve la MG di scafo agli impulsi 2 e 4. Senza assistente usa TQ-3.",
						Domain.Order.AIMED_FIRE),
					func() -> void:
						cm.set_order(Domain.Order.AIMED_FIRE)
						_update_orders_button()
						_open_crew_order_panel(vehicle, cm))
				_add_crew_fire_btn(order_list, order_desc, "Bow MG Supp.", border == 2,
					_crew_order_desc("Bow MG — Suppressive Fire",
						"%s%s-MG-Supr-Marker-f.png" % [base, side],
						"-2 WS, spara a tutti e 4 gli impulsi. Forza morale check; senza assistente TQ-3.",
						Domain.Order.SUPPRESSIVE_FIRE),
					func() -> void:
						cm.set_order(Domain.Order.SUPPRESSIVE_FIRE)
						_update_orders_button()
						_open_crew_order_panel(vehicle, cm))
				_add_crew_fire_btn(order_list, order_desc, "Bow MG Rapid", border == 3,
					_crew_order_desc("Bow MG — Rapid Fire",
						"%s%s-MG-Rapid-Marker-f.png" % [base, side],
						"-2 WS, spara a tutti e 4 gli impulsi. Alta cadenza; senza assistente TQ-3.",
						Domain.Order.RAPID_FIRE),
					func() -> void:
						cm.set_order(Domain.Order.RAPID_FIRE)
						_update_orders_button()
						_open_crew_order_panel(vehicle, cm))
			else:
				var info := Label.new()
				info.text = "Nessuna bow MG montata."
				info.add_theme_color_override("font_color", Color(0.65, 0.65, 0.6))
				order_list.add_child(info)
		"Loader":
			if VehicleCombat.has_turret(vehicle):
				var gun_state := "[color=#88ff88]CARICO[/color]" if vehicle.main_gun_loaded \
					else "[color=#ff9966]DA RICARICARE[/color]"
				var status_lbl := RichTextLabel.new()
				status_lbl.bbcode_enabled = true
				status_lbl.text = "Cannone: %s" % gun_state
				status_lbl.fit_content = true
				status_lbl.custom_minimum_size = Vector2(200, 28)
				order_list.add_child(status_lbl)
				var mode_lbl := Label.new()
				mode_lbl.text = "Munizione: %s" % \
					(vehicle.fire_mode if not vehicle.fire_mode.is_empty() else "auto")
				mode_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
				order_list.add_child(mode_lbl)
				_add_crew_fire_btn(order_list, order_desc, "Carica AP", vehicle.fire_mode == "AP",
					_crew_order_desc("Carica AP",
						"%s%s-Load-AP-Marker-f.png" % [base, side],
						"Proiettile perforante (AP). Efficace contro blindatura; meno danno antiuomo."),
					func() -> void:
						vehicle.fire_mode = "AP"
						_open_crew_order_panel(vehicle, cm))
				_add_crew_fire_btn(order_list, order_desc, "Carica HE", vehicle.fire_mode == "HE",
					_crew_order_desc("Carica HE",
						"%s%s-Load-HE-Marker-f.png" % [base, side],
						"Proiettile esplosivo (HE). Efficace contro fanteria e strutture; inutile contro blindatura pesante."),
					func() -> void:
						vehicle.fire_mode = "HE"
						_open_crew_order_panel(vehicle, cm))
				_add_crew_fire_btn(order_list, order_desc, "Auto", vehicle.fire_mode.is_empty(),
					_crew_order_desc("Auto",
						"%s%s-Loaded-f.png" % [base, side],
						"Il sistema sceglie automaticamente la prima arma disponibile."),
					func() -> void:
						vehicle.fire_mode = ""
						_open_crew_order_panel(vehicle, cm))
			else:
				var info := Label.new()
				info.text = "Nessun cannone su questo mezzo."
				info.add_theme_color_override("font_color", Color(0.65, 0.65, 0.6))
				order_list.add_child(info)
		"Commander":
			if VehicleCombat.has_turret(vehicle):
				var hatch_btn := Button.new()
				hatch_btn.text = "Boccaporto: %s" % ("CHIUSO" if vehicle.is_buttoned_up else "APERTO")
				hatch_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
				hatch_btn.custom_minimum_size = Vector2(200, 0)
				hatch_btn.modulate = Color(0.7, 0.85, 0.98) if vehicle.is_buttoned_up \
					else Color(0.95, 0.8, 0.5)
				hatch_btn.mouse_entered.connect(func() -> void:
					order_desc.text = _crew_order_desc("Boccaporto",
						"%s%s-Button-Open-Marker-f.png" % [base, side] if not vehicle.is_buttoned_up else "",
						"[b]Chiuso[/b]: equipaggio al sicuro dal fuoco leggero, ma avvista a -2.\n[b]Aperto[/b]: avvista normalmente, ma l'equipaggio e' esposto al fuoco leggero."))
				hatch_btn.pressed.connect(func() -> void:
					vehicle.is_buttoned_up = not vehicle.is_buttoned_up
					_open_crew_order_panel(vehicle, cm))
				order_list.add_child(hatch_btn)
			_add_crew_fire_btn(order_list, order_desc, "Bail Out", false,
				_crew_order_desc("Bail Out",
					"%s%s-Bail-Out-Marker-f.png" % [base, side],
					"Tutto l'equipaggio abbandona il mezzo (Rule 31.10). Ogni superstite scende nell'hex vicino, morale -1, diventa fanteria."),
				func() -> void:
					VehicleCombat.bail_out(state, vehicle)
					order_panel.hide()
					_refresh()
					_refresh_vehicle_display())
			var info_cmd := Label.new()
			info_cmd.text = "Dirige l'avvistamento del mezzo."
			info_cmd.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
			order_list.add_child(info_cmd)
	var cancel := Button.new()
	cancel.text = "Annulla"
	cancel.modulate = Color(0.85, 0.7, 0.7)
	cancel.pressed.connect(func() -> void: order_panel.hide())
	order_list.add_child(cancel)
	order_panel.show()
	# Aggiorna i segnalini ordine sull'equipaggio nel Vehicle Display.
	_refresh_vehicle_display()


# Bottone standard per le scelte di fuoco/azione crew: evidenziato se attivo.
func _add_crew_fire_btn(container: Control, desc_lbl: RichTextLabel,
		label: String, active: bool, tooltip: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(200, 0)
	b.modulate = Color(0.5, 1.0, 0.5) if active else Color(0.85, 0.85, 0.7)
	b.mouse_entered.connect(func() -> void: desc_lbl.text = tooltip)
	b.pressed.connect(cb)
	container.add_child(b)


# Descrizione hover formattata: titolo + segnalino + testo + breakdown impulsi.
func _crew_order_desc(title: String, img: String, desc: String, order: int = -1) -> String:
	var lines: Array[String] = []
	lines.append("[b][color=#f3e88a]%s[/color][/b]" % title)
	if not img.is_empty() and ResourceLoader.exists(img):
		lines.append("[img=72]%s[/img]" % img)
	lines.append("")
	lines.append(desc)
	if order >= 0 and Orders.IMPULSES.has(order):
		lines.append("")
		lines.append("[b]Impulsi:[/b]")
		for row in Orders.track_lines(order):
			lines.append("  [b][color=#f3e88a]%s[/color][/b] - %s" % [
				row.substr(0, 1), row.substr(4)])
		var ws_mod: int = Orders.FIRE_WS_MOD.get(order, 0)
		if ws_mod != 0:
			lines.append("")
			lines.append("[b]Mod. al fuoco:[/b] %+d WS" % ws_mod)
	return "\n".join(lines)


# Percorso del segnalino-ordine corrente per un membro equipaggio (Vehicle Display overlay).
func _crew_order_marker(vehicle: Character, cm: Character) -> String:
	if cm.is_dead() or not cm.embarked:
		return ""
	var side := "US" if vehicle.side == Domain.Side.FRIENDLY else "GE"
	var base := "res://assets/counters/"
	match cm.crew_role:
		"Driver":
			if not vehicle.has_order:
				return ""
			var mk: String = DRIVER_ORDER_MARKER.get(vehicle.order, "")
			if mk.is_empty():
				return ""
			var p := "%s%s-%s.png" % [base, side, mk]
			return p if ResourceLoader.exists(p) else ""
		"Gunner":
			if not cm.has_order:
				return ""
			var mk := ""
			if cm.fires_coax:
				match cm.order:
					Domain.Order.AIMED_FIRE:       mk = "MG-Aimed-Marker-f"
					Domain.Order.SUPPRESSIVE_FIRE: mk = "MG-Supr-Marker-f"
					Domain.Order.RAPID_FIRE:       mk = "MG-Rapid-Marker-f"
			else:
				match cm.order:
					Domain.Order.AIMED_FIRE:       mk = "Fire-Main-Marker-f"
					Domain.Order.SUPPRESSIVE_FIRE: mk = "SupprFire-Marker-1-f"
					Domain.Order.RAPID_FIRE:       mk = "Fire-Main-Marker-f"
			if mk.is_empty():
				return ""
			var p := "%s%s-%s.png" % [base, side, mk]
			return p if ResourceLoader.exists(p) else ""
		"Co-Driver":
			if not cm.has_order:
				return ""
			var mk := ""
			match cm.order:
				Domain.Order.AIMED_FIRE:       mk = "MG-Aimed-Marker-f"
				Domain.Order.SUPPRESSIVE_FIRE: mk = "MG-Supr-Marker-f"
				Domain.Order.RAPID_FIRE:       mk = "MG-Rapid-Marker-f"
			if mk.is_empty():
				return ""
			var p := "%s%s-%s.png" % [base, side, mk]
			return p if ResourceLoader.exists(p) else ""
		"Loader":
			if not VehicleCombat.has_turret(vehicle):
				return ""
			var mk := ""
			match vehicle.fire_mode:
				"AP": mk = "Load-AP-Marker-f"
				"HE": mk = "Load-HE-Marker-f"
				_:    mk = "Loaded-f"
			var p := "%s%s-%s.png" % [base, side, mk]
			return p if ResourceLoader.exists(p) else ""
		"Commander":
			if not vehicle.is_buttoned_up and VehicleCombat.has_turret(vehicle):
				var p := "%s%s-Button-Open-Marker-f.png" % [base, side]
				return p if ResourceLoader.exists(p) else ""
	return ""


# Ripiego testuale se manca il mat del veicolo.
func _crew_text_list(vehicle: Character) -> Control:
	var vb := VBoxContainer.new()
	for cm in vehicle.crew:
		var row := Label.new()
		var st := "a bordo"
		if cm.is_dead():
			st = "KIA" if cm.is_killed() else "fuori"
		elif not cm.embarked:
			st = "sceso"
		row.text = "%s — %s%s" % [cm.crew_role, st, _crew_action_text(vehicle, cm)]
		vb.add_child(row)
	return vb


# Barra-titolo di una finestra fluttuante: fa anche da maniglia di trascinamento.
func _title_bar(text: String) -> Panel:
	var bar := Panel.new()
	bar.custom_minimum_size = Vector2(0, 26)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.20, 0.22, 0.28)
	sb.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = "⠿  " + text
	lbl.position = Vector2(6, 3)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(lbl)
	return bar


# Rende 'win' trascinabile col mouse afferrando la barra 'handle'. Al primo
# trascinamento la finestra passa a posizionamento libero (ancore top-left)
# preservando la posizione corrente.
func _make_draggable(win: Control, handle: Control) -> void:
	handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	handle.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				var gp := win.global_position
				win.set_anchors_preset(Control.PRESET_TOP_LEFT)
				win.grow_horizontal = Control.GROW_DIRECTION_END
				win.grow_vertical = Control.GROW_DIRECTION_END
				win.global_position = gp
				handle.set_meta("_dragging", true)
			else:
				handle.set_meta("_dragging", false)
		elif ev is InputEventMouseMotion and handle.get_meta("_dragging", false):
			win.global_position += ev.relative)



func _show_card_preview(tex: Texture2D) -> void:
	card_preview.texture = tex
	card_preview.show()


func _hide_card_preview() -> void:
	card_preview.hide()


func _show_info(hex: Vector2i, c: Character) -> void:
	_update_los_lines(c)
	var hexdata := state.hex_at(hex.x, hex.y)
	var lines: Array[String] = []
	lines.append("[b]Hex %02d.%02d[/b]  %s%s" % [
		hex.x, hex.y, Domain.TERRAIN_NAMES[hexdata.terrain],
		"  (Cover)" if Domain.terrain_gives_cover(hexdata.terrain) else "",
	])
	if c != null and c.side == Domain.Side.ENEMY and not c.known:
		lines.append("")
		lines.append("[b]Nemico non identificato[/b]")
		info_text.text = "\n".join(lines)
		return
	if c != null:
		lines.append("")
		lines.append("[b]%s[/b]  (%s, team %s)" % [c.display_name,
			"Friendly" if c.side == Domain.Side.FRIENDLY else "Enemy", c.team])
		lines.append("TQ %d  LDR %d  Morale: %s" % [
			Checks.effective_tq(c), c.leadership, Domain.MORALE_NAMES[c.morale]])
		if c.has_order:
			var extra := "" if c.order_move.is_empty() else " " + c.order_move
			lines.append("Ordine: %s%s" % [Domain.ORDER_NAMES[c.order], extra])
		if not c.weapon_skills.is_empty():
			lines.append("Armi: %s" % str(c.weapon_skills))
		if not c.wounds.is_empty():
			lines.append("Ferite: %d" % c.wounds.size())
	info_text.text = "\n".join(lines)


# Counter ID del segnalino arma da mostrare nel roster, o "" se nessuno.
# Per il Bazooka restituisce il counter dello stato ammo corrente.
func _weapon_counter_id(c: Character) -> String:
	if c.weapon_skills.is_empty():
		return ""
	var wname: String = c.weapon_skills.keys()[0]
	if wname == "Bazooka M9":
		if c.no_ammo:
			return "US-Baz-UnLoaded-Marker"
		elif c.low_ammo:
			return "US-Baz-Ammo-1-Marker"
		else:
			return "US-Baz-Loaded-Marker"
	if wname == "Panzerfaust 60" or wname == "Panzerfaust 100":
		if c.no_ammo:
			return ""  # sparato: scompare
	return WEAPON_COUNTER_ID.get(wname, "")


# Roster: una riga per uomo con indicatori visivi colorati (ferite, ammo, morale).
func _refresh_roster() -> void:
	for child in roster_body.get_children():
		child.queue_free()
	# Raggruppa per team nell'ordine di apparizione in state.characters
	var team_order: Array[String] = []
	for c in state.characters:
		if c.side == Domain.Side.FRIENDLY and not c.team in team_order:
			team_order.append(c.team)
	for team_name in team_order:
		var team_hdr := Label.new()
		team_hdr.text = "— %s —" % team_name.to_upper()
		team_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		team_hdr.add_theme_font_size_override("font_size", 11)
		team_hdr.add_theme_color_override("font_color", Color(0.98, 0.92, 0.55))
		roster_body.add_child(team_hdr)
		for c in state.characters:
			if c.side != Domain.Side.FRIENDLY or c.team != team_name:
				continue
			var row := PanelContainer.new()
			row.custom_minimum_size = Vector2(210, 0)
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var sb := StyleBoxFlat.new()
			if c.is_dead():
				sb.bg_color = Color(0.12, 0.12, 0.12)
				sb.border_color = Color(0.3, 0.3, 0.3)
			elif map_view != null and c == map_view.selected:
				sb.bg_color = Color(0.28, 0.38, 0.18)
				sb.border_color = Color(0.85, 0.95, 0.35)
				sb.border_width_left = 5
				sb.border_width_right = 3
				sb.border_width_top = 3
				sb.border_width_bottom = 3
			else:
				sb.bg_color = Color(0.18, 0.22, 0.13)
				sb.border_color = MapView.MORALE_COLORS[c.morale]
			sb.border_width_left = 5
			sb.border_width_right = 1
			sb.border_width_top = 1
			sb.border_width_bottom = 1
			sb.set_corner_radius_all(4)
			sb.set_content_margin_all(3)
			sb.content_margin_left = 8
			row.add_theme_stylebox_override("panel", sb)
			var hbox := HBoxContainer.new()
			hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hbox.add_theme_constant_override("separation", 3)
			row.add_child(hbox)
			# Thumbnail counter PNG (58x58, allineata in basso con i segnalini)
			var thumb := TextureRect.new()
			thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			thumb.custom_minimum_size = Vector2(58, 58)
			thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			thumb.size_flags_vertical = Control.SIZE_SHRINK_END
			var tex_path := "res://assets/counters/%s-f.png" % c.counter
			if ResourceLoader.exists(tex_path):
				thumb.texture = load(tex_path)
			hbox.add_child(thumb)
			# Colonna destra: nome sopra, segnalini sotto
			var col := VBoxContainer.new()
			col.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.add_theme_constant_override("separation", 3)
			hbox.add_child(col)
			var name_lbl := Label.new()
			name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_lbl.add_theme_font_size_override("font_size", 13)
			name_lbl.add_theme_color_override("font_color",
				Color(0.5, 0.5, 0.5) if c.is_dead() else Color.WHITE)
			name_lbl.text = c.display_name
			col.add_child(name_lbl)
			if c.is_dead():
				var dead_lbl := Label.new()
				dead_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
				dead_lbl.text = "KIA" if c.is_killed() else "INC"
				dead_lbl.add_theme_font_size_override("font_size", 10)
				dead_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
				col.add_child(dead_lbl)
			else:
				var markers_row := HBoxContainer.new()
				markers_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
				markers_row.add_theme_constant_override("separation", 2)
				col.add_child(markers_row)
				# Segnalino arma (M1919, M2, Bazooka, Panzerfaust…)
				var wcid := _weapon_counter_id(c)
				if not wcid.is_empty():
					var wcp := "res://assets/counters/%s-f.png" % wcid
					var wct := TextureRect.new()
					wct.mouse_filter = Control.MOUSE_FILTER_IGNORE
					wct.custom_minimum_size = Vector2(36, 36)
					wct.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					wct.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					if ResourceLoader.exists(wcp):
						wct.texture = load(wcp)
					markers_row.add_child(wct)
				# Ferite
				for wound_type in c.wounds:
					var wpath := "res://assets/counters/GEN-BadWound-Marker-1-f.png" \
						if wound_type == Domain.Wound.BAD \
						else "res://assets/counters/GEN-LightWound-Marker-1-f.png"
					var wt := TextureRect.new()
					wt.mouse_filter = Control.MOUSE_FILTER_IGNORE
					wt.custom_minimum_size = Vector2(36, 36)
					wt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					wt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					if ResourceLoader.exists(wpath):
						wt.texture = load(wpath)
					markers_row.add_child(wt)
				# Ammo generico solo se non gia' coperto dal segnalino arma
				var has_weapon_ammo := wcid.begins_with("US-Baz-")
				if not has_weapon_ammo:
					var ammo_path := ""
					if c.no_ammo:
						ammo_path = "res://assets/counters/GEN-LowAmmo-Marker-2-r.png"
					elif c.low_ammo:
						ammo_path = "res://assets/counters/GEN-LowAmmo-Marker-2-f.png"
					if not ammo_path.is_empty():
						var at := TextureRect.new()
						at.mouse_filter = Control.MOUSE_FILTER_IGNORE
						at.custom_minimum_size = Vector2(36, 36)
						at.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
						at.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
						if ResourceLoader.exists(ammo_path):
							at.texture = load(ammo_path)
						markers_row.add_child(at)
				# Morale
				var morale_path: String = MORALE_MARKERS.get(int(c.morale), "")
				if not morale_path.is_empty():
					var mt := TextureRect.new()
					mt.mouse_filter = Control.MOUSE_FILTER_IGNORE
					mt.custom_minimum_size = Vector2(36, 36)
					mt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					mt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					if ResourceLoader.exists(morale_path):
						mt.texture = load(morale_path)
					markers_row.add_child(mt)
			var ch := c
			row.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
					map_view.selected = ch
					map_view.highlight_hex = ch.position
					camera.position = map_view.hex_center(ch.position.x, ch.position.y)
					map_view.queue_redraw()
					_show_info(ch.position, ch)
					_refresh_roster()
					_refresh_enemy_roster()
					if phase == Phase.ORDERS and not ch.is_dead():
						_open_order_panel(ch))
			roster_body.add_child(row)


# Nemici avvistati nella sidebar destra (collassabile).
func _refresh_enemy_roster() -> void:
	if enemy_roster_body == null:
		return
	for child in enemy_roster_body.get_children():
		child.queue_free()
	var spotted: Array = []
	for c in state.characters:
		if c.side == Domain.Side.ENEMY and c.known and not c.embarked:
			spotted.append(c)
	if spotted.is_empty():
		var lbl := Label.new()
		lbl.text = "Nessun nemico avvistato"
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		enemy_roster_body.add_child(lbl)
		return
	for c in spotted:
		var pc := PanelContainer.new()
		pc.custom_minimum_size = Vector2(210, 0)
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := StyleBoxFlat.new()
		if c.is_dead():
			sb.bg_color = Color(0.12, 0.12, 0.12)
			sb.border_color = Color(0.3, 0.3, 0.3)
		elif map_view != null and c == map_view.selected:
			sb.bg_color = Color(0.32, 0.14, 0.14)
			sb.border_color = Color(0.95, 0.45, 0.45)
			sb.border_width_left = 5
			sb.border_width_right = 3
			sb.border_width_top = 3
			sb.border_width_bottom = 3
		else:
			sb.bg_color = Color(0.22, 0.12, 0.12)
			sb.border_color = MapView.MORALE_COLORS[c.morale]
		sb.border_width_left = 5
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.set_corner_radius_all(4)
		sb.set_content_margin_all(3)
		sb.content_margin_left = 8
		pc.add_theme_stylebox_override("panel", sb)
		var hbox := HBoxContainer.new()
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_theme_constant_override("separation", 3)
		pc.add_child(hbox)
		# Thumbnail (58x58, allineata in basso con i segnalini)
		var thumb := TextureRect.new()
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumb.custom_minimum_size = Vector2(58, 58)
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumb.size_flags_vertical = Control.SIZE_SHRINK_END
		var tex_path := "res://assets/counters/%s-f.png" % c.counter
		if ResourceLoader.exists(tex_path):
			thumb.texture = load(tex_path)
		hbox.add_child(thumb)
		# Colonna destra
		var col := VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 3)
		hbox.add_child(col)
		var name_lbl := Label.new()
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color",
			Color(0.5, 0.5, 0.5) if c.is_dead() else Color(0.95, 0.7, 0.7))
		name_lbl.text = c.display_name
		col.add_child(name_lbl)
		if c.is_dead():
			var dead_lbl := Label.new()
			dead_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dead_lbl.text = "KIA" if c.is_killed() else "INC"
			dead_lbl.add_theme_font_size_override("font_size", 10)
			dead_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			col.add_child(dead_lbl)
		else:
			var markers_row := HBoxContainer.new()
			markers_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			markers_row.add_theme_constant_override("separation", 2)
			col.add_child(markers_row)
			var ewcid := _weapon_counter_id(c)
			if not ewcid.is_empty():
				var ewcp := "res://assets/counters/%s-f.png" % ewcid
				var ewct := TextureRect.new()
				ewct.mouse_filter = Control.MOUSE_FILTER_IGNORE
				ewct.custom_minimum_size = Vector2(36, 36)
				ewct.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				ewct.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				if ResourceLoader.exists(ewcp):
					ewct.texture = load(ewcp)
				markers_row.add_child(ewct)
			for wound_type in c.wounds:
				var wpath := "res://assets/counters/GEN-BadWound-Marker-1-f.png" \
					if wound_type == Domain.Wound.BAD \
					else "res://assets/counters/GEN-LightWound-Marker-1-f.png"
				var wt := TextureRect.new()
				wt.mouse_filter = Control.MOUSE_FILTER_IGNORE
				wt.custom_minimum_size = Vector2(36, 36)
				wt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				wt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				if ResourceLoader.exists(wpath):
					wt.texture = load(wpath)
				markers_row.add_child(wt)
			var morale_path2: String = MORALE_MARKERS.get(int(c.morale), "")
			if not morale_path2.is_empty():
				var mt := TextureRect.new()
				mt.mouse_filter = Control.MOUSE_FILTER_IGNORE
				mt.custom_minimum_size = Vector2(36, 36)
				mt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				mt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				if ResourceLoader.exists(morale_path2):
					mt.texture = load(morale_path2)
				markers_row.add_child(mt)
		var ch: Character = c
		pc.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				map_view.selected = ch
				map_view.highlight_hex = ch.position
				camera.position = map_view.hex_center(ch.position.x, ch.position.y)
				map_view.queue_redraw()
				_show_info(ch.position, ch)
				_refresh_roster()
				_refresh_enemy_roster())
		enemy_roster_body.add_child(pc)


func _refresh() -> void:
	turn_label.text = "  Turno %d/%d  " % [mini(state.turn, state.max_turns), state.max_turns]
	_update_enemy_card()
	_refresh_roster()
	_refresh_enemy_roster()
	if phase != Phase.CARD:
		_update_played_card_bar()
	for line in state.drain_log():
		log_history.append(line)
		if log_show_detail or not line.begins_with("·"):
			log_text.append_text(_format_log_line(line) + "\n")
		print(line)
	map_view.queue_redraw()
	_maybe_screenshot()


# Parole chiave del log -> colore (esiti ed eventi salienti).
const LOG_KEYWORDS := {
	"COLPISCE": "#f5a623", "Mancato": "#999988", "mancato": "#999988",
	"Ferito": "#f0483a", "Light Wound": "#f0483a", "Bad Wound": "#d02015",
	"K.I.A.": "#d02015", "uccidono": "#d02015", "morto": "#d02015",
	"individua": "#f3e88a", "avvistato": "#f3e88a", "scopre": "#f3e88a",
	"esplode": "#ff7733", "granata": "#ff9955", "DISTRUTTO": "#ff5522",
	"Rally": "#7fd87f", "Duck Back": "#7fc8d8", "rinforzi": "#f3e88a",
	"BERSERK": "#c050e0", "ROUT": "#888888", "ricaricato": "#7fd87f",
}


# Ricostruisce il diario dalla cronologia (cambio del filtro "Formule").
func _rebuild_log() -> void:
	log_text.clear()
	for line in log_history:
		if log_show_detail or not line.begins_with("·"):
			log_text.append_text(_format_log_line(line) + "\n")


# Colora il log: nomi in neretto per nazione (blu USA, rosso tedeschi),
# effetti evidenziati.
func _format_log_line(line: String) -> String:
	if line.begins_with("·"):
		return "[i][color=#9aa5b0]%s[/color][/i]" % line
	var out := line
	for c in state.characters:
		if c.display_name.is_empty() or not c.display_name in out:
			continue
		var col := "#8ab4ff" if c.side == Domain.Side.FRIENDLY else "#ff9484"
		out = out.replace(c.display_name,
			"[b][color=%s]%s[/color][/b]" % [col, c.display_name])
	for kw in LOG_KEYWORDS:
		if kw in out:
			out = out.replace(kw, "[b][color=%s]%s[/color][/b]" % [LOG_KEYWORDS[kw], kw])
	return out


# ------------------------------------------------------------ auto-test

var _auto_replayed := false


func _auto_step() -> void:
	if replay_idx >= 0:
		return  # replay in corso: si lascia finire
	match phase:
		Phase.CARD:
			_on_card_chosen(0)
		Phase.ORDERS:
			for c in state.characters:
				if c.side == Domain.Side.FRIENDLY and not c.is_dead() and not c.has_order:
					c.set_order(Domain.Order.AIMED_FIRE)
			next_button.disabled = false
			_on_next_pressed()
		Phase.GAME_OVER:
			# COMBAT_REPLAY=1: esercita il replay completo prima di uscire.
			if not OS.get_environment("COMBAT_REPLAY").is_empty() and not _auto_replayed:
				_auto_replayed = true
				print("AUTO: replay di %d frame" % state.replay.size())
				_start_replay(_merge_turn_frames(state.replay))
			else:
				print("AUTO: fine partita")
				get_tree().quit()
		_:
			_on_next_pressed()


# Mostra l'ultima Enemy Card pescata (grafica originale) durante gli
# impulsi; nascosta finche' non se ne pesca una.
func _update_enemy_card() -> void:
	if state.enemy_cards_in_play.is_empty():
		enemy_card_rect.hide()
		return
	var serial: int = state.enemy_cards_in_play.values().back()
	var img := EnemyCards.image(serial)
	if img.is_empty():
		enemy_card_rect.hide()
		return
	enemy_card_rect.texture = load(img)
	enemy_card_rect.show()


# Balance test (COMBAT_BALANCE=1): simula ogni scenario N volte con seed
# diversi e stampa una tabella vittorie/sconfitte/VP per bilanciamento.
func _balance_test() -> void:
	const RUNS := 20
	var sid_filter := OS.get_environment("COMBAT_SCENARIO")
	var sids: Array = Scenario.SCENARIOS.keys()
	if not sid_filter.is_empty():
		sids = [sid_filter]
	# Intestazione tabella.
	print("")
	print("=" .repeat(82))
	print("BALANCE TEST  (%d run per scenario)" % RUNS)
	print("=" .repeat(82))
	print("%-12s %-28s  WIN%% DRAW%%  LOSS%%  avgVP  avgFK avgEK avgTR" % [
		"ID", "Nome"])
	print("-".repeat(82))
	for sid in sids:
		var sc_name: String = Scenario.SCENARIOS[sid].get("name", sid)
		var wins := 0; var draws := 0; var losses := 0
		var sum_vp := 0; var sum_fk := 0; var sum_ek := 0; var sum_turns := 0
		for run in range(RUNS):
			var st := GameState.new()
			st.rng.seed = hash(sid + str(run))
			Scenario.build(st, sid)
			# Simula la partita completa senza UI.
			var safety := 0
			while not st.game_over and safety < 200:
				safety += 1
				TurnSequence.friendly_card_phase(st, 0)
				_balance_assign_friendly_orders(st)
				TurnSequence.enemy_order_phase(st)
				TurnSequence.action_phase(st)
				TurnSequence.end_phase(st)
			# Raccogli risultati.
			var res := Scenario.victory(st, sid)
			var tl := Scenario.tally(st)
			var outcome: String = res.get("outcome", "")
			var vp: int = int(res.get("vp", 0))
			if "Vittoria" in outcome:
				wins += 1
			elif "Sconfitta" in outcome:
				losses += 1
			else:
				draws += 1
			sum_vp += vp
			sum_fk += tl["f_dead"]
			sum_ek += tl["e_dead"]
			sum_turns += st.turn - 1  # turn gia' incrementato dopo l'ultimo end_phase
		var r := float(RUNS)
		print("%-12s %-28s  %3d%%  %3d%%   %3d%%  %5.1f  %4.1f  %4.1f  %4.1f" % [
			sid, sc_name.left(28),
			int(wins * 100.0 / r), int(draws * 100.0 / r), int(losses * 100.0 / r),
			sum_vp / r, sum_fk / r, sum_ek / r, sum_turns / r])
	print("=" .repeat(82))
	print("WIN=Vittoria/Vittoria*  DRAW=Pareggio/risicata  LOSS=Sconfitta")
	print("FK=caduti friendly  EK=nemici eliminati  TR=turni giocati")
	print("")
	get_tree().quit(0)


# Assegna automaticamente ordini ai personaggi friendly per il balance test.
# Strategia semplice: fuoco se c'e' un nemico vivo noto entro gittata,
# altrimenti ADVANCE verso la parte nemica della mappa.
func _balance_assign_friendly_orders(st: GameState) -> void:
	for c in st.characters:
		if c.side != Domain.Side.FRIENDLY or c.is_dead() or c.embarked:
			continue
		if c.is_vehicle:
			c.set_order(Domain.Order.AIMED_FIRE)
			continue
		if c.is_medic:
			c.set_order(Domain.Order.HIDE)
			continue
		var legal := TurnSequence.legal_orders(st, c)
		# Tenta AIMED_FIRE se c'e' un bersaglio.
		var has_fire_target := false
		if Domain.Order.AIMED_FIRE in legal:
			var targets := TurnSequence.valid_fire_targets(st, c)
			if not targets.is_empty():
				c.set_order(Domain.Order.AIMED_FIRE)
				has_fire_target = true
		if not has_fire_target:
			# Avanza verso la zona nemica.
			if Domain.Order.RUN_AND_GUN in legal:
				c.set_order(Domain.Order.RUN_AND_GUN)
			elif Domain.Order.SPRINT in legal:
				c.set_order(Domain.Order.SPRINT)
			elif Domain.Order.SNEAK in legal:
				c.set_order(Domain.Order.SNEAK)
			elif Domain.Order.HIDE in legal:
				c.set_order(Domain.Order.HIDE)
			elif not legal.is_empty():
				c.set_order(legal[0])


# Self-test (COMBAT_SELFTEST=1): proprieta' che devono valere sempre.
# Oggi: simmetria della LOS su tutte le coppie di tutti gli scenari.
func _selftest() -> void:
	var failures := 0
	for sid in Scenario.SCENARIOS:
		var st := GameState.new()
		st.rng.seed = hash(sid)
		Scenario.build(st, sid)
		for i in range(st.characters.size()):
			for j in range(i + 1, st.characters.size()):
				var a: Character = st.characters[i]
				var b: Character = st.characters[j]
				if LOS.clear(st, a, b) != LOS.clear(st, b, a):
					failures += 1
					print("ASIMMETRIA LOS in %s: %s <-> %s (%s / %s)" % [
						sid, a.display_name, b.display_name,
						str(a.position), str(b.position)])
	failures += _test_rules()
	print("SELFTEST: %s (%d problemi)" % [
		"OK" if failures == 0 else "FALLITO", failures])
	get_tree().quit(0 if failures == 0 else 1)


# Micro-test deterministici delle regole nuove (mischia, carte DISCARD,
# vento, rout fuori mappa, registrazione replay).
func _test_rules() -> int:
	var fails := 0
	# Mischia (Rule 15): rivela il bersaglio nello stesso hex.
	var st := GameState.new()
	st.rng.seed = 5
	Boards.fill(st, "farmhouse")
	var atk := Character.new("a", "Atk", Domain.Side.FRIENDLY, "Able")
	atk.troop_quality = 9
	atk.weapon_skills = {"M1 Garand": 5}
	atk.position = Vector2i(10, 10)
	var def := Character.new("d", "Def", Domain.Side.ENEMY, "Red")
	def.troop_quality = 3
	def.weapon_skills = {"KAR 98K": 3}
	def.position = Vector2i(10, 10)
	st.characters.append(atk)
	st.characters.append(def)
	atk.set_order(Domain.Order.CHARGE)
	TurnSequence._do_melee(st, atk)
	if not def.known:
		print("TEST mischia: bersaglio non rivelato")
		fails += 1
	# Extra Mag dalla mano: ricarica e scarta la carta.
	atk.no_ammo = true
	st.friendly_hand = [15]
	TurnSequence._use_proactive_discards(st)
	if atk.no_ammo or st.friendly_hand.has(15) or not st.friendly_discard.has(15):
		print("TEST Extra Mag: non applicata")
		fails += 1
	# Fumo che deriva col vento nella End Phase.
	st.compass = Move.compass_from_dir1(Vector3i(0, 1, -1))
	st.wind = st.compass[1]  # nord: riga -1
	st.area_markers = [{"type": Area.Type.SMOKE, "hex": Vector2i(10, 5),
		"placed_turn": 1, "turns_left": 2}]
	Area.end_phase(st)
	if st.area_markers.is_empty() or st.area_markers[0]["hex"] != Vector2i(10, 4):
		print("TEST vento: il fumo non deriva")
		fails += 1
	# Nemico in ROUT esce dal bordo mappa (eliminato per i VP).
	def.morale = Domain.Morale.ROUT
	def.position = Vector2i(10, 0)
	var res := Move.compass_step(st, def, [1])
	if res != 2 or not def.routed_off or not def.removed:
		print("TEST rout: non esce dalla mappa (res %d)" % res)
		fails += 1
	# Il replay registra i passi di movimento.
	st.replay.clear()
	atk.position = Vector2i(10, 10)
	Move.step_to(st, atk, Vector2i(10, 11))
	Move.step_to(st, atk, Vector2i(10, 12))
	if st.replay.is_empty() or st.replay[0]["moves"].values()[0].size() != 3:
		print("TEST replay: passi non registrati")
		fails += 1
	fails += _test_ss_skills()
	fails += _test_weapons()
	fails += _test_weather()
	fails += _test_terrain()
	fails += _test_knife()
	fails += _test_fire()
	fails += _test_medic()
	fails += _test_wire()
	fails += _test_abbey()
	fails += _test_vehicles()
	fails += _test_grenade()
	return fails


# Granata a mano: frammentazione Near/Far (Rule 14.2).
func _test_grenade() -> int:
	var fails := 0
	var st := GameState.new()
	st.rng.seed = 5
	Boards.fill(st, "farmhouse")
	st.turn = 1
	st.max_turns = 12
	# Terreno aperto per un modificatore di copertura noto.
	st.hex_at(10, 10).terrain = Domain.Terrain.OPEN_LEVEL_0
	var tgt := Character.new("t", "Tgt", Domain.Side.ENEMY, "Red")
	tgt.troop_quality = 5
	tgt.weapon_skills = {"KAR 98K": 3}
	tgt.position = Vector2i(10, 10)
	var adj := Character.new("j", "Adj", Domain.Side.ENEMY, "Red")
	adj.troop_quality = 5
	adj.position = Vector2i(10, 11)  # adiacente
	st.characters.append(tgt)
	st.characters.append(adj)
	# Bersaglio senza ordine in aperto: gruppo "no order" -> +1 alla Order/Terrain Chart.
	if Fire.cover_modifier(st, tgt) != 1:
		print("TEST granata: cover_modifier errato (%d)" % Fire.cover_modifier(st, tgt))
		fails += 1
	# Granata che esplode nell'hex del bersaglio.
	st.area_markers = [{"type": Area.Type.GRENADE, "hex": Vector2i(10, 10),
		"placed_turn": 1, "turns_left": 1, "thrower_ws": 4}]
	Area.end_phase(st)
	# Il marcatore granata deve essere consumato dall'esplosione.
	for m in st.area_markers:
		if m["type"] == Area.Type.GRENADE:
			print("TEST granata: marcatore non consumato")
			fails += 1
			break
	# Chi e' nell'hex viene investito (rivelato dall'attacco).
	if not tgt.known:
		print("TEST granata: bersaglio nell'hex non investito")
		fails += 1
	# L'adiacente fa solo un MC: non viene rivelato dalla scheggia.
	if adj.known:
		print("TEST granata: adiacente rivelato per errore")
		fails += 1
	return fails


# Abbazia (Volume 2, Rule 27.5).
func _test_abbey() -> int:
	var fails := 0
	var st := GameState.new()
	st.map[GameState.hex_key(0, 0)] = GameState.MapHex.new(Domain.Terrain.OPEN_LEVEL_0)
	st.map[GameState.hex_key(0, 1)] = GameState.MapHex.new(Domain.Terrain.OPEN_LEVEL_0)
	st.map[GameState.hex_key(0, 2)] = GameState.MapHex.new(Domain.Terrain.ABBEY_INTERIOR)
	var firer := Character.new("f", "F", Domain.Side.FRIENDLY, "Able")
	firer.troop_quality = 6
	firer.weapon_skills = {"M1 Garand": 6}
	firer.position = Vector2i(0, 0)
	var tgt := Character.new("t", "T", Domain.Side.ENEMY, "Red")
	tgt.troop_quality = 5
	tgt.position = Vector2i(0, 2)
	# Da fuori non si colpisce un hex interno...
	if Fire.can_fire(st, firer, tgt, "M1 Garand"):
		print("TEST abbazia: l'interno non e' immune da fuori")
		fails += 1
	# ...ma da dentro l'abbazia si'.
	st.map[GameState.hex_key(0, 0)].terrain = Domain.Terrain.ABBEY_EXTERIOR
	if not Fire.can_fire(st, firer, tgt, "M1 Garand"):
		print("TEST abbazia: da dentro dovrebbe poter colpire l'interno")
		fails += 1
	# Copertura dipendente dal tiratore: bersaglio esterno in Hide (gruppo 0).
	var st2 := GameState.new()
	st2.map[GameState.hex_key(0, 0)] = GameState.MapHex.new(Domain.Terrain.OPEN_LEVEL_0)
	st2.map[GameState.hex_key(0, 1)] = GameState.MapHex.new(Domain.Terrain.OPEN_LEVEL_0)
	st2.map[GameState.hex_key(0, 2)] = GameState.MapHex.new(Domain.Terrain.ABBEY_EXTERIOR)
	var sh := Character.new("s", "S", Domain.Side.FRIENDLY, "Able")
	sh.troop_quality = 6
	sh.weapon_skills = {"M1 Garand": 6}
	sh.position = Vector2i(0, 0)
	var hid := Character.new("h", "H", Domain.Side.ENEMY, "Red")
	hid.troop_quality = 5
	hid.position = Vector2i(0, 2)
	hid.set_order(Domain.Order.HIDE)
	var ws_out: int = Fire._compute_ws(st2, sh, hid, "M1 Garand")["ws"]
	st2.map[GameState.hex_key(0, 0)].terrain = Domain.Terrain.ABBEY_EXTERIOR
	var ws_in: int = Fire._compute_ws(st2, sh, hid, "M1 Garand")["ws"]
	if ws_in - ws_out != 2:  # -5 (fuori) vs -3 (dentro) sul gruppo Hide
		print("TEST abbazia: copertura tiratore-dipendente errata (%d vs %d)" % [ws_in, ws_out])
		fails += 1
	# -1 per ogni hex d'abbazia attraversato.
	var st3 := GameState.new()
	st3.map[GameState.hex_key(0, 1)] = GameState.MapHex.new(Domain.Terrain.ABBEY_INTERIOR)
	st3.map[GameState.hex_key(0, 2)] = GameState.MapHex.new(Domain.Terrain.ABBEY_EXTERIOR)
	if Fire._abbey_hexes_crossed(st3, Vector2i(0, 0), Vector2i(0, 3)) != 2:
		print("TEST abbazia: conteggio hex attraversati errato")
		fails += 1
	# LOS: dentro l'abbazia non e' bloccata; da fuori il muro esterno blocca.
	var st4 := GameState.new()
	st4.map[GameState.hex_key(0, 0)] = GameState.MapHex.new(Domain.Terrain.ABBEY_INTERIOR)
	st4.map[GameState.hex_key(0, 1)] = GameState.MapHex.new(Domain.Terrain.ABBEY_EXTERIOR)
	st4.map[GameState.hex_key(0, 2)] = GameState.MapHex.new(Domain.Terrain.ABBEY_INTERIOR)
	if not LOS.clear_positions(st4, Vector2i(0, 0), Vector2i(0, 2), 0, 0, false):
		print("TEST abbazia: LOS interna dovrebbe essere libera")
		fails += 1
	st4.map[GameState.hex_key(0, 0)].terrain = Domain.Terrain.OPEN_LEVEL_0  # osservatore fuori
	if LOS.clear_positions(st4, Vector2i(0, 0), Vector2i(0, 2), 0, 0, false):
		print("TEST abbazia: il muro esterno dovrebbe bloccare da fuori")
		fails += 1
	return fails


# Filo spinato (Volume 2, Rule 27.7).
func _test_wire() -> int:
	var fails := 0
	var st := GameState.new()
	st.map[GameState.hex_key(0, 0)] = GameState.MapHex.new(Domain.Terrain.OPEN_LEVEL_0)
	var firer := Character.new("f", "F", Domain.Side.FRIENDLY, "Able")
	firer.troop_quality = 6
	firer.weapon_skills = {"M1 Garand": 6}
	firer.position = Vector2i(0, 0)
	var tgt := Character.new("t", "T", Domain.Side.ENEMY, "Red")
	tgt.troop_quality = 5
	tgt.position = Vector2i(0, 2)
	# -1 al WS sparando dal filo spinato.
	var ws_open: int = Fire._compute_ws(st, firer, tgt, "M1 Garand")["ws"]
	st.map[GameState.hex_key(0, 0)].wire = true
	var ws_wire: int = Fire._compute_ws(st, firer, tgt, "M1 Garand")["ws"]
	if ws_open - ws_wire != 1:
		print("TEST filo spinato: -1 al WS dall'interno errato")
		fails += 1
	# Ordine di movimento nemico (non Sneak) -> Sneak.
	var en := Character.new("en", "En", Domain.Side.ENEMY, "Red")
	en.troop_quality = 5
	en.position = Vector2i(0, 0)
	st.characters = [en]
	TurnSequence._set_enemy_order(st, en, Domain.Order.RUN_AND_GUN, "3")
	if en.order != Domain.Order.SNEAK:
		print("TEST filo spinato: ordine di movimento non ridotto a Sneak")
		fails += 1
	# legal_orders del giocatore: niente Sprint dall'interno, Sneak si'.
	var fr := Character.new("fr", "Fr", Domain.Side.FRIENDLY, "Able")
	fr.troop_quality = 6
	fr.position = Vector2i(0, 0)
	st.characters = [fr]
	var orders := TurnSequence.legal_orders(st, fr)
	if Domain.Order.SPRINT in orders or Domain.Order.SNEAK not in orders:
		print("TEST filo spinato: legal_orders non filtra il movimento")
		fails += 1
	# Auto-Hide: in un hex con 2 nemici, il TQ piu' basso passa in Hide.
	var a := Character.new("a", "A", Domain.Side.ENEMY, "Red")
	a.troop_quality = 6
	a.position = Vector2i(0, 0)
	var b := Character.new("b", "B", Domain.Side.ENEMY, "Red")
	b.troop_quality = 3
	b.position = Vector2i(0, 0)
	st.characters = [a, b]
	TurnSequence._wire_auto_hide(st)
	if b.order != Domain.Order.HIDE or a.has_order:
		print("TEST filo spinato: auto-Hide del TQ piu' basso errato")
		fails += 1
	# TQC per uscire: fallendo si resta impigliati (nessun movimento).
	var seed := 1
	while true:
		var probe := RandomNumberGenerator.new()
		probe.seed = seed
		if probe.randi_range(0, 9) > 3:  # > TQ 3 -> TQC fallito
			break
		seed += 1
	var sw := GameState.new()
	sw.rng.seed = seed
	for col in range(3, 9):
		for row in range(3, 12):
			sw.map[GameState.hex_key(col, row)] = GameState.MapHex.new(Domain.Terrain.OPEN_LEVEL_0)
	sw.map[GameState.hex_key(5, 5)].wire = true
	var stuck := Character.new("st", "St", Domain.Side.ENEMY, "Red")
	stuck.troop_quality = 3
	stuck.position = Vector2i(5, 5)
	stuck.set_order(Domain.Order.SNEAK)
	var prey := Character.new("pr", "Pr", Domain.Side.FRIENDLY, "Able")
	prey.troop_quality = 6
	prey.position = Vector2i(5, 9)
	sw.characters = [stuck, prey]
	if Move.move_character(sw, stuck, 1) != 0 or stuck.position != Vector2i(5, 5):
		print("TEST filo spinato: il TQC d'uscita fallito non trattiene")
		fails += 1
	return fails


# Medici addestrati (Volume 2, Rule 30).
func _test_medic() -> int:
	var fails := 0
	# Medico disarmato: nessun bersaglio di fuoco possibile.
	var st := GameState.new()
	var medic := Character.new("md", "Doc", Domain.Side.FRIENDLY, "Able")
	medic.troop_quality = 5
	medic.is_medic = true
	medic.position = Vector2i(5, 5)
	var foe := Character.new("fo", "Foe", Domain.Side.ENEMY, "Red")
	foe.troop_quality = 5
	foe.known = true
	foe.position = Vector2i(5, 6)
	st.characters = [medic, foe]
	if not TurnSequence.valid_fire_targets(st, medic).is_empty():
		print("TEST medico: disarmato non puo' sparare")
		fails += 1
	# legal_orders: niente fuoco/mischia, ma Medical Aid si'.
	var orders := TurnSequence.legal_orders(st, medic)
	if Domain.Order.AIMED_FIRE in orders or Domain.Order.CHARGE in orders \
			or Domain.Order.MEDICAL_AID not in orders:
		print("TEST medico: legal_orders non filtra il combattimento")
		fails += 1
	# Enemy medic: un ordine di fuoco diventa Medical Aid.
	var emed := Character.new("em", "Sani", Domain.Side.ENEMY, "Red")
	emed.troop_quality = 5
	emed.is_medic = true
	TurnSequence._set_enemy_order(st, emed, Domain.Order.AIMED_FIRE)
	if emed.order != Domain.Order.MEDICAL_AID:
		print("TEST medico: ordine di fuoco non convertito in cura")
		fails += 1
	# +2 TQ alla cura: con un tiro che passa solo grazie al +2.
	var seed := 1
	var roll := 0
	while true:
		var probe := RandomNumberGenerator.new()
		probe.seed = seed
		roll = probe.randi_range(0, 9)
		if roll >= 2:
			break
		seed += 1
	for as_medic in [true, false]:
		var sm := GameState.new()
		sm.rng.seed = seed
		var doc := Character.new("d2", "D2", Domain.Side.FRIENDLY, "Able")
		doc.troop_quality = roll - 1  # senza +2 il tiro fallisce
		doc.is_medic = as_medic
		doc.position = Vector2i(2, 2)
		var hurt := Character.new("hu", "Hurt", Domain.Side.FRIENDLY, "Able")
		hurt.troop_quality = 6
		hurt.position = Vector2i(2, 3)
		hurt.wounds = [Domain.Wound.LIGHT]
		sm.characters = [doc, hurt]
		TurnSequence._do_medic(sm, doc)
		var cured := hurt.wounds.is_empty()
		if cured != as_medic:
			print("TEST medico: +2 TQ alla cura errato (medic=%s, curato=%s)" % [as_medic, cured])
			fails += 1
	# Mai mischia: se un avversario entra nel suo hex, il medico fugge.
	var sf := GameState.new()
	sf.rng.seed = 9
	for col in range(3, 8):
		for row in range(3, 8):
			sf.map[GameState.hex_key(col, row)] = GameState.MapHex.new(Domain.Terrain.OPEN_LEVEL_0)
	var doc2 := Character.new("d3", "D3", Domain.Side.FRIENDLY, "Able")
	doc2.troop_quality = 5
	doc2.is_medic = true
	doc2.position = Vector2i(5, 5)
	var att := Character.new("at", "Att", Domain.Side.ENEMY, "Red")
	att.troop_quality = 6
	att.position = Vector2i(5, 5)
	att.set_order(Domain.Order.CHARGE)
	sf.characters = [doc2, att]
	TurnSequence._do_melee(sf, att)
	if doc2.position == Vector2i(5, 5) or not doc2.wounds.is_empty():
		print("TEST medico: dovrebbe fuggire dalla mischia illeso")
		fails += 1
	# Rule 30.1: alla caduta del medico friendly, i compagni con LOS reagiscono.
	var sk := GameState.new()
	sk.rng.seed = 2
	var kia := -1
	for s in FriendlyCards.CARDS:
		if FriendlyCards.wound_of(s) == FriendlyCards.WoundDraw.KIA:
			kia = s
			break
	sk.friendly_deck = [kia, kia]
	var mdead := Character.new("mm", "MM", Domain.Side.FRIENDLY, "Able")
	mdead.troop_quality = 5
	mdead.is_medic = true
	mdead.position = Vector2i(0, 0)
	var witness := Character.new("wi", "Wi", Domain.Side.FRIENDLY, "Able")
	witness.troop_quality = 8  # cosi' la reazione cambia sempre il morale
	witness.position = Vector2i(0, 1)
	sk.characters = [mdead, witness]
	Fire._resolve_wound(sk, null, mdead)
	if not mdead.is_dead() or witness.morale == Domain.Morale.NORMAL:
		print("TEST medico: nessuna reazione alla caduta del medico")
		fails += 1
	# Rule 30.2: micro-AI del medico nemico (Hide / Medical Aid / Evade).
	var sa := GameState.new()
	var emedic := Character.new("e", "E", Domain.Side.ENEMY, "Red")
	emedic.troop_quality = 5
	emedic.is_medic = true
	emedic.position = Vector2i(5, 5)
	sa.characters = [emedic]
	TurnSequence._assign_enemy_order(sa, emedic, 1)
	if emedic.order != Domain.Order.HIDE:
		print("TEST medico nemico: senza feriti dovrebbe fare Hide")
		fails += 1
	var w1 := Character.new("w1", "W1", Domain.Side.ENEMY, "Red")
	w1.troop_quality = 5
	w1.position = Vector2i(5, 6)  # adiacente
	w1.wounds = [Domain.Wound.LIGHT]
	sa.characters = [emedic, w1]
	TurnSequence._assign_enemy_order(sa, emedic, 1)
	if emedic.order != Domain.Order.MEDICAL_AID:
		print("TEST medico nemico: ferito adiacente -> Medical Aid")
		fails += 1
	w1.position = Vector2i(5, 8)  # dist 3 (entro 4)
	TurnSequence._assign_enemy_order(sa, emedic, 1)
	if emedic.order != Domain.Order.EVADE:
		print("TEST medico nemico: ferito vicino -> si muove (Evade)")
		fails += 1
	# Rule 30 (convenzione): con TQ+2=9 il nemico evita SEMPRE il medico amico.
	var sav := GameState.new()
	sav.rng.seed = 77
	var ef := Character.new("ef", "Firer", Domain.Side.ENEMY, "Red")
	ef.troop_quality = 7  # TQ+2=9 >= ogni d10 -> evita sempre
	ef.weapon_skills = {"Rifle": 5}
	ef.position = Vector2i(2, 2)
	ef.set_order(Domain.Order.AIMED_FIRE)
	var mav := Character.new("mav", "DocAv", Domain.Side.FRIENDLY, "Able")
	mav.troop_quality = 5
	mav.is_medic = true
	mav.position = Vector2i(2, 3)
	mav.spotted = true
	sav.characters = [ef, mav]
	TurnSequence._try_fire(sav, ef)
	if not mav.wounds.is_empty():
		print("TEST medico (Rule 30 convenzione): l'AI non dovrebbe sparare al medico (TQ+2=9)")
		fails += 1
	# Rule 30 (revenge): la morte del medico porta i Berserk ad eseguire i prigionieri.
	var rev_seed := 1
	while true:
		var probe := RandomNumberGenerator.new()
		probe.seed = rev_seed
		if probe.randi_range(0, 9) == 0:
			break
		rev_seed += 1
	var srv := GameState.new()
	srv.rng.seed = rev_seed
	var mrev := Character.new("mr", "DocR", Domain.Side.FRIENDLY, "Able")
	mrev.troop_quality = 5
	mrev.is_medic = true
	mrev.position = Vector2i(3, 3)
	var wrev := Character.new("wr", "WiR", Domain.Side.FRIENDLY, "Able")
	wrev.troop_quality = 5
	wrev.morale = Domain.Morale.BOLD  # con roll==0 (+2) -> BERSERK
	wrev.position = Vector2i(3, 4)  # adiacente al medico (LOS sempre ok)
	var pris := Character.new("pr", "Prig", Domain.Side.ENEMY, "Red")
	pris.troop_quality = 5
	pris.set_order(Domain.Order.GUARD)
	pris.position = Vector2i(3, 5)  # adiacente al witness
	srv.characters = [mrev, wrev, pris]
	Fire._medic_shock(srv, mrev)  # il roll==0 porta wrev a BERSERK
	if not pris.is_dead():
		print("TEST medico (Rule 30 revenge): il prigioniero dovrebbe essere giustiziato")
		fails += 1
	return fails


# Incendi (Volume 2, Rule 29).
func _test_fire() -> int:
	var fails := 0
	# Solo il terreno infiammabile prende fuoco.
	if not Area.burnable(Domain.Terrain.TREES) or Area.burnable(Domain.Terrain.OPEN_LEVEL_0):
		print("TEST incendio: tabella infiammabilita' errata")
		fails += 1
	# fire_at / smoke_penalty / passabilita'.
	var st := GameState.new()
	st.map[GameState.hex_key(3, 3)] = GameState.MapHex.new(Domain.Terrain.TREES)
	st.area_markers = [{"type": Area.Type.FIRE, "hex": Vector2i(3, 3),
		"placed_turn": 1, "turns_left": 99}]
	if Area.fire_at(st, Vector2i(3, 3)) != Area.Type.FIRE \
			or Area.smoke_penalty(st, Vector2i(3, 3)) != -3:
		print("TEST incendio: fire_at/smoke_penalty errati")
		fails += 1
	if Move.is_passable(st, Vector2i(3, 3)):
		print("TEST incendio: l'hex in fiamme non e' passabile")
		fails += 1
	var charger := Character.new("ch", "Ch", Domain.Side.FRIENDLY, "Able")
	charger.position = Vector2i(3, 2)
	charger.set_order(Domain.Order.CHARGE)
	if Move.can_enter(st, charger, Vector2i(3, 3)):
		print("TEST incendio: nemmeno la carica entra nelle fiamme")
		fails += 1
	st.area_markers[0]["type"] = Area.Type.RAGING_FIRE
	if Area.smoke_penalty(st, Vector2i(3, 3)) != -4 \
			or Area.fire_at(st, Vector2i(3, 3)) != Area.Type.RAGING_FIRE:
		print("TEST incendio: furioso = -4")
		fails += 1
	# Chi resta nelle fiamme pesca una ferita (non nel turno in cui nasce).
	var st2 := GameState.new()
	st2.rng.seed = 1
	st2.max_turns = 10
	st2.turn = 2
	st2.map[GameState.hex_key(3, 3)] = GameState.MapHex.new(Domain.Terrain.TREES)
	st2.area_markers = [{"type": Area.Type.FIRE, "hex": Vector2i(3, 3),
		"placed_turn": 1, "turns_left": 99}]
	var victim := Character.new("v", "V", Domain.Side.FRIENDLY, "Able")
	victim.troop_quality = 6
	victim.position = Vector2i(3, 3)
	st2.characters = [victim]
	st2.friendly_deck = [17]  # carta con Light Wound
	Area.end_phase(st2)
	if victim.wounds.is_empty():
		print("TEST incendio: chi e' nel fuoco non e' ferito")
		fails += 1
	# Un incendio appena nato non ferisce nello stesso turno.
	var st3 := GameState.new()
	st3.rng.seed = 1
	st3.max_turns = 10
	st3.turn = 1
	st3.map[GameState.hex_key(3, 3)] = GameState.MapHex.new(Domain.Terrain.TREES)
	st3.area_markers = [{"type": Area.Type.FIRE, "hex": Vector2i(3, 3),
		"placed_turn": 1, "turns_left": 99}]
	var v3 := Character.new("v3", "V3", Domain.Side.FRIENDLY, "Able")
	v3.troop_quality = 6
	v3.position = Vector2i(3, 3)
	st3.characters = [v3]
	st3.friendly_deck = [17]
	Area.end_phase(st3)
	if not v3.wounds.is_empty():
		print("TEST incendio: il fuoco appena nato non dovrebbe ferire")
		fails += 1
	return fails


# Coltello da lancio del Knife Expert (Rule 24): WS = TQ - gittata, gittata 2,
# e "flip" (rivelazione) solo se NON in copertura.
func _test_knife() -> int:
	var fails := 0
	var st := GameState.new()
	st.rng.seed = 4
	var ke := Character.new("ke", "Knife", Domain.Side.FRIENDLY, "Able")
	ke.troop_quality = 7
	ke.skills = [Character.SKILL_KNIFE_EXPERT]
	ke.position = Vector2i(0, 0)
	var t1 := Character.new("t1", "T1", Domain.Side.ENEMY, "Red")
	t1.troop_quality = 5
	t1.position = Vector2i(0, 1)  # dist 1
	var t2 := Character.new("t2", "T2", Domain.Side.ENEMY, "Red")
	t2.troop_quality = 5
	t2.position = Vector2i(0, 2)  # dist 2
	var t3 := Character.new("t3", "T3", Domain.Side.ENEMY, "Red")
	t3.troop_quality = 5
	t3.position = Vector2i(0, 3)  # dist 3 (fuori gittata)
	# WS = TQ - gittata (+1 dell'open, no-order): 7-1+1=7, 7-2+1=6.
	if Fire._compute_ws(st, ke, t1, "Thrown Knife")["ws"] != 7 \
			or Fire._compute_ws(st, ke, t2, "Thrown Knife")["ws"] != 6:
		print("TEST coltello: WS = TQ - gittata errato")
		fails += 1
	# Gittata massima 2 hex.
	if not Fire.can_fire(st, ke, t2, "Thrown Knife") \
			or Fire.can_fire(st, ke, t3, "Thrown Knife"):
		print("TEST coltello: gittata massima errata")
		fails += 1
	# Senza la skill non si lancia.
	var plain := Character.new("pl", "Plain", Domain.Side.FRIENDLY, "Able")
	plain.troop_quality = 7
	plain.position = Vector2i(0, 0)
	if Fire.throw_knife(st, plain, t1):
		print("TEST coltello: lancio senza skill")
		fails += 1
	# Flip: lanciando allo scoperto il nemico si rivela...
	var st2 := GameState.new()
	st2.rng.seed = 4
	var keo := Character.new("keo", "KEo", Domain.Side.ENEMY, "Red")
	keo.troop_quality = 7
	keo.skills = [Character.SKILL_KNIFE_EXPERT]
	keo.position = Vector2i(0, 0)
	var ft := Character.new("ft", "FT", Domain.Side.FRIENDLY, "Able")
	ft.troop_quality = 5
	ft.position = Vector2i(0, 1)
	st2.characters = [keo, ft]
	if not Fire.throw_knife(st2, keo, ft) or not keo.known:
		print("TEST coltello: allo scoperto dovrebbe rivelarsi")
		fails += 1
	# ...ma lanciando da copertura resta nascosto.
	var st3 := GameState.new()
	st3.rng.seed = 4
	st3.map[GameState.hex_key(0, 0)] = GameState.MapHex.new(Domain.Terrain.BUILDING)
	var kec := Character.new("kec", "KEc", Domain.Side.ENEMY, "Red")
	kec.troop_quality = 7
	kec.skills = [Character.SKILL_KNIFE_EXPERT]
	kec.position = Vector2i(0, 0)
	var ft2 := Character.new("ft2", "FT2", Domain.Side.FRIENDLY, "Able")
	ft2.troop_quality = 5
	ft2.position = Vector2i(0, 1)
	st3.characters = [kec, ft2]
	if not Fire.throw_knife(st3, kec, ft2) or kec.known:
		print("TEST coltello: in copertura dovrebbe restare nascosto")
		fails += 1
	return fails


# Nuovo terreno del Volume 2 (Rule 27): Fountain, Fortified Building, Trench.
func _test_terrain() -> int:
	var fails := 0
	# Le righe dei chart esistono con i valori letti dalle tabelle.
	if Fire.WS_MOD[Domain.Terrain.FOUNTAIN][0] != -2 \
			or Fire.WS_MOD[Domain.Terrain.FORTIFIED_BUILDING][0] != -5 \
			or Fire.WS_MOD[Domain.Terrain.TRENCH] != Fire.WS_MOD[Domain.Terrain.DEPRESSION]:
		print("TEST terreno: WS_MOD errati")
		fails += 1
	if Spotting.TERRAIN_MOD[Domain.Terrain.FORTIFIED_BUILDING] != Spotting.TERRAIN_MOD[Domain.Terrain.BUILDING] \
			or Spotting.TERRAIN_MOD[Domain.Terrain.FOUNTAIN][0] != -2:
		print("TEST terreno: TERRAIN_MOD errati")
		fails += 1
	for t in [Domain.Terrain.FOUNTAIN, Domain.Terrain.FORTIFIED_BUILDING, Domain.Terrain.TRENCH]:
		if not Domain.terrain_gives_cover(t):
			print("TEST terreno: %d non da' copertura" % t)
			fails += 1
	# Fountain (ostacolo 1/2) blocca la LOS fra due unita' a livello del suolo.
	var st := GameState.new()
	for k in [[0, 0], [0, 1], [0, 2]]:
		st.map[GameState.hex_key(k[0], k[1])] = GameState.MapHex.new(Domain.Terrain.OPEN_LEVEL_0)
	if not LOS.clear_positions(st, Vector2i(0, 0), Vector2i(0, 2), 0, 0, false):
		print("TEST fountain: aperto dovrebbe essere libero")
		fails += 1
	st.map[GameState.hex_key(0, 1)] = GameState.MapHex.new(Domain.Terrain.FOUNTAIN)
	if LOS.clear_positions(st, Vector2i(0, 0), Vector2i(0, 2), 0, 0, false):
		print("TEST fountain: dovrebbe bloccare la LOS")
		fails += 1
	# Fortified Building: la carica non puo' entrare nell'hex dell'occupante.
	var st2 := GameState.new()
	st2.map[GameState.hex_key(0, 0)] = GameState.MapHex.new(Domain.Terrain.OPEN_LEVEL_0)
	st2.map[GameState.hex_key(0, 1)] = GameState.MapHex.new(Domain.Terrain.FORTIFIED_BUILDING)
	st2.map[GameState.hex_key(0, 2)] = GameState.MapHex.new(Domain.Terrain.BUILDING)
	var mover := Character.new("m", "M", Domain.Side.FRIENDLY, "Able")
	mover.position = Vector2i(0, 0)
	mover.set_order(Domain.Order.CHARGE)
	var e1 := Character.new("e1", "E1", Domain.Side.ENEMY, "Red")
	e1.troop_quality = 5
	e1.position = Vector2i(0, 1)
	var e2 := Character.new("e2", "E2", Domain.Side.ENEMY, "Red")
	e2.troop_quality = 5
	e2.position = Vector2i(0, 2)
	st2.characters = [mover, e1, e2]
	if Move.can_enter(st2, mover, Vector2i(0, 1)):
		print("TEST fortified: la carica non dovrebbe entrare")
		fails += 1
	if not Move.can_enter(st2, mover, Vector2i(0, 2)):
		print("TEST fortified: la carica in un edificio normale e' lecita")
		fails += 1
	# Trench trattata come Depression: chi e' in trincea con ordine Hide
	# e' fuori LOS da lontano (come una depressione), non in aperto.
	var st3 := GameState.new()
	st3.map[GameState.hex_key(5, 5)] = GameState.MapHex.new(Domain.Terrain.TRENCH)
	var hider := Character.new("h", "H", Domain.Side.ENEMY, "Red")
	hider.position = Vector2i(5, 5)
	hider.set_order(Domain.Order.HIDE)
	var seer := Character.new("s", "S", Domain.Side.FRIENDLY, "Able")
	seer.position = Vector2i(5, 10)
	if LOS.clear(st3, seer, hider):
		print("TEST trench: in trincea con Hide dovrebbe essere nascosto")
		fails += 1
	st3.map[GameState.hex_key(5, 5)] = GameState.MapHex.new(Domain.Terrain.OPEN_LEVEL_0)
	if not LOS.clear(st3, seer, hider):
		print("TEST trench: in aperto dovrebbe essere visibile")
		fails += 1
	return fails


# Meteo e condizioni del terreno (Volume 2, Rule 28).
func _test_weather() -> int:
	var fails := 0
	# Malus al WS oltre i 2 hex (mappa vuota = niente edifici).
	var st := GameState.new()
	var a := Character.new("a", "A", Domain.Side.FRIENDLY, "Able")
	a.position = Vector2i(0, 0)
	var b := Character.new("b", "B", Domain.Side.ENEMY, "Red")
	st.weather = Weather.Type.RAIN
	b.position = Vector2i(0, 3)  # dist 3 (> 2)
	if Weather.ws_modifier(st, a, b, 3) != -1:
		print("TEST meteo: pioggia -1 oltre 2 hex errato")
		fails += 1
	if Weather.ws_modifier(st, a, b, 2) != 0:
		print("TEST meteo: malus applicato entro 2 hex")
		fails += 1
	st.weather = Weather.Type.FOG
	if Weather.ws_modifier(st, a, b, 3) != -2:
		print("TEST meteo: nebbia -2 errato")
		fails += 1
	# Stesso edificio: nessun malus.
	st.map[GameState.hex_key(0, 0)] = GameState.MapHex.new(Domain.Terrain.BUILDING)
	st.map[GameState.hex_key(0, 3)] = GameState.MapHex.new(Domain.Terrain.BUILDING)
	st.weather = Weather.Type.RAIN
	if Weather.ws_modifier(st, a, b, 3) != 0:
		print("TEST meteo: edificio non esenta dal malus")
		fails += 1
	# Limite di visibilita': oltre il raggio niente LOS.
	var st2 := GameState.new()
	st2.max_los = 3
	if LOS.clear_positions(st2, Vector2i(0, 0), Vector2i(0, 4), 0, 0, false):
		print("TEST visibilita': LOS non bloccata oltre il raggio")
		fails += 1
	if not LOS.clear_positions(st2, Vector2i(0, 0), Vector2i(0, 3), 0, 0, false):
		print("TEST visibilita': LOS bloccata entro il raggio")
		fails += 1
	# Demozione degli ordini per condizione del terreno.
	if Weather.demote_order(Weather.Ground.MUD, Domain.Order.SPRINT) != Domain.Order.EVADE \
			or Weather.demote_order(Weather.Ground.MUD, Domain.Order.AIMED_FIRE) != Domain.Order.AIMED_FIRE:
		print("TEST fango: demozione Sprint errata")
		fails += 1
	if Weather.demote_order(Weather.Ground.DEEP_SNOW, Domain.Order.EVADE) != Domain.Order.SNEAK \
			or Weather.demote_order(Weather.Ground.DEEP_SNOW, Domain.Order.RUN_AND_GUN) != Domain.Order.SNEAK \
			or Weather.demote_order(Weather.Ground.NONE, Domain.Order.SPRINT) != Domain.Order.SPRINT:
		print("TEST neve alta: demozione errata")
		fails += 1
	# legal_orders esclude lo Sprint sul fango.
	var st3 := GameState.new()
	st3.ground = Weather.Ground.MUD
	var fc := Character.new("f", "F", Domain.Side.FRIENDLY, "Able")
	fc.troop_quality = 6
	fc.position = Vector2i(5, 5)
	st3.characters = [fc]
	var orders := TurnSequence.legal_orders(st3, fc)
	if Domain.Order.SPRINT in orders or Domain.Order.HIDE not in orders:
		print("TEST fango: legal_orders non filtra lo Sprint")
		fails += 1
	# Winter Camouflage: -1 a essere individuato sulla neve.
	var st4 := GameState.new()
	st4.ground = Weather.Ground.SNOW
	st4.rng.seed = 3
	var spot := Character.new("s", "S", Domain.Side.FRIENDLY, "Able")
	spot.troop_quality = 6
	spot.position = Vector2i(0, 0)
	var camo := Character.new("c", "C", Domain.Side.ENEMY, "Red")
	camo.troop_quality = 5
	camo.position = Vector2i(0, 2)
	camo.skills = [Character.SKILL_WINTER_CAMO]
	var plain := Character.new("p", "P", Domain.Side.ENEMY, "Red")
	plain.troop_quality = 5
	plain.position = Vector2i(0, 2)
	var th_camo: int = Spotting.attempt(st4, spot, camo)["threshold"]
	var th_plain: int = Spotting.attempt(st4, spot, plain)["threshold"]
	if th_camo - th_plain != -1:
		print("TEST Winter Camo: -1 allo spotting errato (%d vs %d)" % [th_camo, th_plain])
		fails += 1
	# Limite di visibilita' tirato: fasce d10 corrette.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in range(60):
		var f := Weather.roll_max_los(Weather.Type.FOG, rng)
		var mi := Weather.roll_max_los(Weather.Type.MIST, rng)
		var hr := Weather.roll_max_los(Weather.Type.HEAVY_RAIN, rng)
		if f < 1 or f > 6 or mi < 5 or mi > 10 or hr < 2 or hr > 12:
			print("TEST visibilita': fasce di tiro fuori range")
			fails += 1
			break
	if Weather.roll_max_los(Weather.Type.CLEAR, rng) != 0:
		print("TEST visibilita': il sereno non e' illimitato")
		fails += 1
	# Pioggia battente -> fango col 9; con pioggia normale mai.
	var st5 := GameState.new()
	st5.rng.seed = 1
	st5.weather = Weather.Type.HEAVY_RAIN
	var became := false
	for i in range(400):
		if Weather.maybe_make_mud(st5):
			became = true
			break
	if not became or st5.ground != Weather.Ground.MUD:
		print("TEST pioggia battente: il fango non si forma")
		fails += 1
	var st6 := GameState.new()
	st6.rng.seed = 1
	st6.weather = Weather.Type.RAIN
	for i in range(50):
		if Weather.maybe_make_mud(st6):
			print("TEST pioggia normale: fango non previsto")
			fails += 1
			break
	return fails


# Nuove armi del Volume 2 (Rule 26): fasce di gittata, ROF variabile dello
# StG 44 e bonus del mirino del Springfield M1903.
func _test_weapons() -> int:
	var fails := 0
	# Thompson: gittata 16, fasce come da chart.
	if Weapons.range_ws_modifier("M1 Thompson", 6) != 0 \
			or Weapons.range_ws_modifier("M1 Thompson", 16) != -4 \
			or Weapons.range_ws_modifier("M1 Thompson", 17) != null:
		print("TEST Thompson: fasce di gittata errate")
		fails += 1
	# StG 44: ROF 3 entro 13 hex, ROF 1 oltre; fasce fino a -6 a 66 hex.
	if Weapons.rof_at("StG 44", 13) != 3 or Weapons.rof_at("StG 44", 14) != 1:
		print("TEST StG 44: ROF per gittata errato")
		fails += 1
	if Weapons.range_ws_modifier("StG 44", 66) != -6 \
			or Weapons.range_ws_modifier("StG 44", 67) != null:
		print("TEST StG 44: fasce di gittata errate")
		fails += 1
	# Armi a ROF fisso: rof_at restituisce il ROF nominale.
	if Weapons.rof_at("M1 Garand", 30) != 1 or Weapons.rof_at("M1 Thompson", 20) != 3:
		print("TEST rof_at: ROF fisso errato")
		fails += 1
	# M1903 Springfield: mirino +1 in Aimed Fire oltre i 3 hex (stesse fasce
	# del KAR 98K, cosi' la differenza isola il solo bonus del mirino).
	var st := GameState.new()
	st.rng.seed = 11
	Boards.fill(st, "farmhouse")
	st.impulse = 1
	var scoped := Character.new("sc", "Scoped", Domain.Side.FRIENDLY, "Able")
	scoped.troop_quality = 6
	scoped.weapon_skills = {"M1903 Springfield": 6}
	scoped.position = Vector2i(10, 10)
	scoped.set_order(Domain.Order.AIMED_FIRE)
	var plain := Character.new("pl", "Plain", Domain.Side.FRIENDLY, "Able")
	plain.troop_quality = 6
	plain.weapon_skills = {"KAR 98K": 6}
	plain.position = Vector2i(10, 10)
	plain.set_order(Domain.Order.AIMED_FIRE)
	var far := Character.new("fa", "Far", Domain.Side.ENEMY, "Red")
	far.position = Vector2i(10, 15)  # dist 5 (> 3 hex)
	var near := Character.new("ne", "Near", Domain.Side.ENEMY, "Red")
	near.position = Vector2i(10, 12)  # dist 2 (<= 3 hex)
	if Fire._fire_ws(st, scoped, far) - Fire._fire_ws(st, plain, far) != 1:
		print("TEST mirino: +1 mancante oltre 3 hex")
		fails += 1
	if Fire._fire_ws(st, scoped, near) - Fire._fire_ws(st, plain, near) != 0:
		print("TEST mirino: bonus errato entro 3 hex")
		fails += 1
	return fails


# Skill dei nemici Elite SS (Rule 24).
# Serial 1 = Close Call (lieve, severita' 0), serial 33 = Bad Wound (severita' 2).
func _test_ss_skills() -> int:
	var fails := 0
	var st := GameState.new()
	st.rng.seed = 7
	Boards.fill(st, "farmhouse")
	var plain_shooter := Character.new("ps", "PS", Domain.Side.FRIENDLY, "Able")
	var deadly := Character.new("de", "Deadly", Domain.Side.FRIENDLY, "Able")
	deadly.skills = [Character.SKILL_DEADLY]
	var plain_tgt := Character.new("pt", "PT", Domain.Side.ENEMY, "Red")
	plain_tgt.troop_quality = 7
	var tough := Character.new("to", "Tough", Domain.Side.ENEMY, "Red")
	tough.troop_quality = 7
	tough.skills = [Character.SKILL_TOUGH]

	# Deadly: pesca 2 (33 e 1), applica la peggiore -> 33.
	st.friendly_deck = [1, 33]
	st.friendly_discard = []
	if Fire._draw_wound(st, deadly, plain_tgt) != 33:
		print("TEST Deadly: non applica la ferita peggiore")
		fails += 1
	# Tough: pesca 2 (33 e 1), applica la meno grave -> 1.
	st.friendly_deck = [1, 33]
	st.friendly_discard = []
	if Fire._draw_wound(st, plain_shooter, tough) != 1:
		print("TEST Tough: non applica la ferita meno grave")
		fails += 1
	# Deadly vs Tough si annullano: una sola pescata (33), il 1 resta nel mazzo.
	st.friendly_deck = [1, 33]
	st.friendly_discard = []
	if Fire._draw_wound(st, deadly, tough) != 33 or st.friendly_deck != [1]:
		print("TEST Deadly vs Tough: non si annullano")
		fails += 1

	# Eagle Eyes: +1 alla TQ effettiva nello spotting, con cap a 8.
	var sp_a := Character.new("sa", "SA", Domain.Side.FRIENDLY, "Able")
	sp_a.troop_quality = 5
	sp_a.position = Vector2i(10, 10)
	var sp_b := Character.new("sb", "SB", Domain.Side.FRIENDLY, "Able")
	sp_b.troop_quality = 5
	sp_b.skills = [Character.SKILL_EAGLE_EYES]
	sp_b.position = Vector2i(10, 10)
	var tgt := Character.new("et", "ET", Domain.Side.ENEMY, "Red")
	tgt.troop_quality = 5
	tgt.position = Vector2i(10, 11)
	st.characters = [sp_a, sp_b, tgt]
	var th_a: int = Spotting.attempt(st, sp_a, tgt)["threshold"]
	tgt.known = false
	var th_b: int = Spotting.attempt(st, sp_b, tgt)["threshold"]
	tgt.known = false
	if th_a < 0 or th_b - th_a != 1:
		print("TEST Eagle Eyes: bonus +1 errato (%d vs %d)" % [th_b, th_a])
		fails += 1
	# Cap a 8: con TQ 8 il bonus non si applica.
	sp_a.troop_quality = 8
	sp_b.troop_quality = 8
	var c_a: int = Spotting.attempt(st, sp_a, tgt)["threshold"]
	tgt.known = false
	var c_b: int = Spotting.attempt(st, sp_b, tgt)["threshold"]
	tgt.known = false
	if c_b - c_a != 0:
		print("TEST Eagle Eyes: cap a 8 non rispettato (%d vs %d)" % [c_b, c_a])
		fails += 1

	# Dodge/-2 abbassa il WS del tiratore se il bersaglio e' in Evade.
	var firer := Character.new("fi", "Firer", Domain.Side.FRIENDLY, "Able")
	firer.troop_quality = 6
	firer.weapon_skills = {"M1 Garand": 6}
	firer.position = Vector2i(10, 10)
	var evader := Character.new("ev", "Evader", Domain.Side.ENEMY, "Red")
	evader.troop_quality = 6
	evader.position = Vector2i(10, 12)
	evader.set_order(Domain.Order.EVADE)
	var plain_ev := Character.new("pe", "PlainEv", Domain.Side.ENEMY, "Red")
	plain_ev.troop_quality = 6
	plain_ev.position = Vector2i(10, 12)
	plain_ev.set_order(Domain.Order.EVADE)
	evader.skills = [Character.SKILL_DODGE_2]
	st.impulse = 1
	if Fire._fire_ws(st, firer, plain_ev) - Fire._fire_ws(st, firer, evader) != 2:
		print("TEST Dodge-2: il malus al WS non vale 2")
		fails += 1

	# Sniper: +2 WS in Aimed Fire fuori dall'impulso 2.
	var sniper := Character.new("sn", "Sniper", Domain.Side.ENEMY, "Red")
	sniper.troop_quality = 6
	sniper.weapon_skills = {"KAR 98K": 6}
	sniper.skills = [Character.SKILL_SNIPER]
	sniper.position = Vector2i(10, 10)
	sniper.set_order(Domain.Order.AIMED_FIRE)
	var prey := Character.new("pr", "Prey", Domain.Side.FRIENDLY, "Able")
	prey.troop_quality = 6
	prey.position = Vector2i(10, 12)
	st.impulse = 1
	var ws_imp1 := Fire._fire_ws(st, sniper, prey)
	st.impulse = 2
	var ws_imp2 := Fire._fire_ws(st, sniper, prey)
	if ws_imp1 - ws_imp2 != 2:
		print("TEST Sniper: +2 WS in Aimed Fire (non imp.2) errato")
		fails += 1

	# Knife Expert: +1 TQ in mischia.
	var ke := Character.new("ke", "Knife", Domain.Side.ENEMY, "Red")
	ke.troop_quality = 5
	ke.skills = [Character.SKILL_KNIFE_EXPERT]
	if TurnSequence._melee_attack_tq(st, ke) - (TurnSequence._melee_tq(ke)) != 1:
		print("TEST Knife Expert: +1 TQ in mischia errato")
		fails += 1
	return fails


# Veicoli e anticarro (Rule 31-32).
func _test_vehicles() -> int:
	var fails := 0
	var st := GameState.new()
	st.rng.seed = 42
	Boards.fill(st, "farmhouse")

	# make_vehicle: crea un Character con i campi veicolo corretti.
	var sherman := VehicleCombat.make_vehicle(
		"M4A3 Sherman", Domain.Side.FRIENDLY, "Able", Vector2i(5, 5), 5)
	if not sherman.is_vehicle or sherman.vehicle_type != "M4A3 Sherman" \
			or not sherman.weapon_skills.has("75mm L40 HE"):
		print("TEST veicoli: make_vehicle Sherman errato")
		fails += 1

	# Veicolo distrutto se hull_damage >= 2.
	var pz := VehicleCombat.make_vehicle(
		"PzIVH", Domain.Side.ENEMY, "Red", Vector2i(5, 8), 2)
	if pz.is_dead():
		print("TEST veicoli: PzIVH non dovrebbe essere morto con hull_damage 0")
		fails += 1
	pz.hull_damage = 2
	if not pz.is_dead():
		print("TEST veicoli: PzIVH dovrebbe essere distrutto con hull_damage 2")
		fails += 1

	# hit_face: front se tiratore e' davanti al veicolo.
	# facing=3 → CUBE_DIRS[2]=(0,1,-1) → fronte verso nord (riga decrescente).
	pz.hull_damage = 0
	pz.facing = 3
	var face_front := VehicleCombat.hit_face(pz, Vector2i(5, 7))  # a nord del PzIVH
	var face_rear  := VehicleCombat.hit_face(pz, Vector2i(5, 9))  # a sud
	if face_front != VehicleCombat.Face.FRONT:
		print("TEST veicoli: hit_face frontale errato (%d)" % face_front)
		fails += 1
	if face_rear != VehicleCombat.Face.REAR:
		print("TEST veicoli: hit_face posteriore errato (%d)" % face_rear)
		fails += 1

	# can_fire: arma normale non puo' colpire veicolo.
	var bazooka_man := Character.new("bz", "Bazooka", Domain.Side.FRIENDLY, "Able")
	bazooka_man.troop_quality = 5
	bazooka_man.weapon_skills = {"Bazooka M9": 5}
	bazooka_man.position = Vector2i(5, 5)
	var rifleman := Character.new("rf", "Rifle", Domain.Side.FRIENDLY, "Able")
	rifleman.troop_quality = 6
	rifleman.weapon_skills = {"M1 Garand": 6}
	rifleman.position = Vector2i(5, 5)
	pz.hull_damage = 0
	pz.known = true
	pz.position = Vector2i(5, 8)
	st.characters = [bazooka_man, rifleman, pz]
	if not Fire.can_fire(st, bazooka_man, pz, "Bazooka M9"):
		print("TEST veicoli: Bazooka M9 non puo' colpire veicolo")
		fails += 1
	if Fire.can_fire(st, rifleman, pz, "M1 Garand"):
		print("TEST veicoli: M1 Garand non dovrebbe colpire veicolo")
		fails += 1

	# legal_orders: veicolo friendly ha solo gli ordini VEHICLE_ORDERS.
	var jeep := VehicleCombat.make_vehicle(
		"Jeep", Domain.Side.FRIENDLY, "Able", Vector2i(6, 5))
	st.characters = [jeep]
	var vorders := TurnSequence.legal_orders(st, jeep)
	if Domain.Order.CHARGE in vorders or Domain.Order.MEDICAL_AID in vorders:
		print("TEST veicoli: legal_orders veicolo include ordini non ammessi")
		fails += 1
	if Domain.Order.AIMED_FIRE not in vorders:
		print("TEST veicoli: legal_orders veicolo manca Aimed Fire")
		fails += 1

	# Move.can_enter: veicolo non puo' entrare in BUILDING.
	var hex_building := Vector2i(4, 4)
	st.map[GameState.hex_key(hex_building.x, hex_building.y)] = \
		GameState.MapHex.new(Domain.Terrain.BUILDING)
	if Move.can_enter(st, jeep, hex_building):
		print("TEST veicoli: il veicolo non dovrebbe entrare in BUILDING")
		fails += 1

	# at_fire: un colpo di Bazooka M9 a bruciapelo (rng deterministico)
	# deve applicare danno al veicolo bersaglio, non a fanteria.
	var az := GameState.new()
	az.rng.seed = 1
	Boards.fill(az, "farmhouse")
	var bz2 := Character.new("b2", "Bazooka2", Domain.Side.FRIENDLY, "Able")
	bz2.troop_quality = 6
	bz2.weapon_skills = {"Bazooka M9": 7}
	bz2.position = Vector2i(5, 5)
	bz2.set_order(Domain.Order.AIMED_FIRE)
	var target_pz := VehicleCombat.make_vehicle(
		"PzIVH", Domain.Side.ENEMY, "Red", Vector2i(5, 6), 5)
	target_pz.known = true
	az.characters = [bz2, target_pz]
	az.rng.seed = 0   # roll = 0 -> nat0 = colpisce sempre
	var res := VehicleCombat.at_fire(az, bz2, target_pz, "Bazooka M9")
	if not res["hit"]:
		print("TEST veicoli: at_fire nat0 non colpisce (res=%s)" % str(res))
		fails += 1

	# --- Equipaggio (Rule 31, livello intermedio) ---
	# populate_crew: il Sherman ha 5 uomini, tutti imbarcati.
	var sh := VehicleCombat.make_vehicle(
		"M4A3 Sherman", Domain.Side.FRIENDLY, "Able", Vector2i(5, 5), 4)
	if sh.crew.size() != 5:
		print("TEST equipaggio: Sherman deve avere 5 crew (%d)" % sh.crew.size())
		fails += 1
	var all_embarked := true
	for cm in sh.crew:
		if not cm.embarked or not cm.is_crew():
			all_embarked = false
	if not all_embarked:
		print("TEST equipaggio: crew non imbarcati correttamente")
		fails += 1

	# Bail out: i crew vivi scendono in mappa e lasciano il mezzo.
	var bs := GameState.new()
	bs.rng.seed = 7
	Boards.fill(bs, "farmhouse")
	var sh2 := VehicleCombat.make_vehicle(
		"M4A3 Sherman", Domain.Side.FRIENDLY, "Able", Vector2i(6, 6), 4)
	bs.characters = [sh2]
	VehicleCombat.bail_out(bs, sh2)
	if bs.characters.size() != 6:  # 1 mezzo + 5 crew scesi
		print("TEST equipaggio: bail_out non aggiunge i crew (%d)" % bs.characters.size())
		fails += 1
	for cm in sh2.crew:
		if cm.embarked:
			print("TEST equipaggio: crew ancora imbarcato dopo il bail out")
			fails += 1
			break

	# Distruzione: tutti i crew ancora a bordo muoiono.
	var ks := GameState.new()
	ks.rng.seed = 3
	Boards.fill(ks, "farmhouse")
	var pz3 := VehicleCombat.make_vehicle(
		"PzIVH", Domain.Side.ENEMY, "Red", Vector2i(7, 7), 4)
	ks.characters = [pz3]
	VehicleCombat._kill_embarked_crew(ks, pz3)
	var all_dead := true
	for cm in pz3.crew:
		if not cm.is_dead():
			all_dead = false
	if not all_dead:
		print("TEST equipaggio: distruzione non uccide tutto l'equipaggio")
		fails += 1

	# --- Facing scafo e torretta (Rule 31.4-31.6) ---
	# rotate_toward: 1 hex-side per la via piu' corta, con wrap dell'anello 1..6.
	if Move.rotate_toward(1, 1) != 1 or Move.rotate_toward(1, 2) != 2 \
			or Move.rotate_toward(1, 6) != 6 or Move.rotate_toward(6, 1) != 1:
		print("TEST veicoli: rotate_toward errato")
		fails += 1

	# dir_of_step: la direzione di un passo e' coerente con CUBE_DIRS.
	var fs := GameState.new()
	Boards.fill(fs, "farmhouse")
	var p0 := Vector2i(5, 5)
	var nb := Move.neighbors(fs, p0)
	if not nb.is_empty():
		var d := Move.dir_of_step(p0, nb[0])
		if d < 1 or d > 6 \
				or Move.from_cube(Move.to_cube(p0) + Move.CUBE_DIRS[d - 1]) != nb[0]:
			print("TEST veicoli: dir_of_step incoerente")
			fails += 1

	# Lo scafo si orienta nella direzione di marcia (Rule 31.5).
	var ms := GameState.new()
	Boards.fill(ms, "farmhouse")
	var jp := VehicleCombat.make_vehicle(
		"Jeep", Domain.Side.FRIENDLY, "Able", Vector2i(5, 5), 3)
	ms.characters = [jp]
	var jdest: Vector2i = Move.neighbors(ms, jp.position)[0]
	var want_dir := Move.dir_of_step(jp.position, jdest)
	Move.step_to(ms, jp, jdest)
	if jp.facing != want_dir:
		print("TEST veicoli: il facing scafo non segue il movimento (%d != %d)" % [
			jp.facing, want_dir])
		fails += 1

	# has_turret: AFV si, Jeep no.
	var shT := VehicleCombat.make_vehicle(
		"M4A3 Sherman", Domain.Side.FRIENDLY, "Able", Vector2i(5, 5), 3)
	if not VehicleCombat.has_turret(shT) or VehicleCombat.has_turret(jp):
		print("TEST veicoli: has_turret errato")
		fails += 1

	# turret_aim: torretta disallineata ruota (no fire), poi si allinea.
	var ts2 := GameState.new()
	Boards.fill(ts2, "farmhouse")
	var tgt := Vector2i(5, 9)
	var want := Move.dir_toward(shT.position, tgt)
	shT.turret_facing = ((want + 2) % 6) + 1   # ~3 hex-side di distanza
	var aligned := false
	var first_false := false
	for i in range(6):
		var r := VehicleCombat.turret_aim(ts2, shT, tgt)
		if i == 0 and not r:
			first_false = true
		if r:
			aligned = true
			break
	if not first_false:
		print("TEST veicoli: torretta disallineata dovrebbe ruotare senza sparare")
		fails += 1
	if not aligned or shT.turret_facing != want:
		print("TEST veicoli: la torretta non si allinea al bersaglio")
		fails += 1

	# fire_action: col cannone, torretta disallineata ruota e NON spara;
	# allineata, spara (registra il colpo).
	var fa := GameState.new()
	fa.rng.seed = 0
	Boards.fill(fa, "farmhouse")
	var shF := VehicleCombat.make_vehicle(
		"M4A3 Sherman", Domain.Side.FRIENDLY, "Able", Vector2i(5, 5), 3)
	var pzF := VehicleCombat.make_vehicle(
		"PzIVH", Domain.Side.ENEMY, "Red", Vector2i(5, 7), 4)
	pzF.known = true
	fa.characters = [shF, pzF]
	var wantF := Move.dir_toward(shF.position, pzF.position)
	shF.turret_facing = ((wantF + 2) % 6) + 1
	Fire.fire_action(fa, shF, pzF, "75mm L40 AP")
	if not fa.shots.is_empty():
		print("TEST veicoli: il cannone non deve sparare con torretta disallineata")
		fails += 1
	shF.turret_facing = wantF
	fa.rng.seed = 0
	Fire.fire_action(fa, shF, pzF, "75mm L40 AP")
	if fa.shots.is_empty():
		print("TEST veicoli: il cannone deve sparare con torretta allineata")
		fails += 1

	# Rule 31.1.3: stato di carica. Spara -> scarico -> ricarica (un impulso,
	# niente fuoco) -> torna a sparare. Torretta pre-allineata.
	var ls := GameState.new()
	ls.rng.seed = 0
	Boards.fill(ls, "farmhouse")
	var shL := VehicleCombat.make_vehicle(
		"M4A3 Sherman", Domain.Side.FRIENDLY, "Able", Vector2i(5, 5), 3)
	var pzL := VehicleCombat.make_vehicle(
		"PzIVH", Domain.Side.ENEMY, "Red", Vector2i(5, 7), 4)
	pzL.known = true
	ls.characters = [shL, pzL]
	shL.turret_facing = Move.dir_toward(shL.position, pzL.position)  # allineata
	if not shL.main_gun_loaded:
		print("TEST cannone: deve partire carico")
		fails += 1
	ls.rng.seed = 0
	Fire.fire_action(ls, shL, pzL, "75mm L40 AP")   # spara, si svuota
	if shL.main_gun_loaded or ls.shots.is_empty():
		print("TEST cannone: il primo colpo deve sparare e svuotare il cannone")
		fails += 1
	pzL.hull_damage = 0   # ripristina il bersaglio per i tiri successivi
	var n1: int = ls.shots.size()
	ls.rng.seed = 0
	Fire.fire_action(ls, shL, pzL, "75mm L40 AP")   # ricarica, niente fuoco
	if ls.shots.size() != n1 or not shL.main_gun_loaded:
		print("TEST cannone: il cannone scarico deve ricaricarsi senza sparare")
		fails += 1
	ls.rng.seed = 0
	Fire.fire_action(ls, shL, pzL, "75mm L40 AP")   # spara di nuovo
	if ls.shots.size() == n1:
		print("TEST cannone: il cannone ricaricato deve tornare a sparare")
		fails += 1

	# Rule 31.9: ordini per-membro. _crew_member trova il ruolo; il Gunner
	# riceve un ordine di fuoco col bersaglio in LOS (base del move-and-shoot).
	var cs := GameState.new()
	cs.rng.seed = 0
	Boards.fill(cs, "farmhouse")
	var pzC := VehicleCombat.make_vehicle(
		"PzIVH", Domain.Side.ENEMY, "Red", Vector2i(10, 10), 3)
	var jeepC := VehicleCombat.make_vehicle(
		"Jeep", Domain.Side.FRIENDLY, "Able", Vector2i(12, 10))
	if TurnSequence._crew_member(pzC, "Gunner") == null:
		print("TEST equipaggio: il PzIVH deve avere un Gunner")
		fails += 1
	if TurnSequence._crew_member(jeepC, "Gunner") != null:
		print("TEST equipaggio: la Jeep non ha un Gunner")
		fails += 1
	var foeC := Character.new("foeC", "Foe", Domain.Side.FRIENDLY, "Able")
	foeC.troop_quality = 6
	foeC.weapon_skills = {"M1 Garand": 6}
	foeC.position = Vector2i(10, 9)   # adiacente al PzIVH
	foeC.spotted = true
	cs.characters = [pzC, foeC]
	TurnSequence._assign_vehicle_order(cs, pzC)
	var gunC := TurnSequence._crew_member(pzC, "Gunner")
	if gunC == null or not gunC.has_order or gunC.order != Domain.Order.AIMED_FIRE:
		print("TEST equipaggio: il Gunner deve ricevere Aimed Fire col bersaglio in LOS")
		fails += 1

	# Rule 31.9: il Gunner spara anche se lo scafo non ha ordine (Driver fermo).
	# Veicolo senza ordine + Gunner AIMED_FIRE -> resolve_action lo processa e
	# il cannone spara (si svuota).
	var gs := GameState.new()
	gs.rng.seed = 0
	Boards.fill(gs, "farmhouse")
	var pzG := VehicleCombat.make_vehicle(
		"PzIVH", Domain.Side.ENEMY, "Red", Vector2i(8, 5), 3)
	var shG := VehicleCombat.make_vehicle(
		"M4A3 Sherman", Domain.Side.FRIENDLY, "Able", Vector2i(8, 6), 4)
	shG.spotted = true
	gs.characters = [pzG, shG]
	pzG.facing = Move.dir_toward(pzG.position, shG.position)
	pzG.turret_facing = Move.dir_toward(pzG.position, shG.position)
	pzG.clear_order()   # lo scafo non ha ordine (Driver fermo)
	TurnSequence._crew_member(pzG, "Gunner").set_order(Domain.Order.AIMED_FIRE)
	gs.impulse = 2
	gs.rng.seed = 0
	TurnSequence.resolve_action(gs, pzG)
	if pzG.main_gun_loaded:
		print("TEST equipaggio: il Gunner deve sparare col veicolo senza ordine")
		fails += 1

	# Rule 31.9.4b: la bow MG del Co-Driver e' un'arma separata (WS = TQ-3) e
	# spara nello stesso impulse, anche con lo scafo fermo.
	var bs2 := GameState.new()
	bs2.rng.seed = 0
	Boards.fill(bs2, "farmhouse")
	var shB := VehicleCombat.make_vehicle(
		"M4A3 Sherman", Domain.Side.FRIENDLY, "Able", Vector2i(8, 5), 3)
	var codB := TurnSequence._crew_member(shB, "Co-Driver")
	if codB == null or codB.weapon_skills.get("M1919", 0) != 4:
		print("TEST bow MG: il Co-Driver del Sherman deve avere la bow MG a TQ-3 (4)")
		fails += 1
	var enemyB := Character.new("enB", "Schutze", Domain.Side.ENEMY, "Red")
	enemyB.troop_quality = 5
	enemyB.weapon_skills = {"KAR 98K": 5}
	enemyB.position = Vector2i(8, 6)   # adiacente al Sherman
	enemyB.known = true
	bs2.characters = [shB, enemyB]
	shB.clear_order()   # scafo fermo, nessun ordine del veicolo/Gunner
	if codB != null:
		codB.set_order(Domain.Order.AIMED_FIRE)
	bs2.impulse = 2
	var shots_b: int = bs2.shots.size()
	bs2.rng.seed = 0
	TurnSequence.resolve_action(bs2, shB)
	if bs2.shots.size() == shots_b:
		print("TEST bow MG: il Co-Driver deve aver sparato la bow MG col solo suo ordine")
		fails += 1

	# Rule 31.9.4c: il Gunner puo' sparare la coassiale (WS = TQ piena) invece
	# del cannone; sparando la coax il cannone NON si scarica.
	var cx := GameState.new()
	cx.rng.seed = 0
	Boards.fill(cx, "farmhouse")
	var shX := VehicleCombat.make_vehicle(
		"M4A3 Sherman", Domain.Side.FRIENDLY, "Able", Vector2i(8, 5), 3)
	var gX := TurnSequence._crew_member(shX, "Gunner")
	if gX == null or gX.weapon_skills.get("M1919", 0) != 7:
		print("TEST coassiale: il Gunner deve avere la coax a TQ piena (7)")
		fails += 1
	var enX := Character.new("enX", "Schutze", Domain.Side.ENEMY, "Red")
	enX.troop_quality = 5
	enX.weapon_skills = {"KAR 98K": 5}
	enX.position = Vector2i(8, 6)   # adiacente
	enX.known = true
	cx.characters = [shX, enX]
	shX.facing = Move.dir_toward(shX.position, enX.position)
	shX.turret_facing = Move.dir_toward(shX.position, enX.position)
	if gX != null:
		gX.set_order(Domain.Order.AIMED_FIRE)
		gX.fires_coax = true
	shX.clear_order()
	cx.impulse = 2
	var shots_x: int = cx.shots.size()
	cx.rng.seed = 0
	TurnSequence.resolve_action(cx, shX)
	if cx.shots.size() == shots_x:
		print("TEST coassiale: il Gunner deve aver sparato la coassiale")
		fails += 1
	if not shX.main_gun_loaded:
		print("TEST coassiale: sparando la coassiale il cannone non si deve scaricare")
		fails += 1

	# Rule 31.7/31.10: boccaporto ed equipaggio esposto.
	var hx := GameState.new()
	hx.rng.seed = 0
	Boards.fill(hx, "farmhouse")
	var shH := VehicleCombat.make_vehicle("M4A3 Sherman", Domain.Side.FRIENDLY, "Able", Vector2i(8, 5), 3)
	if not shH.is_buttoned_up:
		print("TEST boccaporto: l'AFV deve partire chiuso")
		fails += 1
	if VehicleCombat.crew_exposed(shH):
		print("TEST boccaporto: un AFV chiuso non e' esposto")
		fails += 1
	shH.is_buttoned_up = false
	if not VehicleCombat.crew_exposed(shH):
		print("TEST boccaporto: un AFV aperto e' esposto")
		fails += 1
	var jeepH := VehicleCombat.make_vehicle("Jeep", Domain.Side.FRIENDLY, "Able", Vector2i(9, 5))
	if not VehicleCombat.crew_exposed(jeepH):
		print("TEST boccaporto: la Jeep (scoperta) e' sempre esposta")
		fails += 1
	# Armi leggere: non colpiscono un AFV chiuso, colpiscono uno aperto.
	var rfH := Character.new("rfH", "Rifle", Domain.Side.ENEMY, "Red")
	rfH.troop_quality = 6
	rfH.weapon_skills = {"KAR 98K": 6}
	rfH.position = Vector2i(8, 6)
	var shClosed := VehicleCombat.make_vehicle("M4A3 Sherman", Domain.Side.FRIENDLY, "Able", Vector2i(8, 5), 3)
	shClosed.spotted = true
	hx.characters = [shClosed, rfH]
	if Fire.can_fire(hx, rfH, shClosed, "KAR 98K"):
		print("TEST boccaporto: armi leggere non devono colpire un AFV chiuso")
		fails += 1
	shClosed.is_buttoned_up = false
	if not Fire.can_fire(hx, rfH, shClosed, "KAR 98K"):
		print("TEST boccaporto: armi leggere colpiscono un AFV aperto (equipaggio esposto)")
		fails += 1
	hx.rng.seed = 0   # nat0 colpisce
	Fire.fire_action(hx, rfH, shClosed, "KAR 98K")
	if hx.shots.is_empty():
		print("TEST boccaporto: il fuoco all'equipaggio esposto deve registrare uno sparo")
		fails += 1
	# Spotting: il boccaporto chiuso da' -2 alla soglia.
	var sps := GameState.new()
	sps.rng.seed = 5
	Boards.fill(sps, "farmhouse")
	var spv := VehicleCombat.make_vehicle("M4A3 Sherman", Domain.Side.FRIENDLY, "Able", Vector2i(8, 5), 6)
	var tgS := Character.new("tgS", "T", Domain.Side.ENEMY, "Red")
	tgS.troop_quality = 6
	tgS.position = Vector2i(8, 6)   # adiacente nel front arc (facing 6) -> LOS garantita
	sps.characters = [spv, tgS]
	spv.is_buttoned_up = true
	var th_closed: int = Spotting.attempt(sps, spv, tgS)["threshold"]
	spv.is_buttoned_up = false
	tgS.known = false
	var th_open: int = Spotting.attempt(sps, spv, tgS)["threshold"]
	if th_open - th_closed != 2:
		print("TEST boccaporto: chiuso deve dare -2 allo spotting (%d vs %d)" % [th_closed, th_open])
		fails += 1
	return fails


# Hook di debug per verifiche senza monitor (CI/cloud).
func _maybe_screenshot() -> void:
	var path := OS.get_environment("COMBAT_SCREENSHOT")
	if path.is_empty():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


