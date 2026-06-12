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


# Carte DISCARD che convengono appena l'occasione si presenta: False
# Alarm (toglie una Light Wound), Extra Mag (ricarica), Enough Is Enough
# (+2 morale al piu' scosso), Stop! (Rally automatico di un Rout vicino
# a un leader). Una sola occasione per carta, loggata.
static func _use_proactive_discards(state: GameState) -> void:
	for c in state.characters:
		if c.side != Domain.Side.FRIENDLY or c.is_dead():
			continue
		if Domain.Wound.LIGHT in c.wounds \
				and FriendlyCards.use_from_hand(state, FriendlyCards.FALSE_ALARM,
					"la ferita di %s era solo un graffio" % c.display_name):
			c.wounds.erase(Domain.Wound.LIGHT)
		if c.no_ammo \
				and FriendlyCards.use_from_hand(state, FriendlyCards.EXTRA_MAG,
					"%s ricarica al volo" % c.display_name):
			c.no_ammo = false
			c.low_ammo = false
	# Il morale peggiore della squadra, se Shaken o Rout.
	var worst: Character = null
	for c in state.characters:
		if c.side == Domain.Side.FRIENDLY and not c.is_dead() \
				and c.morale >= Domain.Morale.SHAKEN \
				and (worst == null or c.morale > worst.morale):
			worst = c
	if worst != null:
		if worst.morale == Domain.Morale.ROUT and _near_leader(state, worst) \
				and FriendlyCards.use_from_hand(state, FriendlyCards.STOP,
					"%s si ferma e si riprende" % worst.display_name):
			worst.morale = Domain.raise_morale(worst.morale, 1, Domain.Morale.NORMAL)
		elif FriendlyCards.use_from_hand(state, FriendlyCards.ENOUGH,
				"%s ritrova il coraggio (+2 morale)" % worst.display_name):
			worst.morale = Domain.raise_morale(worst.morale, 2, Domain.Morale.NORMAL)


# C'e' un leader friendly entro il suo raggio di comando (LDR)?
static func _near_leader(state: GameState, c: Character) -> bool:
	for l in state.characters:
		if l.side == Domain.Side.FRIENDLY and not l.is_dead() and l.leadership > 0 \
				and Spotting.hex_distance(l.position, c.position) <= l.leadership:
			return true
	return false


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
	# Carte DISCARD "proattive" dalla mano (uso automatico razionale).
	_use_proactive_discards(state)
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


# Assegna un ordine a un Enemy applicando le restrizioni del terreno
# (Rule 28.2: Sprint -> Evade su fango/neve; Sprint/Evade/Run&Gun -> Sneak su
# neve alta). La direzione (order_move) si conserva.
static func _set_enemy_order(state: GameState, c: Character, order: int,
		move: String = "", grenade: bool = false, charge: bool = false) -> void:
	var final_order := Weather.demote_order(state.ground, order)
	# Medico addestrato (Rule 30): mai fuoco/granate/carica/mischia -> cura.
	if c.is_medic and final_order in MEDIC_FORBIDDEN:
		final_order = Domain.Order.MEDICAL_AID
	c.set_order(final_order, move, grenade, charge)
	if final_order != order:
		state.log_event("  %s: %s impedito dal %s -> %s" % [c.display_name,
			Domain.ORDER_NAMES[order], Weather.GROUND_NAMES[state.ground],
			Domain.ORDER_NAMES[final_order]])


