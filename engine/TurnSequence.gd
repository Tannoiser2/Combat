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

# SOP 1a-1c: pesca fino al limite di mano, scarta l'eccesso.
static func friendly_card_phase_prepare(state: GameState) -> void:
	# SOP 1a: riporta la mano a hand_limit (5) pescando nuove carte.
	while state.friendly_hand.size() < state.hand_limit:
		state.friendly_hand.append(state.draw_friendly_card())
	# TODO SOP 1b: aggiungere le carte messe da parte da un Plan riuscito.
	# SOP 1c: se la mano supera il limite (es. da Plan), scarta le piu' vecchie.
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


# Step 3 - Enemy Card and Order Phase (Rule 9.0 / 9.2)
static func enemy_order_phase(state: GameState) -> void:
	# Carte DISCARD "proattive" dalla mano (uso automatico razionale).
	_use_proactive_discards(state)
	# Ondate di rinforzi del turno, prima di assegnare gli ordini.
	if not state.scenario_id.is_empty():
		Scenario.run_waves(state)
	# Filo spinato (Rule 27.7): in un hex con 2+ nemici, il TQ piu' basso passa
	# automaticamente in Hide prima di assegnare gli altri ordini.
	_wire_auto_hide(state)
	state.enemy_cards_in_play.clear()
	if state.large_battle:
		# Rule 9.2 Grande Battaglia: una carta per Gruppo; tutti i membri usano
		# la stessa carta (ordine determinato da morale e copertura individuali).
		for team in state.enemy_teams_with_alerted():
			var serial := state.draw_enemy_card()
			state.enemy_cards_in_play[team] = serial
			state.log_event("Team %s pesca Enemy Card %d (init %d) [Grande Battaglia]" % [
				team, serial, EnemyCards.initiative_of(serial)])
			for c in state.characters_of_team(team):
				if c.alerted and not c.is_dead() and not c.has_order and not c.is_prisoner:
					_assign_enemy_order(state, c, serial)
	else:
		# Rule 9 standard: una carta per ogni personaggio nemico Alerted.
		# Per l'Initiative Track si usa la carta con iniziativa minore del team.
		for team in state.enemy_teams_with_alerted():
			var team_serial := -1
			var team_init := 999
			for c in state.characters_of_team(team):
				if not c.alerted or c.is_dead() or c.has_order or c.is_prisoner:
					continue
				var serial := state.draw_enemy_card()
				state.log_event("  %s pesca Enemy Card %d (init %d)" % [
					c.display_name, serial, EnemyCards.initiative_of(serial)])
				_assign_enemy_order(state, c, serial)
				var iv := EnemyCards.initiative_of(serial)
				if iv < team_init:
					team_init = iv
					team_serial = serial
			if team_serial >= 0:
				state.enemy_cards_in_play[team] = team_serial
	# SOP step 3c: completare l'Initiative Order Track.
	_update_initiative_order(state)


# Ordini di movimento (diversi da Sneak) limitati dal filo spinato (Rule 27.7).
const WIRE_MOVEMENT := [Domain.Order.RUN_AND_GUN, Domain.Order.SPRINT,
	Domain.Order.EVADE, Domain.Order.CHARGE]


