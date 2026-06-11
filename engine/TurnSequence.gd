## La macchina a stati della sequenza di gioco (Rule 4.0).
## Un turno = 5 step. Lo step 4 (Action) si svolge in 4 Impulse,
## e in ogni Impulse i Team agiscono in ordine di iniziativa.
##
## OSSATURA: la struttura c'e' tutta, i sottosistemi (firing, morale, LOS...)
## si innestano nei punti marcati TODO. Cosi' il gioco e' sempre eseguibile
## e si arricchisce a strati.
class_name TurnSequence
extends RefCounted


# Step 1 - Friendly Card Phase (Rule 5.0), in due meta' cosi' la UI puo'
# mostrare la mano e far scegliere il giocatore tra prepare e play.

# SOP 1a-1c: pesca se la mano e' vuota, scarta oltre il limite.
static func friendly_card_phase_prepare(state: GameState) -> void:
	if state.friendly_hand.is_empty():
		state.friendly_hand.append(state.draw_friendly_card())
	# TODO SOP 1b: aggiungere le carte messe da parte da un Plan riuscito.
	# SOP 1c: scelta del giocatore; policy provvisoria: si scartano le prime.
	while state.friendly_hand.size() > state.hand_limit:
		state.friendly_discard.append(state.friendly_hand.pop_front())


# SOP 1d-1e: gioca la carta scelta sull'Initiative Track.
static func friendly_card_play(state: GameState, index: int) -> void:
	state.friendly_card_played = state.friendly_hand.pop_at(index)
	state.log_event('Friendly gioca la carta %d: "%s"' % [
		state.friendly_card_played,
		FriendlyCards.title_of(state.friendly_card_played),
	])
	# Effetto meccanico della carta (modificatori di turno).
	FriendlyCards.apply(state, state.friendly_card_played)
	# Carta che innesca un Event (es. "They're Up to Something").
	if state.turn_fx.has("event"):
		Events.resolve(state, state.turn_fx["event"])
		state.turn_fx.erase("event")
	# SOP 1e: se la carta giocata e' una carta Event (FLASH), salvo
	# scenari "no events" si tira sulla tabella, poi si rimpiazza e si
	# rimescola (la carta Event torna nel giro).
	while FriendlyCards.kind_of(state.friendly_card_played) == FriendlyCards.Kind.EVENT:
		if not _no_events(state):
			Events.resolve(state, "friendly" if state.friendly_card_played == 51 else "enemy")
		else:
			state.log_event("Carta Event (no-events): rimescolo")
		state.friendly_discard.append(state.friendly_card_played)
		state.friendly_card_played = state.draw_friendly_card()
		state.reshuffle_friendly_deck()
		FriendlyCards.apply(state, state.friendly_card_played)


static func _no_events(state: GameState) -> bool:
	if state.scenario_id.is_empty():
		return false
	return bool(Scenario.SCENARIOS[state.scenario_id].get("no_events", false))


# Fase completa senza UI (banco di prova): gioca la prima carta.
static func friendly_card_phase(state: GameState, play_index: int = 0) -> void:
	friendly_card_phase_prepare(state)
	friendly_card_play(state, play_index)


# Step 2 - Friendly Order Phase (Rule 7.0)
static func friendly_order_phase(state: GameState) -> void:
	# TODO: il giocatore assegna un Order a ogni Friendly Character.
	pass


# Step 3 - Enemy Card and Order Phase (Rule 9.0)
static func enemy_order_phase(state: GameState) -> void:
	# Ondate di rinforzi del turno, prima di assegnare gli ordini.
	if not state.scenario_id.is_empty():
		Scenario.run_waves(state)
	# SOP step 3a: una carta per ogni Enemy Team con almeno un Alerted.
	state.enemy_cards_in_play.clear()
	for team in state.enemy_teams_with_alerted():
		var serial := state.draw_enemy_card()
		state.enemy_cards_in_play[team] = serial
		state.log_event("Team %s pesca la Enemy Card %d (iniziativa %d)" % [
			team, serial, EnemyCards.initiative_of(serial)])
		# SOP step 3b: ordini a tutti gli Alerted del team, ciascuno
		# secondo il proprio morale e la propria copertura.
		for c in state.characters_of_team(team):
			if c.alerted and not c.is_dead():
				_assign_enemy_order(state, c, serial)
	# SOP step 3c: completare l'Initiative Order Track.
	_update_initiative_order(state)