static func _assign_enemy_order(state: GameState, c: Character, serial: int) -> void:
	# SR10: il PRIMO ordine (turno 1, e i rinforzi al turno 4) viene da un
	# 1D6 di scenario, non dal lookup morale x cover.
	if not c.had_first_order and not state.scenario_id.is_empty():
		var fo := Scenario.first_order(state.scenario_id, state.rng)
		if not fo.is_empty():
			_set_enemy_order(state, c, fo["order"], fo["move"])
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
				_set_enemy_order(state, c, Domain.Order.AIMED_FIRE)
				state.log_event("%s si apposta alla finestra -> Aimed Fire" % c.display_name)
				return
	if not EnemyCards.has_table_row(c.morale):
		# Berserk e Rout agiscono d'istinto (Rule 17), col movimento
		# stampato sulla carta: il Berserk carica il nemico piu' vicino,
		# il Rout fugge.
		if c.morale == Domain.Morale.BERSERK:
			_set_enemy_order(state, c, Domain.Order.CHARGE, EnemyCards.berserk_move(serial), false, true)
			state.log_event("%s e' BERSERK -> Charge %s" % [
				c.display_name, c.order_move])
		else:  # ROUT
			_set_enemy_order(state, c, Domain.Order.EVADE, EnemyCards.rout_move(serial))
			state.log_event("%s e' in ROUT -> fugge %s" % [
				c.display_name, c.order_move])
		return
	var hex := state.hex_at(c.position.x, c.position.y)
	# In Cover se il terreno protegge O se l'hex ha una siepe/muro sul bordo.
	var in_cover := (hex != null and Domain.terrain_gives_cover(hex.terrain)) \
		or state.hex_has_hexside(c.position)
	var entry := EnemyCards.lookup(serial, c.morale, in_cover)
	_set_enemy_order(state, c, entry["order"], entry["move"], entry["grenade"], entry["charge"])
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
			elif c.order == Domain.Order.RIFLE_GRENADE:
				# Lanciagranate M7: gittata lunga ma non sotto i 5 hex.
				if not c.thrown:
					_try_throw(state, c, 12, 5)
			else:
				_try_fire(state, c)
		Domain.ImpulseAction.MAY_MOVE_1, Domain.ImpulseAction.MUST_MOVE_1:
			_do_move(state, c, 1)
		Domain.ImpulseAction.MUST_MOVE_2:
			_do_move(state, c, 2)
		Domain.ImpulseAction.MELEE:
			_do_melee(state, c)


# Lancio granata (gittata 3 a mano, 5-12 col lanciagranate M7; Grenade
# Check = TQC; il marker esplode in End Phase). Automatico:
# sull'avversario visibile piu' vicino nella fascia di gittata.
static func _try_throw(state: GameState, thrower: Character, max_r := 3, min_r := 1) -> void:
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
		if d >= min_r and d <= max_r and d < best_d and LOS.clear(state, thrower, t):
			best_d = d
			best = t
	if best == null:
		return
	throw_grenade(state, thrower, best.position)


# Fascia di gittata della granata per l'ordine corrente: [min, max].
static func throw_range(c: Character) -> Array[int]:
	if c.has_order and c.order == Domain.Order.RIFLE_GRENADE:
		return [5, 12]
	return [1, 3]


# Hex bersaglio validi per il lancio: in gittata e con LOS dall'hex del
# lanciatore (Rule 14). Per la UI: il giocatore clicca dove lanciare.
static func valid_throw_hexes(state: GameState, thrower: Character) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := throw_range(thrower)
	var origin := Move.to_cube(thrower.position)
	for dq in range(-r[1], r[1] + 1):
		for dr in range(-r[1], r[1] + 1):
			var cube := origin + Vector3i(dq, dr, -dq - dr)
			var hex := Move.from_cube(cube)
			if not state.map.has(GameState.hex_key(hex.x, hex.y)):
				continue
			var d := Spotting.hex_distance(thrower.position, hex)
			if d < r[0] or d > r[1]:
				continue
			if LOS.clear_hexes(state, thrower.position, hex):
				out.append(hex)
	return out


# Lancio verso un hex (anche per la UI). Grenade Check: TQC; se fallisce
# la granata scatta comunque ma con deviazione garantita.
static func throw_grenade(state: GameState, thrower: Character, hex: Vector2i) -> void:
	var smoke := thrower.order == Domain.Order.SMOKE_GRENADE
	state.audio_events.append({"type": "throw", "hex": thrower.position})
	Replay.sfx(state, "throw")
	var check := Checks.troop_quality_check(thrower, state.rng)
	state.log_event("%s lancia una granata%s verso %02d.%02d (TQC %s)" % [
		thrower.display_name, " fumogena" if smoke else "",
		hex.x, hex.y, "ok" if check["passed"] else "fallito"])
	# "Lucky Bounce": il giocatore ritira un Grenade Check fallito.
	if not check["passed"] and thrower.side == Domain.Side.FRIENDLY \
			and FriendlyCards.use_from_hand(state, FriendlyCards.LUCKY_BOUNCE,
				"%s ritira il lancio" % thrower.display_name):
		check = Checks.troop_quality_check(thrower, state.rng)
		state.log_event("· nuovo Grenade Check: %s" % ("ok" if check["passed"] else "fallito"))
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
			# Medico addestrato (Rule 30): +2 TQ al check di Medical Aid.
			var bonus := 2 if medic.is_medic else 0
			var roll := Checks.roll_d10(state.rng)
			var res := {"passed": roll <= Checks.effective_tq(medic) + bonus}
			# "Medical Marvel": la cura fallita riesce automaticamente.
			if not res["passed"] and medic.side == Domain.Side.FRIENDLY \
					and FriendlyCards.use_from_hand(state, FriendlyCards.MEDICAL,
						"la cura di %s riesce comunque" % medic.display_name):
				res["passed"] = true
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


