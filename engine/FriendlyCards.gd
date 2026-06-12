## Le 52 Friendly Card americane (Rule 5.0): il mazzo del giocatore.
##
## Ogni carta (1..50) ha:
## - un valore di Initiative per ciascun Team (Able/Baker/Charlie), da
##   giocare sull'Initiative Track. Tutti i valori sono PARI (le Enemy
##   Card hanno valori dispari: mai pareggi sul track);
## - un effetto speciale con etichetta ORDER (vale nel turno in cui la
##   carta e' giocata) o DISCARD (si scarta dalla mano per attivarlo);
##   titolo e testo trascritti verbatim, la logica arrivera' a strati;
## - un timbro ferita in basso: e' la pesca per la gravita' delle ferite
##   (Close Call / Light Wound / Bad Wound / K.I.A.) con annotazione.
## Le carte 51 e 52 sono gli Event (FLASH): niente iniziativa, si tira
## sulla Event Table, si pesca un rimpiazzo e si rimescola tutto.
class_name FriendlyCards
extends RefCounted

enum Kind { ORDER, DISCARD, EVENT }
enum WoundDraw { CLOSE_CALL, LIGHT_WOUND, BAD_WOUND, KIA }

# Abbreviazioni per le tabelle
const OR := Kind.ORDER
const DI := Kind.DISCARD
const CC := WoundDraw.CLOSE_CALL
const LW := WoundDraw.LIGHT_WOUND
const BW := WoundDraw.BAD_WOUND
const KIA := WoundDraw.KIA