# L'Initiative Track: ogni Team friendly prende il valore della Friendly
# Card giocata, ogni Team nemico attivo quello della sua Enemy Card.
# Si agisce dal valore piu' basso al piu' alto (friendly pari, enemy
# dispari: mai pareggi).
static func _update_initiative_order(state: GameState) -> void:
	var entries: Array = []  # coppie [iniziativa, team]
	if state.friendly_card_played >= 0:
		for team in state.friendly_teams():
			entries.append([FriendlyCards.initiative_for(state.friendly_card_played, team), team])
	for team in state.enemy_cards_in_play:
		entries.append([EnemyCards.initiative_of(state.enemy_cards_in_play[team]), team])
	entries.sort()
	state.initiative_order.clear()
	for e in entries:
		state.initiative_order.append(e[1])


static func _assign_enemy_order(state: GameState, c: Character, serial: int) -> void:
	# SR10: il PRIMO ordine (turno 1, e i rinforzi al turno 4) viene da un
	# 1D6 di scenario, non dal lookup morale x cover.
	if not c.had_first_order and not state.scenario_id.is_empty():
		var fo := Scenario.first_order(state.scenario_id, state.rng)
		if not fo.is_empty():
			c.set_order(fo["order"], fo["move"])
			c.had_first_order = true
			state.log_event("%s (ordine iniziale) -> %s %s" % [
				c.display_name, Domain.ORDER_NAMES[c.order], c.order_move])
			return
	c.had_first_order = true
	# SR12 (intro2): nemico in un edificio: se passa un TQC riceve
	# Aimed Fire e ignora la carta.
	if not state.scenario_id.is_empty() \
			and Scenario.SCENARIOS[state.scenario_id].get("building_tqc_aimed", false):
		var bhex := state.hex_at(c.position.x, c.position.y)
		if bhex != null and bhex.terrain == Domain.Terrain.BUILDING:
			if Checks.troop_quality_check(c, state.rng)["passed"]:
				c.set_order(Domain.Order.AIMED_FIRE)
				state.log_event("%s si apposta alla finestra -> Aimed Fire" % c.display_name)
				return
	if not EnemyCards.has_table_row(c.morale):
		# Berserk e Rout agiscono d'istinto (Rule 17), col movimento
		# stampato sulla carta: il Berserk carica il nemico piu' vicino,
		# il Rout fugge.
		if c.morale == Domain.Morale.BERSERK:
			c.set_order(Domain.Order.CHARGE, EnemyCards.berserk_move(serial), false, true)
			state.log_event("%s e' BERSERK -> Charge %s" % [
				c.display_name, c.order_move])
		else:  # ROUT
			c.set_order(Domain.Order.EVADE, EnemyCards.rout_move(serial))
			state.log_event("%s e' in ROUT -> fugge %s" % [
				c.display_name, c.order_move])
		return
	var hex := state.hex_at(c.position.x, c.position.y)
	# In Cover se il terreno protegge O se l'hex ha una siepe/muro sul bordo.
	var in_cover := (hex != null and Domain.terrain_gives_cover(hex.terrain)) \
		or state.hex_has_hexside(c.position)
	var entry := EnemyCards.lookup(serial, c.morale, in_cover)
	c.set_order(entry["order"], entry["move"], entry["grenade"], entry["charge"])
	var extra := "" if c.order_move.is_empty() else " " + c.order_move
	if entry["grenade"]:
		extra += " +Grenade"
	if entry["charge"]:
		extra += " +Charge"
	state.log_event("%s (%s, %s) -> %s%s" % [
		c.display_name, Domain.MORALE_NAMES[c.morale],
		"In Cover" if in_cover else "In Open",
		Domain.ORDER_NAMES[c.order], extra,
	])


# Step 4 - Action Phase: 4 impulsi (Rule 4.0 step 4)
static func action_phase(state: GameState) -> void:
	for imp in range(1, 5):
		run_impulse(state, imp)


# Un singolo impulse, tutto automatico (modalita' headless/demo).
static func run_impulse(state: GameState, imp: int) -> void:
	state.impulse = imp
	for c in impulse_order(state):
		activate(state, c)