# Ordini vietati a un medico addestrato (Rule 30): mai fuoco, granate,
# carica o mischia. Se assegnati, diventano Medical Aid (nemico) o sono
# nascosti dal menu (giocatore).
const MEDIC_FORBIDDEN := [
	Domain.Order.AIMED_FIRE, Domain.Order.RAPID_FIRE, Domain.Order.SUPPRESSIVE_FIRE,
	Domain.Order.GUARD, Domain.Order.CHARGE, Domain.Order.MELEE,
	Domain.Order.GRENADE, Domain.Order.RIFLE_GRENADE, Domain.Order.SMOKE_GRENADE,
]


# Il medico fugge di 1 hex in direzione 1D6 quando un avversario entra nel
# suo hex (Rule 30): non combatte mai.
static func _medic_flee(state: GameState, medic: Character) -> void:
	var dir: Vector3i = Move.CUBE_DIRS[state.rng.randi_range(0, 5)]
	var dest := Move.from_cube(Move.to_cube(medic.position) + dir)
	if Move.is_passable(state, dest):
		state.log_event("%s (medico) sfugge all'assalto: %02d.%02d -> %02d.%02d" % [
			medic.display_name, medic.position.x, medic.position.y, dest.x, dest.y])
		medic.position = dest
	else:
		state.log_event("%s (medico) non riesce a fuggire" % medic.display_name)


# Ordini "passivi" che in mischia lasciano scoperti (-2 al TQC difensivo).
const MELEE_PASSIVE := [
	Domain.Order.HIDE, Domain.Order.RALLY, Domain.Order.RELOAD,
	Domain.Order.MEDICAL_AID, Domain.Order.CARRY_DRAG, Domain.Order.PLAN,
]

# Modificatore al TQ in mischia (Rule 15/17): include il morale oltre alle ferite.
const MELEE_MORALE_TQ := {
	Domain.Morale.BERSERK: 3,
	Domain.Morale.AGGRESSIVE: 2,
	Domain.Morale.BOLD: 1,
	Domain.Morale.NORMAL: 0,
	Domain.Morale.CAUTIOUS: -1,
	Domain.Morale.SHAKEN: -2,
	Domain.Morale.ROUT: -99,
}


static func _melee_tq(c: Character) -> int:
	return Checks.effective_tq(c) + int(MELEE_MORALE_TQ.get(c.morale, 0))


# TQ d'attacco in mischia: base + morale (via _melee_tq) piu' i bonus
# deterministici, ossia Charge all'impulso 4 (Rule 7.08/10.08) e Knife Expert
# (Rule 24). Esclude la carta Bayonet, che si gioca in modo interattivo.
static func _melee_attack_tq(state: GameState, attacker: Character) -> int:
	var bonus := 0
	if attacker.has_order and attacker.order == Domain.Order.CHARGE \
			and state.impulse == 4:
		bonus += 1
	if attacker.has_skill(Character.SKILL_KNIFE_EXPERT):
		bonus += 1
	return _melee_tq(attacker) + bonus