# serial -> carta. "a"/"b"/"c" = iniziativa di Able/Baker/Charlie.
# "wound" e' il timbro in basso, "note" l'annotazione a margine.
const CARDS := {
	1: {"a": 2, "b": 18, "c": 86, "kind": DI, "title": "Keep Your Head Down",
		"text": "Enemy hit automatically becomes a Duck Back.", "wound": CC, "note": "MC"},
	2: {"a": 68, "b": 66, "c": 72, "kind": OR, "title": "Get It Together",
		"text": "+2 TQ for any Rally rolls within LDR distance of Leader.", "wound": CC, "note": "MC"},
	3: {"a": 6, "b": 34, "c": 44, "kind": OR, "title": "Make Each Shot Count",
		"text": "+1 Weapon Skill for Aimed Shots within LDR distance of Leader.", "wound": CC, "note": "MC"},
	4: {"a": 42, "b": 52, "c": 30, "kind": DI, "title": "Lucky Bounce",
		"text": "Re-roll a single Grenade Attack Roll.", "wound": CC, "note": "MC"},
	5: {"a": 12, "b": 10, "c": 22, "kind": OR, "title": "They're Up to Something",
		"text": "Enemy Event.", "wound": CC, "note": "MC"},
	6: {"a": 4, "b": 24, "c": 60, "kind": OR, "title": "Bad Shooting",
		"text": "-1 to all WS this turn.", "wound": CC, "note": "MC"},
	7: {"a": 96, "b": 88, "c": 8, "kind": DI, "title": "Enough Is Enough",
		"text": "1 Friendly Character may increase morale by 2 levels.", "wound": CC, "note": "MC"},
	8: {"a": 22, "b": 4, "c": 36, "kind": DI, "title": "False Alarm",
		"text": "Remove 1 Light Wound marker from a Friendly Character.", "wound": CC, "note": "MC"},
	9: {"a": 50, "b": 60, "c": 64, "kind": DI, "title": "Quick Thinking",
		"text": "1 Team may swap their Initiative Counter with the one to the left on the Initiative Track.", "wound": CC, "note": "MC"},
	10: {"a": 46, "b": 86, "c": 20, "kind": OR, "title": "Should've Brought More Ammo",
		"text": "Go straight from Full Ammo to NO Ammo this turn.", "wound": CC, "note": "MC"},
	11: {"a": 92, "b": 66, "c": 42, "kind": DI, "title": "What's He Doing?",
		"text": "Choose 1 Friendly Character. They may act immediately - either take 1 aimed shot or move 1 hex.", "wound": KIA, "note": "Notify NOK"},
	12: {"a": 50, "b": 52, "c": 58, "kind": OR, "title": "Smoke",
		"text": "Smoke rolls across the battlefield - Friendly and Enemy shooting is at -1.", "wound": KIA, "note": "Notify NOK"},
	13: {"a": 52, "b": 40, "c": 48, "kind": OR, "title": "Slow To Start",
		"text": "No Friendly troops may act on Impulse 1.", "wound": KIA, "note": "Notify NOK"},
	14: {"a": 72, "b": 4, "c": 46, "kind": DI, "title": "Initiative",
		"text": "1 Character may immediately change his order.", "wound": KIA, "note": "Notify NOK"},
	15: {"a": 98, "b": 16, "c": 48, "kind": DI, "title": "Extra Mag",
		"text": "Play to reload any 1 Friendly Character immediately.", "wound": KIA, "note": "Notify NOK"},
	16: {"a": 26, "b": 54, "c": 8, "kind": OR, "title": "Event",
		"text": "Roll on the Friendly Event Table.", "wound": KIA, "note": "Notify NOK"},
	17: {"a": 78, "b": 14, "c": 28, "kind": OR, "title": "Weave!",
		"text": "-1 to hit any Friendly Character with Sprint, Evade, or Run & Gun order.", "wound": LW, "note": "Amb."},
	18: {"a": 98, "b": 86, "c": 92, "kind": DI, "title": "Initiative",
		"text": "1 Character may immediately change his order.", "wound": LW, "note": "Amb."},
	19: {"a": 26, "b": 66, "c": 18, "kind": OR, "title": "Good Shooting",
		"text": "+1 to all Friendly shooting this turn.", "wound": LW, "note": "Amb."},
	20: {"a": 4, "b": 38, "c": 26, "kind": OR, "title": "Confusion",
		"text": "Friendly Characters may only be given Rally, Sneak or Hide orders this turn unless within 3 hexes of an Enemy.", "wound": LW, "note": "Amb."},
	21: {"a": 34, "b": 56, "c": 28, "kind": DI, "title": "Crack Shot",
		"text": "Play after a successful hit on an Enemy Character. That Character is automatically killed.", "wound": LW, "note": "Amb."},
	22: {"a": 82, "b": 76, "c": 52, "kind": OR, "title": "Worried",
		"text": "All Friendly Characters who are Cautious or Shaken may only be given Hide orders.", "wound": LW, "note": "Amb."},
	23: {"a": 36, "b": 30, "c": 28, "kind": DI, "title": "Smart Idea",
		"text": "Add +2 to a single Friendly Leader's Command for a Plan Order - play when resolving the Plan Order.", "wound": LW, "note": "Amb."},
	24: {"a": 98, "b": 80, "c": 92, "kind": OR, "title": "Leadership",
		"text": "All Friendly Leaders have their Command Radius doubled this turn.", "wound": LW, "note": "Amb."},
	25: {"a": 46, "b": 56, "c": 40, "kind": OR, "title": "Trip",
		"text": '1 Random Friendly Character from "A" Team may only be given a Hide Order this turn.', "wound": LW, "note": "Amb."},
	26: {"a": 6, "b": 88, "c": 78, "kind": OR, "title": "Event",
		"text": "Roll on the Friendly Event Table.", "wound": LW, "note": "Amb."},
	27: {"a": 50, "b": 42, "c": 62, "kind": OR, "title": "Pour It On",
		"text": 'All Friendly Characters in "A" Team have +1 WS this turn.', "wound": LW, "note": "Amb."},
	28: {"a": 22, "b": 68, "c": 30, "kind": DI, "title": "Good Shot",
		"text": "Play to re-roll any 1 WS roll.", "wound": LW, "note": "Amb."},
	29: {"a": 42, "b": 14, "c": 10, "kind": DI, "title": "Bayonet!",
		"text": "Play for +2 WS in Melee for 1 Attack.", "wound": LW, "note": "Amb."},
	30: {"a": 12, "b": 30, "c": 14, "kind": DI, "title": "Blind Shooting",
		"text": "All Friendly fire from cover is -2 this turn, but Enemies are -2 to hit them.", "wound": LW, "note": "Amb."},
	31: {"a": 84, "b": 70, "c": 42, "kind": OR, "title": "Can't Think Straight",
		"text": "No Leaders may be given the Plan Order this turn.", "wound": LW, "note": "Amb."},
	32: {"a": 98, "b": 50, "c": 92, "kind": OR, "title": "Trip",
		"text": '1 Random Friendly Character from "B" Team may only be given a Hide Order this turn.', "wound": LW, "note": "Amb."},
	33: {"a": 10, "b": 76, "c": 44, "kind": OR, "title": "Pour It On",
		"text": 'All Friendly Characters in "B" Team have +1 WS this turn.', "wound": BW, "note": "Evac."},
	34: {"a": 42, "b": 46, "c": 24, "kind": OR, "title": "Poor Shooting",
		"text": 'All Friendly Characters from "A" Team are -1 WS this turn.', "wound": BW, "note": "Evac."},
	35: {"a": 80, "b": 52, "c": 4, "kind": OR, "title": "Poor Shooting",
		"text": 'All Friendly Characters from "B" Team are -1 WS this turn.', "wound": BW, "note": "Evac."},
	36: {"a": 54, "b": 96, "c": 34, "kind": OR, "title": "Nothing Happens",
		"text": "", "wound": BW, "note": "Evac."},
	37: {"a": 58, "b": 22, "c": 32, "kind": OR, "title": "Trip",
		"text": '1 Random Friendly Character from "C" Team may only be given a Hide Order this turn.', "wound": BW, "note": "Evac."},
	38: {"a": 86, "b": 64, "c": 50, "kind": OR, "title": "Pour It On",
		"text": 'All Friendly Characters in "C" Team have +1 WS this turn.', "wound": BW, "note": "Evac."},
	39: {"a": 40, "b": 34, "c": 4, "kind": OR, "title": "Poor Shooting",
		"text": 'All Friendly Characters from "C" Team are -1 WS this turn.', "wound": BW, "note": "Evac."},
	40: {"a": 96, "b": 16, "c": 2, "kind": DI, "title": "Lucky",
		"text": "Play to re-roll any 1 Die roll.", "wound": BW, "note": "Evac."},
	41: {"a": 20, "b": 84, "c": 88, "kind": OR, "title": "Panic Is Spreading",
		"text": "Any Character that is in or adjacent to a hex with a Friendly Character with lower morale drops their moral to match.", "wound": BW, "note": "Evac."},
	42: {"a": 12, "b": 18, "c": 6, "kind": DI, "title": "Medical Marvel",
		"text": "Play to auto-pass a Medical Roll.", "wound": BW, "note": "Evac."},
	43: {"a": 98, "b": 16, "c": 94, "kind": OR, "title": "Trip",
		"text": '1 Random Friendly Character from "C" Team may only be given a Hide Order this turn.', "wound": CC, "note": "MC"},
	44: {"a": 16, "b": 80, "c": 58, "kind": OR, "title": "Go Boys!",
		"text": "Any Friendly Character that is moving on Impulse 4 may move 1 additional hex for free.", "wound": CC, "note": "MC"},
	45: {"a": 32, "b": 30, "c": 16, "kind": OR, "title": "Smoke",
		"text": "Smoke rolls across the battlefield - Friendly and Enemy shooting is at -1.", "wound": CC, "note": "MC"},
	46: {"a": 44, "b": 70, "c": 36, "kind": OR, "title": "They're Up to Something",
		"text": "Enemy Event.", "wound": BW, "note": "Evac."},
	47: {"a": 82, "b": 26, "c": 16, "kind": DI, "title": "Smart Idea",
		"text": "Add +2 to a single Friendly Leader's Command for a Plan Order - Play when resolving the Plan Order.", "wound": BW, "note": "Evac."},
	48: {"a": 90, "b": 92, "c": 68, "kind": OR, "title": "Can't Think Straight",
		"text": "No Leaders may be given the Plan Order this turn.", "wound": BW, "note": "Evac."},
	49: {"a": 78, "b": 14, "c": 86, "kind": OR, "title": "Worried",
		"text": "All Friendly Characters who are Cautious or Shaken may only be given Hide orders.", "wound": BW, "note": "Evac."},
	50: {"a": 32, "b": 22, "c": 36, "kind": DI, "title": "Stop!",
		"text": "Auto Rally 1 Friendly Character within LDR distance of any Leader.", "wound": BW, "note": "Evac."},
	51: {"a": -1, "b": -1, "c": -1, "kind": Kind.EVENT, "title": "Friendly Event!",
		"text": "Roll on the Friendly Event Table, draw another card to replace this one, then shuffle the Friendly Card Deck and the Discard Pile.", "wound": -1, "note": ""},
	52: {"a": -1, "b": -1, "c": -1, "kind": Kind.EVENT, "title": "Enemy Event!",
		"text": "Roll on the Enemy Event Table, draw another card to replace this one, then shuffle the Friendly Card Deck and the Discard Pile.", "wound": -1, "note": ""},
}