# Ordine di attivazione dell'impulse: i Team in ordine di iniziativa.
# E' la coda che la UI interattiva percorre un personaggio alla volta.
static func impulse_order(state: GameState) -> Array[Character]:
	var list: Array[Character] = []
	for team in state.initiative_order:
		for c in state.characters_of_team(team):
			list.append(c)
	return list


# Attivazione completa automatica: parte passiva + azione.
static func activate(state: GameState, c: Character) -> void:
	if c.is_dead():
		return
	activate_passive(state, c)
	resolve_action(state, c)


# Parte NON discrezionale dell'attivazione: Rally (impulse 1) e Spotting.
# Vale per entrambi i lati; la UI la esegue sempre, anche per i Friendly.
static func activate_passive(state: GameState, c: Character) -> void:
	if c.is_dead():
		return
	if c.has_order and c.order == Domain.Order.RALLY and state.impulse == 1:
		var res := Checks.rally_check(c, state.rng)
		state.log_event("%s tenta Rally: tira %d (TQ %d) -> %s%s" % [
			c.display_name, res["roll"], Checks.effective_tq(c),
			Domain.MORALE_NAMES[res["after"]],
			"" if res["delta"] != 0 else " (nessun effetto)",
		])
	# Ordini "fermi" che agiscono a fine attivazione (impulse 4).
	if c.has_order and state.impulse == 4:
		match c.order:
			Domain.Order.RELOAD:
				if c.low_ammo or c.no_ammo:
					c.low_ammo = false
					c.no_ammo = false
					state.log_event("%s ha ricaricato" % c.display_name)
			Domain.Order.MEDICAL_AID:
				_do_medic(state, c)
			Domain.Order.SEARCH:
				_do_search(state, c)
			Domain.Order.PLAN:
				if c.side != Domain.Side.FRIENDLY:
					pass
				elif not state.scenario_id.is_empty() \
						and Scenario.SCENARIOS[state.scenario_id].get("c4", false):
					# Intro3 SR13: il Plan piazza una carica C4 nell'hex.
					Area.place_c4(state, c.position)
					state.log_event("%s piazza una carica C4 in %02d.%02d" % [
						c.display_name, c.position.x, c.position.y])
				else:
					# Plan (approssimato): genera una carta da parte (Rule 5/7).
					state.friendly_hand.append(state.draw_friendly_card())
					state.log_event("%s pianifica: una carta extra in mano" % c.display_name)
	# SOP 4a-ii: spotting a ogni attivazione (le posizioni cambiano col
	# movimento, quindi LOS e gittata vanno ricontrollate ogni impulse).
	_spotting_checks(state, c)


# Azione dell'impulse risolta automaticamente (nemici, e Friendly in
# modalita' demo). Per i Friendly interattivi la UI chiama invece
# Fire.fire_action / Move.step_to col bersaglio/percorso scelti.
static func resolve_action(state: GameState, c: Character) -> void:
	if c.is_dead() or not c.has_order:
		return
	# "Slow To Start": niente azione Friendly all'impulse 1.
	if state.impulse == 1 and c.side == Domain.Side.FRIENDLY \
			and state.turn_fx.get("no_impulse1", false):
		return
	match Orders.impulse_action(c.order, state.impulse):
		Domain.ImpulseAction.MAY_FIRE:
			if c.order in [Domain.Order.GRENADE, Domain.Order.SMOKE_GRENADE]:
				if not c.thrown:
					_try_throw(state, c)
			else:
				_try_fire(state, c)
		Domain.ImpulseAction.MAY_MOVE_1, Domain.ImpulseAction.MUST_MOVE_1:
			_do_move(state, c, 1)
		Domain.ImpulseAction.MUST_MOVE_2:
			_do_move(state, c, 2)
		Domain.ImpulseAction.MELEE:
			_do_melee(state, c)