# Filo spinato (Rule 27.7): in ogni hex con filo spinato e 2+ nemici vivi, il
# personaggio col TQ piu' basso riceve un Hide automatico (il primo trovato a
# parita' di TQ).
static func _wire_auto_hide(state: GameState) -> void:
	var by_hex := {}
	for c in state.characters:
		if c.side != Domain.Side.ENEMY or c.is_dead() or not state.has_wire(c.position):
			continue
		var k := GameState.hex_key(c.position.x, c.position.y)
		if not by_hex.has(k):
			by_hex[k] = []
		by_hex[k].append(c)
	for k in by_hex:
		var group: Array = by_hex[k]
		if group.size() < 2:
			continue
		var lowest: Character = group[0]
		for c in group:
			if c.troop_quality < lowest.troop_quality:
				lowest = c
		lowest.set_order(Domain.Order.HIDE)
		lowest.had_first_order = true
		state.log_event("%s si appiattisce sul filo spinato (Hide automatico)" % lowest.display_name)


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
	# Filo spinato (Rule 27.7): gli ordini di movimento (non Sneak) -> Sneak.
	if final_order in WIRE_MOVEMENT and state.has_wire(c.position) \
			and not Move.wire_hide_exempt(state, c):
		final_order = Domain.Order.SNEAK
	c.set_order(final_order, move, grenade, charge)
	if final_order != order:
		state.log_event("  %s: %s impedito dal %s -> %s" % [c.display_name,
			Domain.ORDER_NAMES[order], Weather.GROUND_NAMES[state.ground],
			Domain.ORDER_NAMES[final_order]])


# Il ferito alleato piu' vicino entro `max_d` hex, o null (Rule 30.2).
static func _nearest_wounded_ally(state: GameState, medic: Character, max_d: int) -> Character:
	var best: Character = null
	var bd := 9999
	for p in state.characters:
		if p.side != medic.side or p == medic or p.is_dead() or p.wounds.is_empty():
			continue
		var d := Spotting.hex_distance(medic.position, p.position)
		if d <= max_d and d < bd:
			bd = d
			best = p
	return best


# Numero di bussola (1..6) che meglio punta da `from` verso `to`.
static func _compass_toward(state: GameState, from: Vector2i, to: Vector2i) -> int:
	if state.compass.size() != 7:
		return 1
	var delta := Move.to_cube(to) - Move.to_cube(from)
	var best_k := 1
	var best_dot := -9999
	for k in range(1, 7):
		var d: Vector3i = state.compass[k]
		var dot := d.x * delta.x + d.y * delta.y + d.z * delta.z
		if dot > best_dot:
			best_dot = dot
			best_k = k
	return best_k


# Micro-AI del medico nemico (Rule 30.2): cura il ferito adiacente, altrimenti
# si muove (Evade) verso il ferito alleato entro 4 hex, altrimenti Hide.
static func _assign_medic_order(state: GameState, c: Character) -> void:
	c.had_first_order = true
	var ally := _nearest_wounded_ally(state, c, 4)
	if ally == null:
		_set_enemy_order(state, c, Domain.Order.HIDE)
		state.log_event("%s (medico) non vede feriti: Hide" % c.display_name)
		return
	if Spotting.hex_distance(c.position, ally.position) <= 1:
		_set_enemy_order(state, c, Domain.Order.MEDICAL_AID)
		state.log_event("%s (medico) presta soccorso a %s" % [c.display_name, ally.display_name])
	else:
		_set_enemy_order(state, c, Domain.Order.EVADE, str(_compass_toward(state, c.position, ally.position)))
		state.log_event("%s (medico) raggiunge il ferito %s" % [c.display_name, ally.display_name])


# AI veicolo nemico (Rule 31): avanza verso il nemico piu' vicino e spara
# se entro gittata utile; altrimenti avanza (RUN_AND_GUN o SPRINT).
# Vero se un membro d'equipaggio vivo e imbarcato ha un ordine attivo.
static func _vehicle_crew_has_order(v: Character) -> bool:
	for cm in v.crew:
		if cm.embarked and not cm.is_dead() and cm.has_order:
			return true
	return false


# Il membro d'equipaggio vivo e imbarcato con un dato ruolo (o null).
static func _crew_member(v: Character, role: String) -> Character:
	if not v.is_vehicle:
		return null
	for cm in v.crew:
		if cm.crew_role == role and cm.embarked and not cm.is_dead():
			return cm
	return null


