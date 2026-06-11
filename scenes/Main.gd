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

enum Phase { CARD, ORDERS, ENEMY, ACTION, END_TURN, GAME_OVER }

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
var order_menu: PopupMenu
var order_target: Character
var enemy_card_rect: TextureRect
var card_preview: TextureRect   # anteprima ingrandita della carta sotto il mouse

# Action Phase interattiva: coda di attivazione e personaggio in attesa
# di una scelta del giocatore (fuoco/movimento).
var action_queue: Array = []
var acting: Character = null
var action_kind: int = 0   # TurnSequence.Act
var moves_left: int = 0


func _ready() -> void:
	auto_play = not OS.get_environment("COMBAT_AUTO").is_empty()

	state = GameState.new()
	state.rng.seed = hash("combat-test")
	Scenario.build(state, "intro1")

	map_view = MapView.new()
	# Con la scansione in assets/maps si gioca sull'artwork vero; senza
	# (es. build web: le scansioni non sono nel repo) la stessa mappa
	# viene disegnata proceduralmente dal terreno di Boards.gd.
	if not map_view.load_board(Scenario.SCENARIOS["intro1"]["map"]):
		print("Scansione non trovata: mappa in modalita' procedurale")
	map_view.state = state
	add_child(map_view)

	camera = Camera2D.new()
	camera.position = map_view.hex_center(24, 12)  # centro dell'azione
	var z := 60.0 / map_view.cell.x
	camera.zoom = Vector2(z, z)
	add_child(camera)

	_build_hud()
	_start_turn()

	if auto_play:
		var timer := Timer.new()
		timer.wait_time = 0.4
		timer.timeout.connect(_auto_step)
		add_child(timer)
		timer.start()


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
	next_button.text = "Conferma ordini"
	next_button.disabled = not _all_friendly_ordered()
	_refresh()


func _on_next_pressed() -> void:
	# Durante l'attesa di un'azione friendly, il pulsante = "passa/fine".
	if acting != null:
		_finish_friendly_action()
		return
	match phase:
		Phase.ORDERS:
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
		var v := Scenario.victory(state, "intro1")
		hint_label.text = "Fine partita: %s" % v["outcome"]
		state.log_event("=== %s === %s" % [v["outcome"], v["detail"]])
		next_button.text = "Partita finita"
		next_button.disabled = true
	else:
		phase = Phase.END_TURN
		hint_label.text = "End Phase: ordini rimossi"
		next_button.text = "Turno %d" % state.turn
		next_button.disabled = false
	_refresh()


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


func _all_friendly_ordered() -> bool:
	for c in state.characters:
		if c.side == Domain.Side.FRIENDLY and not c.is_dead() and not c.has_order:
			return false
	return true


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
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
	# Durante l'azione di un proprio uomo, il click esegue fuoco/movimento.
	if acting != null:
		_handle_action_click(hex)
		return
	var c := map_view.character_at_hex(hex)
	map_view.selected = c
	map_view.highlight_hex = hex
	map_view.queue_redraw()
	_show_info(hex, c)
	if phase == Phase.ORDERS and c != null \
			and c.side == Domain.Side.FRIENDLY and not c.is_dead():
		order_target = c
		# Solo gli ordini legali per questo personaggio (limitazioni carte).
		order_menu.clear()
		for o in TurnSequence.legal_orders(state, c):
			order_menu.add_item(Domain.ORDER_NAMES[o], o)
		order_menu.position = Vector2i(get_viewport().get_mouse_position()) \
			+ Vector2i(8, 8)
		order_menu.popup()


func _handle_action_click(hex: Vector2i) -> void:
	if action_kind == TurnSequence.Act.FIRE:
		var target := map_view.character_at_hex(hex)
		if target == null or not target in TurnSequence.valid_fire_targets(state, acting):
			return  # click non valido: si ignora
		Fire.fire_action(state, acting, target, acting.weapon_skills.keys()[0])
		_finish_friendly_action()
	else:  # MOVE
		if not Move.step_to(state, acting, hex):
			return
		moves_left -= 1
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
	order_target.set_order(id)
	state.log_event("%s riceve l'ordine %s" % [
		order_target.display_name, Domain.ORDER_NAMES[id]])
	next_button.disabled = not _all_friendly_ordered()
	_refresh()


# ---------------------------------------------------------------- HUD

func _build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)

	# Barra superiore: turno/fase + pulsante Avanti
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud.add_child(top)
	var top_box := HBoxContainer.new()
	top.add_child(top_box)
	turn_label = Label.new()
	top_box.add_child(turn_label)
	hint_label = Label.new()
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_box.add_child(hint_label)
	next_button = Button.new()
	next_button.text = "Avanti"
	next_button.custom_minimum_size = Vector2(170, 0)
	next_button.pressed.connect(_on_next_pressed)
	top_box.add_child(next_button)

	# Log eventi in basso a sinistra
	var log_panel := PanelContainer.new()
	log_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	log_panel.offset_top = -185
	log_panel.offset_right = 520
	log_panel.offset_bottom = -8
	log_panel.offset_left = 8
	hud.add_child(log_panel)
	log_text = RichTextLabel.new()
	log_text.scroll_following = true
	log_text.fit_content = false
	log_panel.add_child(log_text)

	# Pannello info in alto a destra
	var info_panel := PanelContainer.new()
	info_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info_panel.offset_left = -300
	info_panel.offset_right = -8
	info_panel.offset_top = 44
	info_panel.offset_bottom = 280
	hud.add_child(info_panel)
	info_text = RichTextLabel.new()
	info_text.bbcode_enabled = true
	info_panel.add_child(info_text)

	# La mano di carte, in basso al centro
	hand_panel = PanelContainer.new()
	hand_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hand_panel.offset_top = -210
	hand_panel.offset_bottom = -12
	hand_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud.add_child(hand_panel)
	hand_box = HBoxContainer.new()
	hand_panel.add_child(hand_box)

	# Carta nemica pescata (grafica originale), in alto a sinistra.
	enemy_card_rect = TextureRect.new()
	enemy_card_rect.set_anchors_preset(Control.PRESET_TOP_LEFT)
	enemy_card_rect.offset_left = 8
	enemy_card_rect.offset_top = 44
	enemy_card_rect.custom_minimum_size = Vector2(120, 167)
	enemy_card_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	enemy_card_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	enemy_card_rect.hide()
	hud.add_child(enemy_card_rect)

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
	hud.add_child(card_preview)

	# Menu degli ordini
	order_menu = PopupMenu.new()
	for order in Domain.ORDER_NAMES:
		order_menu.add_item(Domain.ORDER_NAMES[order], order)
	order_menu.id_pressed.connect(_on_order_selected)
	hud.add_child(order_menu)


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


func _show_card_preview(tex: Texture2D) -> void:
	card_preview.texture = tex
	card_preview.show()


func _hide_card_preview() -> void:
	card_preview.hide()


func _show_info(hex: Vector2i, c: Character) -> void:
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


func _refresh() -> void:
	turn_label.text = "  Turno %d/%d  " % [mini(state.turn, state.max_turns), state.max_turns]
	_update_enemy_card()
	for line in state.drain_log():
		log_text.append_text(line + "\n")
		print(line)
	map_view.queue_redraw()
	_maybe_screenshot()


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


# Hook di debug per verifiche senza monitor (CI/cloud).
func _maybe_screenshot() -> void:
	var path := OS.get_environment("COMBAT_SCREENSHOT")
	if path.is_empty():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


