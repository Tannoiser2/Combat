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
var order_panel: PanelContainer   # selettore ordini con spiegazioni
var order_list: VBoxContainer
var order_desc: RichTextLabel
var order_target: Character
var enemy_card_rect: TextureRect
var card_preview: TextureRect   # anteprima ingrandita della carta sotto il mouse
var roster_box: VBoxContainer   # elenco della squadra a sinistra

# Action Phase interattiva: coda di attivazione e personaggio in attesa
# di una scelta del giocatore (fuoco/movimento).
var action_queue: Array = []
var acting: Character = null
var action_kind: int = 0   # TurnSequence.Act
var moves_left: int = 0

# Fase di schieramento: uomini ancora da piazzare e zona valida.
var deploy_queue: Array = []
var deploy_zone: Array[Vector2i] = []


func _ready() -> void:
	if not OS.get_environment("COMBAT_SELFTEST").is_empty():
		_selftest()
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

	_build_hud()
	# Fase di schieramento, se lo scenario ha una zona e siamo interattivi.
	deploy_zone = Scenario.deploy_hexes(state, scenario_id)
	if not auto_play and not deploy_zone.is_empty():
		_start_deploy()
	else:
		_start_turn()


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
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.12, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 14)
	hud.add_child(box)
	var title := Label.new()
	title.text = "COMBAT!"
	title.add_theme_font_size_override("font_size", 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Scegli lo scenario"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(0.8, 0.8, 0.7)
	box.add_child(sub)
	for sid in Scenario.SCENARIOS:
		var sc: Dictionary = Scenario.SCENARIOS[sid]
		var b := Button.new()
		b.custom_minimum_size = Vector2(540, 48)
		b.text = "%s  -  %s (%d turni)" % [sc["name"], sc["map"].capitalize(), sc["turns"]]
		b.tooltip_text = sc.get("desc", "")
		b.pressed.connect(func():
			hud.queue_free()
			_start_scenario(sid))
		box.add_child(b)
	# Etichetta di build (scritta dalla CI): smaschera le build in cache.
	var tag := Label.new()
	tag.text = "build: " + _build_tag()
	tag.modulate = Color(0.6, 0.6, 0.55)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tag)


func _build_tag() -> String:
	if FileAccess.file_exists("res://build_tag.txt"):
		return FileAccess.get_file_as_string("res://build_tag.txt").strip_edges()
	return "dev locale"


# ---------------------------------------------------------------- fasi

func _start_turn() -> void:
	phase = Phase.CARD
	acting = null
	map_view.cue_hexes = []
	TurnSequence.friendly_card_phase_prepare(state)
	_show_hand()
	next_button.disabled = true
	next_button.text = "Avanti"
	hint_label.text = "Friendly Card Phase: gioca una carta dalla mano"
	_refresh()


func _on_card_chosen(index: int) -> void:
	if phase != Phase.CARD:
		return
	TurnSequence.friendly_card_play(state, index)
	hand_panel.hide()
	phase = Phase.ORDERS
	hint_label.text = "Order Phase: clicca i tuoi uomini e assegna gli ordini"
	_update_orders_button()
	_refresh()


func _on_next_pressed() -> void:
	# In schieramento: "Posizioni standard" = accetta i default del libro.
	if phase == Phase.DEPLOY:
		deploy_queue = []
		map_view.cue_hexes = []
		_start_turn()
		return
	# Durante l'attesa di un'azione friendly, il pulsante = "passa/fine".
	if acting != null:
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
	# (non raggiunto)


func _begin_friendly_action(c: Character, act: Dictionary) -> void:
	acting = c
	action_kind = act["kind"]
	moves_left = act["hexes"]
	map_view.selected = c
	if action_kind == TurnSequence.Act.FIRE:
		var targets := TurnSequence.valid_fire_targets(state, c)
		map_view.cue_hexes = _hexes_of(targets)
		map_view.cue_color = Color(0.95, 0.2, 0.2, 0.9)
		hint_label.text = "%s: clicca un bersaglio (rosso) o premi Passa" % c.display_name
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
	_advance_action()


func _end_action_phase() -> void:
	TurnSequence.end_phase(state)
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
		hint_label.text = "End Phase: ordini rimossi"
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
		if Move.is_passable(state, n):
			out.append(n)
	return out


# C'e' davvero una scelta da fare (bersagli o hex liberi)?
func _has_options(c: Character, act: Dictionary) -> bool:
	match act["kind"]:
		TurnSequence.Act.FIRE:
			return not TurnSequence.valid_fire_targets(state, c).is_empty()
		TurnSequence.Act.MOVE:
			return not _passable_neighbors(c).is_empty()
		_:
			return false




# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	# Tasto T: overlay di verifica del terreno (confronto con la scansione).
	if event is InputEventKey and event.pressed and event.keycode == KEY_T \
			and map_view != null:
		map_view.debug_terrain = not map_view.debug_terrain
		map_view.queue_redraw()
		hint_label.text = "Overlay terreno: %s (T per cambiare)" % \
			("ON - confronta i colori con la mappa" if map_view.debug_terrain else "off")
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(1.15)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(1.0 / 1.15)
			MOUSE_BUTTON_LEFT:
				_on_map_clicked()
	elif event is InputEventMouseMotion \
			and event.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
		camera.position -= event.relative / camera.zoom.x