# Lancio granata (gittata 3, Grenade Check = TQC; il marker esplode in
# End Phase). Automatico: sull'avversario visibile piu' vicino entro 3.
static func _try_throw(state: GameState, thrower: Character) -> void:
	var best: Character = null
	var best_d := 99
	for t in state.characters:
		if t.side == thrower.side or t.is_dead():
			continue
		if t.side == Domain.Side.ENEMY and not t.known:
			continue
		if t.side == Domain.Side.FRIENDLY and not t.spotted:
			continue
		var d := Spotting.hex_distance(thrower.position, t.position)
		if d <= 3 and d < best_d and LOS.clear(state, thrower, t):
			best_d = d
			best = t
	if best == null:
		return
	throw_grenade(state, thrower, best.position)


# Lancio verso un hex (anche per la UI). Grenade Check: TQC; se fallisce
# la granata scatta comunque ma con deviazione garantita.
static func throw_grenade(state: GameState, thrower: Character, hex: Vector2i) -> void:
	var smoke := thrower.order == Domain.Order.SMOKE_GRENADE
	var check := Checks.troop_quality_check(thrower, state.rng)
	state.log_event("%s lancia una granata%s verso %02d.%02d (TQC %s)" % [
		thrower.display_name, " fumogena" if smoke else "",
		hex.x, hex.y, "ok" if check["passed"] else "fallito"])
	var target := hex
	if not check["passed"]:
		# lancio sbagliato: devia di 1 hex prima ancora dello scatter
		var dir: Vector3i = Move.CUBE_DIRS[state.rng.randi_range(0, 5)]
		var dev := Move.from_cube(Move.to_cube(hex) + dir)
		if state.map.has(GameState.hex_key(dev.x, dev.y)):
			target = dev
	Area.place_with_scatter(state,
		Area.Type.SMOKE if smoke else Area.Type.GRENADE, target)
	thrower.thrown = true  # un lancio per turno; la track prosegue (move)


# Medical Aid: un TQC (skill MEDIC, Rule 18); se passa, stabilizza o
# cura un personaggio ferito adiacente (o se stesso).
static func _do_medic(state: GameState, medic: Character) -> void:
	for p in state.characters:
		if p.side != medic.side or p == medic or p.is_dead():
			continue
		if Spotting.hex_distance(medic.position, p.position) <= 1 and not p.wounds.is_empty():
			var res := Checks.troop_quality_check(medic, state.rng)
			if res["passed"]:
				p.wounds.remove_at(p.wounds.size() - 1)
				state.log_event("%s cura %s (TQC riuscito)" % [
					medic.display_name, p.display_name])
			else:
				state.log_event("%s: cura fallita su %s" % [
					medic.display_name, p.display_name])
			return


# Search: scopre nemici nascosti (ed esche) adiacenti.
static func _do_search(state: GameState, searcher: Character) -> void:
	for e in state.characters:
		if e.side == searcher.side or e.is_dead() or e.known:
			continue
		if Spotting.hex_distance(searcher.position, e.position) <= 1:
			e.known = true
			if e.is_dummy:
				e.removed = true
				state.log_event("%s scopre un'esca cercando" % searcher.display_name)
			else:
				state.log_event("%s scopre %s cercando" % [
					searcher.display_name, e.display_name])


# Mischia (fine Charge). APPROSSIMATA: il regolamento di dettaglio non e'
# trascritto; qui l'attaccante fa un TQC, in caso di successo ferisce
# l'avversario adiacente (rivelandolo se nascosto).
static func _do_melee(state: GameState, attacker: Character) -> void:
	var target: Character = null
	for d in state.characters:
		if d.side == attacker.side or d.is_dead():
			continue
		if Spotting.hex_distance(attacker.position, d.position) <= 1:
			target = d
			break
	if target == null:
		return
	target.known = true
	if target.is_dummy:
		target.removed = true
		state.log_event("%s travolge un'esca in mischia" % attacker.display_name)
		return
	var res := Checks.troop_quality_check(attacker, state.rng)
	state.log_event("%s attacca %s in mischia: TQC %s" % [
		attacker.display_name, target.display_name,
		"riuscito" if res["passed"] else "fallito"])
	if res["passed"]:
		Fire._resolve_wound(state, target)