# Esegue l'azione del veicolo per-membro (Rule 31.9): lo scafo si muove con
# l'ordine del Driver (= ordine del veicolo) e, indipendentemente, il Gunner
# spara il cannone se ha un ordine di fuoco attivo a questo impulse. Cosi' il
# carro puo' muovere E sparare nello stesso impulse (move-and-shoot).
static func _resolve_vehicle_action(state: GameState, v: Character) -> void:
	# Movimento dello scafo (ordine del Driver = ordine del veicolo).
	var vehicle_fired := false
	match Orders.impulse_action(v.order, state.impulse):
		Domain.ImpulseAction.MAY_MOVE_1, Domain.ImpulseAction.MUST_MOVE_1:
			_do_move(state, v, 1)
		Domain.ImpulseAction.MUST_MOVE_2:
			_do_move(state, v, 2)
		Domain.ImpulseAction.MAY_FIRE:
			# Ordine di fuoco proprio del veicolo (Driver fermo): il Gunner spara.
			_gunner_fire(state, v)
			vehicle_fired = true
	# Il Gunner spara se ha un ordine di fuoco attivo, anche durante o dopo il
	# movimento dello scafo (move-and-shoot); niente doppio colpo se il veicolo
	# ha gia' sparato col proprio ordine.
	if not vehicle_fired:
		var gunner := _crew_member(v, "Gunner")
		if gunner != null and gunner.has_order \
				and Orders.impulse_action(gunner.order, state.impulse) \
					== Domain.ImpulseAction.MAY_FIRE:
			_gunner_fire(state, v)
	# Rule 31.9.4b: il Co-Driver serve la bow MG, arma e azione SEPARATE: spara
	# nello stesso impulse del cannone (col WS = TQ-3 gia' nei suoi weapon_skills).
	var bow := VehicleCombat.bow_mg_weapon(v)
	if not bow.is_empty():
		var codriver := _crew_member(v, "Co-Driver")
		if codriver != null and codriver.has_order \
				and Orders.impulse_action(codriver.order, state.impulse) \
					== Domain.ImpulseAction.MAY_FIRE:
			_fire_crew_weapon(state, v, codriver, bow)


# Il Gunner spara: la MG coassiale (Rule 31.9.4c, se fires_coax e il veicolo
# ce l'ha) oppure il cannone principale. La coassiale e' allineata dalla
# torretta (gate turretta come il cannone) e usa la TQ piena del Gunner.
static func _gunner_fire(state: GameState, v: Character) -> void:
	var gunner := _crew_member(v, "Gunner")
	var coax := VehicleCombat.coax_mg_weapon(v)
	if gunner != null and gunner.fires_coax and not coax.is_empty():
		_fire_crew_weapon(state, v, gunner, coax, true)
		return
	# Propaga l'ordine del Gunner al veicolo per il WS mod corretto: at_fire legge
	# firer.order, ma il veicolo ha l'ordine di movimento (SPRINT etc.), non quello
	# di fuoco. Con SUPPRESSIVE/RAPID_FIRE il Gunner avrebbe -2 WS, ma senza questa
	# propagazione non veniva applicato.
	var had_order := v.has_order
	var old_order: int = v.order if v.has_order else 0
	if gunner != null and gunner.has_order:
		v.has_order = true
		v.order = gunner.order
	# fire_mode AP/HE scelto dal Loader: rimuovi temporaneamente l'arma non
	# selezionata cosi' _try_fire usa solo quella scelta (poi la ripristiniamo).
	var removed_weapon := ""
	var removed_ws := 0
	if not v.fire_mode.is_empty():
		for w: String in v.weapon_skills.keys():
			if "AP" in w or "HE" in w:
				var wrong: bool = (v.fire_mode == "AP" and "HE" in w) \
					or (v.fire_mode == "HE" and "AP" in w)
				if wrong:
					removed_weapon = w
					removed_ws = int(v.weapon_skills[w])
					break
		if not removed_weapon.is_empty():
			v.weapon_skills.erase(removed_weapon)
	_try_fire(state, v)  # cannone (gate torretta + carica in Fire.fire_action)
	# Ripristina weapon_skills e ordine del veicolo.
	if not removed_weapon.is_empty():
		v.weapon_skills[removed_weapon] = removed_ws
	v.has_order = had_order
	if had_order:
		v.order = old_order