# Nome della chiave iniziativa per ciascun Team friendly.
const TEAM_KEYS := {"Able": "a", "Baker": "b", "Charlie": "c"}


static func kind_of(serial: int) -> int:
	assert(CARDS.has(serial), "Carta friendly inesistente: %d" % serial)
	return CARDS[serial]["kind"]


static func title_of(serial: int) -> String:
	return CARDS[serial]["title"]


static func text_of(serial: int) -> String:
	return CARDS[serial]["text"]


# Iniziativa della carta per un dato Team ("Able"/"Baker"/"Charlie").
static func initiative_for(serial: int, team: String) -> int:
	assert(CARDS.has(serial), "Carta friendly inesistente: %d" % serial)
	assert(TEAM_KEYS.has(team), "Team friendly sconosciuto: %s" % team)
	return CARDS[serial][TEAM_KEYS[team]]


# Timbro ferita della carta (per la pesca delle ferite, Rule 16).
static func wound_of(serial: int) -> int:
	return CARDS[serial]["wound"]


# Effetti meccanici applicati quando la carta e' giocata (sottoinsieme
# automatizzato: modificatori di fuoco, limitazioni d'ordine, eventi).
# Le carte non elencate restano informative (testo nel log).
const FX := {
	6: {"ws_all": -1},                       # Bad Shooting
	19: {"ws_all": 1},                       # Good Shooting
	27: {"ws_team": {"Able": 1}},            # Pour It On (A)
	33: {"ws_team": {"Baker": 1}},           # Pour It On (B)
	38: {"ws_team": {"Charlie": 1}},         # Pour It On (C)
	34: {"ws_team": {"Able": -1}},           # Poor Shooting (A)
	35: {"ws_team": {"Baker": -1}},          # Poor Shooting (B)
	39: {"ws_team": {"Charlie": -1}},        # Poor Shooting (C)
	30: {"ws_cover_self": -2},               # Blind Shooting
	13: {"no_impulse1": true},               # Slow To Start
	36: {"nothing": true},                   # Nothing Happens
	22: {"restrict": "worried"},             # Worried
	49: {"restrict": "worried"},
	20: {"restrict": "confusion"},           # Confusion
	31: {"restrict": "no_leader_plan"},      # Can't Think Straight
	48: {"restrict": "no_leader_plan"},
	5: {"event": "enemy"},                   # They're Up to Something
	46: {"event": "enemy"},
	16: {"event": "friendly"},               # Event
	26: {"event": "friendly"},
}