# Ordini assegnabili a un Friendly, filtrati dalle limitazioni attive
# (carte Worried/Confusion/Can't Think Straight). Per il menu della UI.
static func legal_orders(state: GameState, c: Character) -> Array[int]:
	var restrict: String = state.turn_fx.get("restrict", "")
	var near_enemy := false
	for e in state.characters:
		if e.side != c.side and not e.is_dead() \
				and Spotting.hex_distance(c.position, e.position) <= 3:
			near_enemy = true
			break
	var allowed: Array[int] = []
	for o in Domain.Order.values():
		if restrict == "worried" and c.morale in [Domain.Morale.CAUTIOUS, Domain.Morale.SHAKEN] \
				and o != Domain.Order.HIDE:
			continue
		if restrict == "confusion" and not near_enemy \
				and o not in [Domain.Order.RALLY, Domain.Order.SNEAK, Domain.Order.HIDE]:
			continue
		if restrict == "no_leader_plan" and c.leadership > 0 and o == Domain.Order.PLAN:
			continue
		allowed.append(o)
	return allowed


# Azione discrezionale del personaggio in questo impulse: FIRE, MOVE_n
# o NOTHING. La UI la usa per decidere se mettere in pausa sui Friendly.
enum Act { NONE, FIRE, MOVE }


static func discretionary_action(c: Character, impulse: int, state: GameState = null) -> Dictionary:
	if not c.has_order:
		return {"kind": Act.NONE, "hexes": 0}
	# "Slow To Start": i Friendly non agiscono all'impulse 1.
	if impulse == 1 and c.side == Domain.Side.FRIENDLY and state != null \
			and state.turn_fx.get("no_impulse1", false):
		return {"kind": Act.NONE, "hexes": 0}
	match Orders.impulse_action(c.order, impulse):
		Domain.ImpulseAction.MAY_FIRE:
			return {"kind": Act.FIRE, "hexes": 0}
		Domain.ImpulseAction.MAY_MOVE_1, Domain.ImpulseAction.MUST_MOVE_1:
			return {"kind": Act.MOVE, "hexes": 1}
		Domain.ImpulseAction.MUST_MOVE_2:
			return {"kind": Act.MOVE, "hexes": 2}
		_:
			return {"kind": Act.NONE, "hexes": 0}


# Movimento nell'impulse: verso il nemico (Sneak/Sprint/Run&Gun/Charge)
# o lontano (Evade/Carry-Drag), del numero di hex consentito.
static func _do_move(state: GameState, c: Character, hexes: int) -> void:
	var from := c.position
	var n := Move.move_character(state, c, hexes)
	if n > 0:
		var verso := "verso" if Move.advances(c.order) else "via dal"
		state.log_event("%s si sposta %s nemico: %02d.%02d -> %02d.%02d" % [
			c.display_name, verso, from.x, from.y, c.position.x, c.position.y])


# Bersagli che il tiratore puo' ingaggiare ora (visti, in gittata, LOS).
static func valid_fire_targets(state: GameState, firer: Character) -> Array[Character]:
	var out: Array[Character] = []
	if firer.weapon_skills.is_empty():
		return out
	var weapon: String = firer.weapon_skills.keys()[0]
	for target in state.characters:
		if target.side == firer.side or target.is_dead():
			continue
		# si ingaggia solo cio' che si vede
		if target.side == Domain.Side.ENEMY and not target.known:
			continue
		if target.side == Domain.Side.FRIENDLY and not target.spotted:
			continue
		if Fire.can_fire(state, firer, target, weapon):
			out.append(target)
	return out


# Fuoco automatico (nemici / demo): bersaglio valido piu' vicino.
# Estensione G delle Enemy Card: se puo', lancia una granata al posto
# di sparare quando il bersaglio e' a portata di lancio (3 hex).
static func _try_fire(state: GameState, firer: Character) -> void:
	var targets := valid_fire_targets(state, firer)
	var best: Character = null
	var best_dist := 9999
	for target in targets:
		var dist := Spotting.hex_distance(firer.position, target.position)
		if dist < best_dist:
			best_dist = dist
			best = target
	if best == null:
		return
	if firer.order_grenade and not firer.thrown and best_dist <= 3:
		throw_grenade(state, firer, best.position)
		return
	Fire.fire_action(state, firer, best, firer.weapon_skills.keys()[0])