# Un membro d'equipaggio spara un'arma specifica dall'hex del veicolo (Rule
# 31.9): il firer e' il crew (col proprio WS), il colpo parte dallo scafo.
# Se require_turret, l'arma e' solidale alla torretta (coassiale): la torretta
# deve essere puntata sul bersaglio, altrimenti ruota e non spara.
static func _fire_crew_weapon(state: GameState, vehicle: Character,
		crew: Character, weapon: String, require_turret := false) -> void:
	crew.position = vehicle.position
	var best: Character = null
	var best_d := 9999
	for t in state.characters:
		if t.side == crew.side or t.is_dead():
			continue
		if t.side == Domain.Side.ENEMY and not t.known:
			continue
		if t.side == Domain.Side.FRIENDLY and not t.spotted:
			continue
		if not Fire.can_fire(state, crew, t, weapon):
			continue
		var d := Spotting.hex_distance(crew.position, t.position)
		if d < best_d:
			best_d = d
			best = t
	if best == null:
		return
	# Coassiale: serve la torretta puntata (la rotazione consuma l'impulse).
	if require_turret and VehicleCombat.has_turret(vehicle) \
			and not VehicleCombat.turret_aim(state, vehicle, best.position):
		return
	Fire.fire_action(state, crew, best, weapon)


# True se il Gunner ha un ordine di fuoco attivo a questo impulse (move-and-shoot).
static func vehicle_gunner_fires_impulse(v: Character, impulse: int) -> bool:
	var gunner := _crew_member(v, "Gunner")
	if gunner == null or not gunner.has_order:
		return false
	return Orders.impulse_action(gunner.order, impulse) == Domain.ImpulseAction.MAY_FIRE


# Come _gunner_fire ma spara su un bersaglio SCELTO dal giocatore (fire interattivo).
static func fire_vehicle_gunner_at(state: GameState, v: Character, target: Character) -> void:
	var gunner := _crew_member(v, "Gunner")
	var coax := VehicleCombat.coax_mg_weapon(v)
	if gunner != null and gunner.fires_coax and not coax.is_empty():
		var old_pos := gunner.position
		gunner.position = v.position
		if not (VehicleCombat.has_turret(v) and not VehicleCombat.turret_aim(state, v, target.position)):
			Fire.fire_action(state, gunner, target, coax)
		gunner.position = old_pos
		return
	var had_order := v.has_order
	var old_order: int = v.order if v.has_order else 0
	if gunner != null and gunner.has_order:
		v.has_order = true
		v.order = gunner.order
	var removed_weapon := ""
	var removed_ws := 0
	if not v.fire_mode.is_empty():
		for w: String in v.weapon_skills.keys():
			if "AP" in w or "HE" in w:
				var wrong: bool = (v.fire_mode == "AP" and "HE" in w) \
					or (v.fire_mode == "HE" and "AP" in w)
				if wrong:
					removed_weapon = w; removed_ws = int(v.weapon_skills[w]); break
		if not removed_weapon.is_empty():
			v.weapon_skills.erase(removed_weapon)
	var weapon: String = v.weapon_skills.keys()[0] if not v.weapon_skills.is_empty() else ""
	if not weapon.is_empty():
		Fire.fire_action(state, v, target, weapon)
	if not removed_weapon.is_empty():
		v.weapon_skills[removed_weapon] = removed_ws
	v.has_order = had_order
	if had_order:
		v.order = old_order


# Spara solo la bow MG del Co-Driver (usato dopo il fuoco interattivo del Gunner).
static func resolve_vehicle_bow_mg(state: GameState, v: Character) -> void:
	var bow := VehicleCombat.bow_mg_weapon(v)
	if bow.is_empty():
		return
	var codriver := _crew_member(v, "Co-Driver")
	if codriver != null and codriver.has_order \
			and Orders.impulse_action(codriver.order, state.impulse) \
				== Domain.ImpulseAction.MAY_FIRE:
		_fire_crew_weapon(state, v, codriver, bow)