# Mischia (Rule 15): solo l'attaccante tira un TQC (modificato da ferite e morale).
# Successo = pesca carta ferita (senza Duck Back). Fallimento = nessun effetto.
# La mischia avviene solo nello STESSO esagono. Charge all'impulso 4: +1 TQ.
static func _do_melee(state: GameState, attacker: Character) -> void:
	# Bersaglio nello stesso hex (non adiacente).
	var target: Character = null
	for d in state.characters:
		if d.side == attacker.side or d.is_dead():
			continue
		if d.position == attacker.position:
			target = d
			break
	if target == null:
		return
	target.known = true
	if target.is_dummy:
		target.removed = true
		state.log_event("%s travolge un'esca in mischia" % attacker.display_name)
		return
	# Medico addestrato (Rule 30): non entra mai in mischia; se un avversario
	# arriva nel suo hex, fugge di 1 hex in direzione 1D6.
	if target.is_medic:
		_medic_flee(state, target)
		return
	# Rout in mischia: l'attaccante in Rota si arrende (Rule 15/17.3).
	if attacker.morale == Domain.Morale.ROUT:
		state.log_event("%s e' in Rotta: si arrende (Guard)" % attacker.display_name)
		attacker.set_order(Domain.Order.GUARD)
		return
	# "Bayonet!": +2 TQ all'attaccante friendly (carta, uso interattivo).
	var atk_bonus := 0
	if attacker.side == Domain.Side.FRIENDLY \
			and FriendlyCards.use_from_hand(state, FriendlyCards.BAYONET,
				"%s carica alla baionetta (+2)" % attacker.display_name):
		atk_bonus = 2
	# TQ d'attacco: morale + Charge all'impulso 4 + Knife Expert (Rule 24).
	var atk_tq := _melee_attack_tq(state, attacker) + atk_bonus
	var roll := Checks.roll_d10(state.rng)
	var passed := roll == 0 or (roll != 9 and roll <= atk_tq)
	state.log_event("%s attacca %s in mischia: TQ %d, tira %d -> %s" % [
		attacker.display_name, target.display_name,
		atk_tq, roll, "COLPISCE" if passed else "manca"])
	if passed:
		state.audio_events.append({"type": "melee", "hex": attacker.position})
		Replay.sfx(state, "melee")
		Fire._resolve_wound_melee(state, attacker, target)
	else:
		state.log_event("  nessun effetto")


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
		# Condizione del terreno (Rule 28.2): ordini di movimento vietati.
		if Weather.order_forbidden(state.ground, o):
			continue
		# Medico addestrato (Rule 30): niente fuoco/granate/carica/mischia.
		if c.is_medic and o in MEDIC_FORBIDDEN:
			continue
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


# Azione discrezionale del personaggio in questo impulse: FIRE, MOVE_n,
# THROW (granate: il giocatore indica l'hex) o NOTHING. La UI la usa per
# decidere se mettere in pausa sui Friendly.
enum Act { NONE, FIRE, MOVE, THROW }

const GRENADE_ORDERS := [Domain.Order.GRENADE, Domain.Order.SMOKE_GRENADE,
	Domain.Order.RIFLE_GRENADE]


static func discretionary_action(c: Character, impulse: int, state: GameState = null) -> Dictionary:
	if not c.has_order:
		return {"kind": Act.NONE, "hexes": 0}
	# "Slow To Start": i Friendly non agiscono all'impulse 1.
	if impulse == 1 and c.side == Domain.Side.FRIENDLY and state != null \
			and state.turn_fx.get("no_impulse1", false):
		return {"kind": Act.NONE, "hexes": 0}
	match Orders.impulse_action(c.order, impulse):
		Domain.ImpulseAction.MAY_FIRE:
			if c.order in GRENADE_ORDERS:
				return {"kind": Act.NONE, "hexes": 0} if c.thrown \
					else {"kind": Act.THROW, "hexes": 0}
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
		var how := "verso il nemico" if Move.advances(c.order) else "via dal nemico"
		if c.side == Domain.Side.ENEMY and not Move.parse_dirs(c.order_move).is_empty() \
				and c.order != Domain.Order.CHARGE:
			how = "in direzione %s (bussola)" % c.order_move
		state.log_event("%s si sposta %s: %02d.%02d -> %02d.%02d" % [
			c.display_name, how, from.x, from.y, c.position.x, c.position.y])


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
	# Pioggia battente: puo' trasformare il terreno in fango (Rule 28.1).
	Weather.maybe_make_mud(state)
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