# Spotting check dello spotter contro ogni avversario non ancora
# individuato (una volta per turno, all'impulse 1; si raffina quando
# arrivera' il movimento). TODO: Line of Sight.
static func _spotting_checks(state: GameState, spotter: Character) -> void:
	for target in state.characters:
		if target.side == spotter.side or target.is_dead():
			continue
		if target.side == Domain.Side.ENEMY and target.known:
			continue
		if target.side == Domain.Side.FRIENDLY and target.spotted:
			continue
		var res := Spotting.attempt(state, spotter, target)
		if res["success"]:
			if target.side == Domain.Side.ENEMY:
				if target.is_dummy:
					_reveal_dummy(state, spotter, target)
				else:
					state.log_event("%s individua %s! (tira %d <= %d, dist %d)" % [
						spotter.display_name, target.display_name,
						res["roll"], res["threshold"], res["dist"]])
			else:
				state.log_event("%s e' stato avvistato da %s! (tira %d <= %d, dist %d)" % [
					target.display_name, spotter.display_name,
					res["roll"], res["threshold"], res["dist"]])


# Esca rivelata. In intro2 (SR13) si tira 1D10: 0 = documenti, 1-6 = un
# uomo disperso di Charlie Team che si unisce, 7-9 = niente.
static func _reveal_dummy(state: GameState, spotter: Character, dummy: Character) -> void:
	dummy.removed = true
	var sc: Dictionary = {} if state.scenario_id.is_empty() \
		else Scenario.SCENARIOS[state.scenario_id]
	if not sc.get("dummy_roll", false):
		state.log_event("%s scopre un'esca in %02d.%02d (rimossa)" % [
			spotter.display_name, dummy.position.x, dummy.position.y])
		return
	var roll := Checks.roll_d10(state.rng)
	if roll == 0:
		# Documenti: +5 VP se raccolti (TODO raccolta con Search; per ora log).
		state.log_event("%s trova dei DOCUMENTI in %02d.%02d!" % [
			spotter.display_name, dummy.position.x, dummy.position.y])
	elif roll <= 6:
		var names := ["Cpl Thomas", "Pvt Stubbs", "Pvt Templeman",
			"Pvt Butterman", "Pvt Walsh", "Pvt Kowalski"]
		var counters := ["US-Charlie-Pvt-Thomas", "US-Charlie-Pvt-Stubbs",
			"US-Charlie-Pvt-Temple", "US-Charlie-Pvt-Butterman",
			"US-Charlie-Pvt-Walsh", "US-Charlie-Pvt-Kowalski"]
		var lost := Character.new("lost_%d" % roll, names[roll - 1],
			Domain.Side.FRIENDLY, "Charlie")
		lost.troop_quality = 5
		lost.weapon_skills = {"M1 Garand": 5}
		lost.position = dummy.position
		lost.counter = counters[roll - 1]
		lost.role = "US Rifleman"
		state.characters.append(lost)
		state.log_event("Era %s di Charlie Team, disperso: si unisce alla squadra!" % lost.display_name)
	else:
		state.log_event("%s scopre un'esca in %02d.%02d (niente)" % [
			spotter.display_name, dummy.position.x, dummy.position.y])


# Step 5 - End Phase (Rule 4.0 step 5)
static func end_phase(state: GameState) -> void:
	# SOP 5: le granate/munizioni d'area esplodono, il fumo degrada.
	Area.end_phase(state)
	# Obiettivi di ricognizione raggiunti in questo turno.
	if not state.scenario_id.is_empty():
		Scenario.scan_objectives(state)
	# SOP step 5d: rimuovere tutti gli ordini.
	for c in state.characters:
		c.clear_order()
	state.enemy_cards_in_play.clear()
	state.turn_fx.clear()  # i modificatori della carta valgono un turno
	# La Friendly Card giocata va negli scarti.
	if state.friendly_card_played >= 0:
		state.friendly_discard.append(state.friendly_card_played)
		state.friendly_card_played = -1
	state.impulse = 1
	state.turn += 1
	# Fine partita: turni esauriti o un lato annientato.
	if state.turn > state.max_turns or Scenario.side_eliminated(state):
		state.game_over = true


# Un turno completo: i 5 step in sequenza.
static func run_turn(state: GameState) -> void:
	friendly_card_phase(state)
	friendly_order_phase(state)
	enemy_order_phase(state)
	action_phase(state)
	end_phase(state)