# Rule 31.6 Emergency Stop: true se c'e' un nemico del veicolo con arma AT in LOS.
static func _vehicle_has_at_threat(state: GameState, vehicle: Character) -> bool:
	for c: Character in state.characters:
		if c.side == vehicle.side or c.is_dead():
			continue
		if not LOS.clear(state, vehicle, c):
			continue
		for w: String in c.weapon_skills:
			var flags: Array = Weapons.info(w).get("flags", [])
			if "at" in flags or "main_gun" in flags:
				return true
	return false


static func _assign_vehicle_order(state: GameState, c: Character) -> void:
	c.had_first_order = true
	var gunner := _crew_member(c, "Gunner")
	var codriver := _crew_member(c, "Co-Driver")
	var target := Move.nearest_enemy(state, c)
	if target == null:
		_set_enemy_order(state, c, Domain.Order.SNEAK)
		if gunner != null:
			gunner.clear_order()
		if codriver != null:
			codriver.clear_order()
		return
	var dist := Spotting.hex_distance(c.position, target.position)
	var los := LOS.clear(state, c, target)
	# Rule 31.9: il Gunner spara il cannone se c'e' LOS ed e' nel raggio
	# dell'arma principale; cosi' puo' sparare anche mentre lo scafo avanza.
	if gunner != null and los and dist <= 20:
		gunner.set_order(Domain.Order.AIMED_FIRE)
	elif gunner != null:
		gunner.clear_order()
	# Rule 31.9.4b: il Co-Driver serve la bow MG (gittata corta): spara se ha
	# LOS ed e' vicino. Arma e azione separate dal cannone.
	if codriver != null and not VehicleCombat.bow_mg_weapon(c).is_empty() \
			and los and dist <= 20:
		codriver.set_order(Domain.Order.AIMED_FIRE)
	elif codriver != null:
		codriver.clear_order()
	# Rule 31.6 Emergency Stop: se il carro si muoverebbe ma c'e' una minaccia
	# AT visibile, il Driver fa un TQC. Se passa, si ferma per questo turno.
	var would_move := not (los and dist <= 12)
	if would_move and not c.emergency_stop and _vehicle_has_at_threat(state, c):
		if Checks.troop_quality_check(c, state.rng)["passed"]:
			c.emergency_stop = true
			state.log_event("%s: Emergency Stop! (minaccia AT in LOS)" % c.display_name)
			_set_enemy_order(state, c, Domain.Order.AIMED_FIRE)
			return
	if los and dist <= 12:
		# Buona gittata: il carro si ferma e spara col cannone.
		_set_enemy_order(state, c, Domain.Order.AIMED_FIRE)
		state.log_event("%s (veicolo) -> Aimed Fire su %s (dist %d)" % [
			c.display_name, target.display_name, dist])
	elif los and dist <= 20:
		# In gittata ma lontano: avanza E spara (move-and-shoot).
		_set_enemy_order(state, c, Domain.Order.SPRINT)
		state.log_event("%s (veicolo) -> avanza e spara su %s (dist %d)" % [
			c.display_name, target.display_name, dist])
	elif dist <= 6:
		_set_enemy_order(state, c, Domain.Order.RUN_AND_GUN)
		state.log_event("%s (veicolo) -> Run&Gun verso %s" % [c.display_name, target.display_name])
	else:
		_set_enemy_order(state, c, Domain.Order.SPRINT)
		state.log_event("%s (veicolo) -> Sprint verso %s" % [c.display_name, target.display_name])