func _zoom(factor: float) -> void:
	var z: float = clamp(camera.zoom.x * factor, 0.15, 2.5)
	camera.zoom = Vector2(z, z)


func _on_map_clicked() -> void:
	var hex := map_view.pick_hex(map_view.get_local_mouse_position())
	if hex.x <= -99:
		return
	if phase == Phase.DEPLOY:
		_handle_deploy_click(hex)
		return
	# Durante l'azione di un proprio uomo, il click esegue fuoco/movimento.
	if acting != null:
		_handle_action_click(hex)
		return
	var c := map_view.character_at_hex(hex)
	map_view.selected = c
	map_view.highlight_hex = hex
	map_view.queue_redraw()
	_show_info(hex, c)
	# Deselezione o selezione di altro: il pannello ordini si chiude.
	order_panel.hide()
	if phase == Phase.ORDERS and c != null \
			and c.side == Domain.Side.FRIENDLY and not c.is_dead():
		_open_order_panel(c)


# Selettore ordini: bottoni a sinistra (solo quelli legali), descrizione
# con track degli impulsi a destra quando passi sopra un ordine.
func _open_order_panel(c: Character) -> void:
	order_target = c
	for child in order_list.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = "Ordine per %s" % c.display_name
	title.add_theme_color_override("font_color", Color(0.98, 0.92, 0.55))
	order_list.add_child(title)
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
	var cancel := Button.new()
	cancel.text = "Annulla"
	cancel.modulate = Color(0.85, 0.7, 0.7)
	cancel.pressed.connect(func(): order_panel.hide())
	order_list.add_child(cancel)
	order_desc.text = "[i]Passa il mouse su un ordine per la spiegazione.[/i]"
	order_panel.show()


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
		var target := map_view.character_at_hex(hex)
		if target == null or not target in TurnSequence.valid_fire_targets(state, acting):
			return  # click non valido: si ignora
		Fire.fire_action(state, acting, target, acting.weapon_skills.keys()[0])
		_finish_friendly_action()
	else:  # MOVE
		var from := acting.position
		if not Move.step_to(state, acting, hex):
			return
		moves_left -= 1
		# Scavalcare un BOCAGE esaurisce il movimento dell'impulse.
		if state.hexside_between(from, hex) == Domain.Terrain.BOCAGE:
			moves_left = 0
			state.log_event("%s scavalca il bocage e si ferma" % acting.display_name)
		if moves_left <= 0:
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
	state.log_event("%s riceve l'ordine %s" % [
		order_target.display_name, Domain.ORDER_NAMES[id]])
	_update_orders_button()
	_refresh()


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
	side_box.add_child(_section_label("DIARIO DI BATTAGLIA"))
	log_text = RichTextLabel.new()
	log_text.bbcode_enabled = true
	log_text.scroll_following = true
	log_text.fit_content = false
	log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_text.add_theme_font_size_override("normal_font_size", 13)
	side_box.add_child(log_text)
	side_box.add_child(HSeparator.new())
	# Legenda dei pallini di morale.
	var legend := RichTextLabel.new()
	legend.bbcode_enabled = true
	legend.fit_content = true
	legend.add_theme_font_size_override("normal_font_size", 12)
	var parts: Array[String] = []
	for m in Domain.MORALE_NAMES:
		parts.append("[color=#%s]●[/color]%s" % [
			MapView.MORALE_COLORS[m].to_html(false), Domain.MORALE_NAMES[m]])
	legend.text = "Morale:  " + "  ".join(parts)
	side_box.add_child(legend)

	# Roster della squadra, a sinistra (clic = seleziona e centra).
	var roster_panel := PanelContainer.new()
	roster_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	roster_panel.offset_left = 8
	roster_panel.offset_top = 224
	root.add_child(roster_panel)
	roster_box = VBoxContainer.new()
	roster_box.add_theme_constant_override("separation", 2)
	roster_panel.add_child(roster_box)

	# La mano di carte, in basso al centro
	hand_panel = PanelContainer.new()
	hand_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hand_panel.offset_top = -224
	hand_panel.offset_bottom = -12
	hand_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(hand_panel)
	hand_box = HBoxContainer.new()
	hand_panel.add_child(hand_box)

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

	# Pannello ordini con spiegazioni (al posto del vecchio PopupMenu):
	# bottoni a sinistra, descrizione al passaggio del mouse a destra.
	order_panel = PanelContainer.new()
	order_panel.set_anchors_preset(Control.PRESET_CENTER)
	order_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	order_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	order_panel.hide()
	root.add_child(order_panel)
	var order_h := HBoxContainer.new()
	order_h.add_theme_constant_override("separation", 10)
	order_panel.add_child(order_h)
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


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.65, 0.72, 0.50))
	return l