# Applica l'effetto della carta giocata ai modificatori di turno.
static func apply(state, serial: int) -> void:
	if not FX.has(serial):
		return
	for k in FX[serial]:
		state.turn_fx[k] = FX[serial][k]


# --- Carte DISCARD (si scartano dalla mano per l'effetto) ---------------
# Il motore le usa con una politica automatica razionale: quando l'evento
# di innesco si verifica, se la carta giusta e' in mano viene scartata e
# l'effetto applicato (loggato). Gruppi per innesco:
const KEEP_HEAD_DOWN := [1]    # colpo nemico subito -> solo Duck Back
const LUCKY_BOUNCE := [4]      # ritira un Grenade Check fallito
const ENOUGH := [7]            # +2 morale a un personaggio
const FALSE_ALARM := [8]       # rimuove una Light Wound
const EXTRA_MAG := [15]        # ricarica immediata
const CRACK_SHOT := [21]       # colpo su nemico -> ucciso automaticamente
const REROLL_WS := [28, 40]    # Good Shot / Lucky: ritira un tiro di WS
const BAYONET := [29]          # +2 in mischia
const MEDICAL := [42]          # Medical Roll riuscito automaticamente
const STOP := [50]             # Rally automatico vicino a un leader


# Se una delle carte e' in mano, la scarta e logga l'uso. Ritorna true.
static func use_from_hand(state, serials: Array, reason: String) -> bool:
	for s in serials:
		var idx: int = state.friendly_hand.find(s)
		if idx >= 0:
			state.friendly_hand.remove_at(idx)
			state.friendly_discard.append(s)
			state.log_event('Dalla mano: "%s" - %s' % [title_of(s), reason])
			return true
	return false


# Percorso dell'immagine della carta (grafica originale), o "" se assente.
static func image(serial: int) -> String:
	var path := "res://assets/cards/US-%02d.jpg" % serial
	return path if ResourceLoader.exists(path) else ""


static func back_image() -> String:
	return "res://assets/cards/US-back.jpg"


# Tutti i seriali, ordinati: il mazzo completo da mescolare.
static func all_serials() -> Array[int]:
	var result: Array[int] = []
	for s in CARDS.keys():
		result.append(s)
	result.sort()
	return result