static func _assign_enemy_order(state: GameState, c: Character, serial: int) -> void:
	# Rule 31: veicolo nemico - AI semplificata.
	if c.is_vehicle:
		_assign_vehicle_order(state, c)
		return
	# Medico addestrato (Rule 30.2): logica dedicata, ignora il lookup morale.
	if c.is_medic:
		_assign_medic_order(state, c)
		return
	# Mischia obbligata (Rule 15): se c'e' un avversario vivo nello stesso hex,
	# l'unico ordine sensato e' MELEE (attacca agli impulsi 2 e 4).
	for rival in state.characters:
		if rival.side == c.side or rival.is_dead() or rival.is_vehicle:
			continue
		if rival.position == c.position:
			_set_enemy_order(state, c, Domain.Order.MELEE)
			state.log_event("%s (mischia obbligata con %s) -> Melee" % [
				c.display_name, rival.display_name])
			return
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
	if c.is_dead():
		return
	# "Slow To Start": niente azione Friendly all'impulse 1.
	if state.impulse == 1 and c.side == Domain.Side.FRIENDLY \
			and state.turn_fx.get("no_impulse1", false):
		return
	# Rule 31.9: i veicoli risolvono l'azione per-membro (Driver muove lo scafo,
	# Gunner spara il cannone, Co-Driver la bow MG): possono muovere E sparare
	# nello stesso impulse. Si processa se lo scafo O un membro ha un ordine.
	if c.is_vehicle:
		if c.has_order or _vehicle_crew_has_order(c):
			_resolve_vehicle_action(state, c)
		return
	if not c.has_order:
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
	state.throw_arcs.append({"from": thrower.position, "to": hex})
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
	# Granata esplosiva: ricorda il WS del lanciatore per il controllo Near/Far
	# alla deflagrazione (Rule 14.2). Il fumogeno non fa danno.
	if not smoke and not state.area_markers.is_empty():
		state.area_markers.back()["thrower_ws"] = Area.GRENADE_WS
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
	# Attaccante non individuato: +2 TQ (Rule 15).
	var is_hidden := not attacker.known if attacker.side == Domain.Side.ENEMY \
		else not attacker.spotted
	if is_hidden:
		bonus += 2
	return _melee_tq(attacker) + bonus


# Mischia (Rule 15): solo l'attaccante tira un TQC (modificato da ferite e morale).
# Successo = pesca carta ferita sul difensore + attaccante va in Duck Back.
# La mischia avviene solo nello STESSO esagono. Charge all'impulso 4: +1 TQ.
static func _do_melee(state: GameState, attacker: Character) -> void:
	# Bersaglio nello stesso hex (non adiacente).
	var target: Character = null
	var rivals_in_hex := 0
	for d in state.characters:
		if d.side == attacker.side or d.is_dead():
			continue
		if d.position == attacker.position:
			rivals_in_hex += 1
			if target == null:
				target = d
	if target == null:
		return
	# Segnalino mischia: flash rosso sull'hex (visibile in MapView).
	state.melee_events.append({"hex": attacker.position})
	if rivals_in_hex > 1:
		state.log_event("Mischia: %d avversari nell'hex — %s attacca %s" % [
			rivals_in_hex, attacker.display_name, target.display_name])
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
		if attacker.side == Domain.Side.ENEMY:
			attacker.is_prisoner = true
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
		attacker.set_order(Domain.Order.DUCK_BACK)
	else:
		state.log_event("  nessun effetto")