func _show_hand() -> void:
	for child in hand_box.get_children():
		child.queue_free()
	for i in range(state.friendly_hand.size()):
		var serial: int = state.friendly_hand[i]
		var tip := "Carta %d - %s\nAble %d  Baker %d  Charlie %d\n%s" % [
			serial, FriendlyCards.title_of(serial),
			FriendlyCards.initiative_for(serial, "Able"),
			FriendlyCards.initiative_for(serial, "Baker"),
			FriendlyCards.initiative_for(serial, "Charlie"),
			FriendlyCards.text_of(serial),
		]
		var img := FriendlyCards.image(serial)
		if not img.is_empty():
			# Grafica originale della carta, cliccabile; hover = ingrandimento.
			var tb := TextureButton.new()
			tb.texture_normal = load(img)
			tb.ignore_texture_size = true
			tb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			tb.custom_minimum_size = Vector2(150, 208)
			tb.tooltip_text = tip
			tb.pressed.connect(_on_card_chosen.bind(i))
			tb.mouse_entered.connect(_show_card_preview.bind(tb.texture_normal))
			tb.mouse_exited.connect(_hide_card_preview)
			hand_box.add_child(tb)
		else:
			var button := Button.new()  # ripiego testuale
			button.custom_minimum_size = Vector2(150, 195)
			button.text = "Carta %d\n%s" % [serial, FriendlyCards.title_of(serial)]
			button.tooltip_text = tip
			button.pressed.connect(_on_card_chosen.bind(i))
			hand_box.add_child(button)
	hand_panel.show()


# Linee di vista dall'unita' selezionata verso ogni avversario in vista
# di mappa (verde = LOS libera, rosso = bloccata). Risponde alla domanda
# "questi due si vedono?" con un click sul tuo uomo.
func _update_los_lines(c: Character) -> void:
	map_view.los_lines = []
	if c == null or c.is_dead():
		map_view.queue_redraw()
		return
	for other in state.characters:
		if other.side == c.side or other.is_dead():
			continue
		# verso i nemici noti (o, per un nemico selezionato, i tuoi uomini)
		if other.side == Domain.Side.ENEMY and not other.known:
			continue
		map_view.los_lines.append({
			"to": map_view.hex_center(other.position.x, other.position.y),
			"clear": LOS.clear(state, c, other),
		})
	map_view.queue_redraw()


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


# Roster: una riga per uomo con stato sintetico (morale, ferite, ammo).
func _refresh_roster() -> void:
	for child in roster_box.get_children():
		child.queue_free()
	for c in state.characters:
		if c.side != Domain.Side.FRIENDLY:
			continue
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(190, 0)
		var flags := ""
		if c.is_dead():
			flags = "  [KIA]" if c.is_killed() else "  [INCAP]"
		else:
			if not c.wounds.is_empty():
				flags += " +%d ferite" % c.wounds.size() if c.wounds.size() > 1 else " ferito"
			if c.no_ammo:
				flags += " NO AMMO"
			elif c.low_ammo:
				flags += " low ammo"
			if c.spotted:
				flags += " visto!"
		b.text = "● %s\n   %s%s" % [c.display_name, Domain.MORALE_NAMES[c.morale], flags]
		b.disabled = c.is_dead()
		b.modulate = Color(0.6, 0.6, 0.6) if c.is_dead() else Color.WHITE
		if not c.is_dead():
			b.add_theme_color_override("font_color", Color.WHITE)
			# il pallino eredita il colore del morale via icona... semplice:
			# coloriamo la prima riga con un modulate leggero non e' possibile
			# per singolo carattere: usiamo il bordo del bottone.
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.18, 0.22, 0.13)
			sb.border_color = MapView.MORALE_COLORS[c.morale]
			sb.set_border_width_all(2)
			sb.set_corner_radius_all(4)
			sb.set_content_margin_all(6)
			b.add_theme_stylebox_override("normal", sb)
		var ch := c
		b.pressed.connect(func():
			map_view.selected = ch
			map_view.highlight_hex = ch.position
			camera.position = map_view.hex_center(ch.position.x, ch.position.y)
			map_view.queue_redraw()
			_show_info(ch.position, ch))
		roster_box.add_child(b)


func _refresh() -> void:
	turn_label.text = "  Turno %d/%d  " % [mini(state.turn, state.max_turns), state.max_turns]
	_update_enemy_card()
	_refresh_roster()
	for line in state.drain_log():
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


# Colora il log: nomi in neretto per nazione (blu USA, rosso tedeschi),
# effetti evidenziati.
func _format_log_line(line: String) -> String:
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

func _auto_step() -> void:
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
			pass
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
	print("SELFTEST: %s (%d asimmetrie)" % [
		"OK" if failures == 0 else "FALLITO", failures])
	get_tree().quit(0 if failures == 0 else 1)


# Hook di debug per verifiche senza monitor (CI/cloud).
func _maybe_screenshot() -> void:
	var path := OS.get_environment("COMBAT_SCREENSHOT")
	if path.is_empty():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