# Ordini assegnabili a un Friendly, filtrati dalle limitazioni attive
# (carte Worried/Confusion/Can't Think Straight). Per il menu della UI.
static func legal_orders(state: GameState, c: Character) -> Array[int]:
	# Rule 31: veicolo ammette solo un sottoinsieme di ordini.
	if c.is_vehicle:
		var vok: Array[int] = []
		for o in VehicleCombat.VEHICLE_ORDERS:
			if Weather.order_forbidden(state.ground, o):
				continue
			vok.append(o)
		return vok
	# Mischia obbligata (Rule 15): se c'e' un avversario vivo nello stesso hex,
	# l'unico ordine possibile e' MELEE.
	for rival in state.characters:
		if rival.side == c.side or rival.is_dead() or rival.is_vehicle:
			continue
		if rival.position == c.position:
			return [Domain.Order.MELEE]
	var restrict: String = state.turn_fx.get("restrict", "")
	var near_enemy := false
	for e in state.characters:
		if e.side != c.side and not e.is_dead() \
				and Spotting.hex_distance(c.position, e.position) <= 3:
			near_enemy = true
			break
	# Armi pesanti/lente (Rule 26): calcola i flag prima del loop sugli ordini.
	var _has_heavy := false
	var _has_very_heavy := false
	var _has_slow := false
	for _w in c.weapon_skills.keys():
		var _wf: Array = Weapons.info(_w)["flags"]
		if "very_heavy" in _wf:
			_has_very_heavy = true
		elif "heavy" in _wf:
			_has_heavy = true
		if "slow" in _wf:
			_has_slow = true
	var allowed: Array[int] = []
	for o in Domain.Order.values():
		# Condizione del terreno (Rule 28.2): ordini di movimento vietati.
		if Weather.order_forbidden(state.ground, o):
			continue
		# Ferite (Rule 13): Light Wound -> no Sprint; Bad Wound -> no Sprint/R&G/Evade.
		if not c.wounds.is_empty() and o == Domain.Order.SPRINT:
			continue
		if Domain.Wound.BAD in c.wounds \
				and o in [Domain.Order.RUN_AND_GUN, Domain.Order.EVADE]:
			continue
		# Armi pesanti (Rule 26): Heavy -> no Sprint; Very Heavy -> no Sprint/R&G;
		# Slow -> no Suppressive Fire.
		if (_has_heavy or _has_very_heavy) and o == Domain.Order.SPRINT:
			continue
		if _has_very_heavy and o == Domain.Order.RUN_AND_GUN:
			continue
		if _has_slow and o == Domain.Order.SUPPRESSIVE_FIRE:
			continue
		# Medico addestrato (Rule 30): niente fuoco/granate/carica/mischia.
		if c.is_medic and o in MEDIC_FORBIDDEN:
			continue
		# Filo spinato (Rule 27.7): per muoversi fuori si usa solo Sneak.
		if o in WIRE_MOVEMENT and state.has_wire(c.position) \
				and not Move.wire_hide_exempt(state, c):
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
		var sfx := "vehicle" if c.is_vehicle else \
			("run" if c.order in [Domain.Order.SPRINT, Domain.Order.RUN_AND_GUN,
				Domain.Order.CHARGE] else "footstep")
		Replay.sfx(state, sfx)
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
# Rule 30: il nemico evita di sparare al medico amico (TQC+2 per rispettare
# la convenzione; se passa salta al bersaglio successivo).
static func _try_fire(state: GameState, firer: Character) -> void:
	var targets := valid_fire_targets(state, firer)
	targets.sort_custom(func(a: Character, b: Character) -> bool:
		return Spotting.hex_distance(firer.position, a.position) \
			 < Spotting.hex_distance(firer.position, b.position))
	var best: Character = null
	var best_dist := 9999
	for target in targets:
		if firer.side == Domain.Side.ENEMY and target.is_medic:
			var roll := Checks.roll_d10(state.rng)
			var thr := Checks.effective_tq(firer) + 2
			if roll <= thr:
				state.log_event("%s rispetta la convenzione: evita il medico %s (tira %d <= %d)" % [
					firer.display_name, target.display_name, roll, thr])
				continue
		best = target
		best_dist = Spotting.hex_distance(firer.position, best.position)
		break
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
	# SOP step 5d: rimuovere tutti gli ordini (anche quelli per-membro dei
	# veicoli: i crew sono fuori da state.characters).
	for c in state.characters:
		c.clear_order()
		if c.is_vehicle:
			c.emergency_stop = false
			for cm in c.crew:
				cm.clear_order()
				cm.fires_coax = false
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
