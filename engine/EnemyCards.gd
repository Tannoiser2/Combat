## Le 50 Enemy Card tedesche (Rule 9.0): il "cervello" tabellare dell'avversario.
##
## Ogni carta ha due tabelle (In Cover / In Open) indicizzate dallo stato di
## morale; ogni riga da' l'Order da assegnare piu' due estensioni stampate:
## - un valore di movimento accanto all'ordine (es. "5/6", "2"), trascritto
##   verbatim come stringa finche' non implementiamo il movimento;
## - le lettere G (lancia Grenade se possibile) e C (Charge se possibile).
## Berserk e Rout non consultano le tabelle: la carta riporta solo il loro
## valore di movimento, l'ordine e' implicito nello stato di morale.
## In basso ogni carta ha un valore di Initiative per l'Initiative Track.
##
## Dati trascritti dalle carte del gioco. Verifica di completezza: le 50
## iniziative sono esattamente i numeri dispari 1..99, una volta ciascuno.
class_name EnemyCards
extends RefCounted

const D := preload("res://engine/Domain.gd")

# Abbreviazioni per leggibilita' delle tabelle (rispecchiano il testo stampato).
const AF := D.Order.AIMED_FIRE        # Aimed Fire
const RF := D.Order.RAPID_FIRE        # Rapid Fire
const SF := D.Order.SUPPRESSIVE_FIRE  # Supp. Fire
const RG := D.Order.RUN_AND_GUN       # Run & Gun
const SN := D.Order.SNEAK             # Sneak
const EV := D.Order.EVADE             # Evade
const SP := D.Order.SPRINT            # Sprint
const RA := D.Order.RALLY             # Rally
const HI := D.Order.HIDE              # Hide

# Riga della tabella di morale a cui guarda ciascuno stato (Berserk e Rout
# sono fuori tabella: vedi rout_move/berserk_move).
const MORALE_ROW := {
	D.Morale.AGGRESSIVE: 0,
	D.Morale.BOLD: 1,
	D.Morale.NORMAL: 2,
	D.Morale.CAUTIOUS: 3,
	D.Morale.SHAKEN: 4,
}

# serial -> carta. Le righe di "cover"/"open" sono [Order, movimento, flag]
# nell'ordine Aggressive, Bold, Normal, Cautious, Shaken.
const CARDS := {
	1: {"initiative": 37, "rout": "2", "berserk": "6",
		"cover": [[RF, "", "G"], [RF, "", "G"], [RF, "", "G"], [RF, "", "G"], [RA, "", ""]],
		"open": [[SP, "5/6", "G"], [SN, "5/6", "C"], [SN, "5/6", "G"], [SN, "2/3", ""], [SN, "2/3", ""]]},
	2: {"initiative": 57, "rout": "2", "berserk": "6",
		"cover": [[EV, "6", "GC"], [EV, "6", "GC"], [EV, "6", "G"], [EV, "3", "G"], [EV, "2", ""]],
		"open": [[SP, "6/5", ""], [SN, "6/5", "C"], [SN, "6/5", "C"], [SN, "3/2", ""], [SN, "3/2", ""]]},
	3: {"initiative": 73, "rout": "2", "berserk": "6",
		"cover": [[EV, "5", "GC"], [EV, "5", "GC"], [EV, "5", "G"], [EV, "2", "G"], [EV, "3", ""]],
		"open": [[AF, "", ""], [AF, "", ""], [AF, "", ""], [AF, "", ""], [AF, "", ""]]},
	4: {"initiative": 19, "rout": "2", "berserk": "6",
		"cover": [[EV, "5/6", "GC"], [EV, "5/6", "GC"], [EV, "5/6", "G"], [EV, "2/3", "G"], [EV, "2/3", ""]],
		"open": [[RG, "6", "C"], [RG, "6", "C"], [RG, "6", "C"], [RG, "2", ""], [SP, "2/1", ""]]},
	5: {"initiative": 39, "rout": "2", "berserk": "6",
		"cover": [[EV, "6/5", "GC"], [EV, "6/5", "GC"], [EV, "6/5", "G"], [EV, "3/2", "G"], [EV, "2/3", ""]],
		"open": [[RG, "6", "C"], [RG, "6", "C"], [RG, "6", "C"], [RG, "3", ""], [SP, "3", ""]]},
	6: {"initiative": 45, "rout": "3", "berserk": "5",
		"cover": [[SF, "", "G"], [SF, "", "G"], [SF, "", "G"], [RF, "", "G"], [RF, "", ""]],
		"open": [[RG, "5", "C"], [RG, "1", "C"], [RG, "1", "C"], [RG, "1", ""], [SP, "1", ""]]},
	7: {"initiative": 55, "rout": "3", "berserk": "5",
		"cover": [[AF, "", "G"], [AF, "", "G"], [AF, "", "G"], [AF, "", ""], [AF, "", ""]],
		"open": [[RG, "6", "C"], [RG, "4", "C"], [RG, "4", "C"], [RG, "4", ""], [SP, "4", ""]]},
	8: {"initiative": 67, "rout": "3", "berserk": "5",
		"cover": [[SN, "5/6", "C"], [SN, "5/6", "C"], [AF, "", "G"], [AF, "", ""], [AF, "", "G"]],
		"open": [[RG, "5/6", "C"], [RG, "5/6", "C"], [RG, "5/6", "C"], [RG, "2/3", ""], [SP, "2/3", ""]]},
	9: {"initiative": 97, "rout": "3", "berserk": "5",
		"cover": [[SN, "6/5", "C"], [SN, "6/5", "C"], [AF, "", "G"], [AF, "", ""], [RA, "", ""]],
		"open": [[RG, "6/5", "C"], [RG, "6/5", "C"], [RG, "6/5", "C"], [RG, "3/2", ""], [SP, "3/2", ""]]},
	10: {"initiative": 3, "rout": "3", "berserk": "5",
		"cover": [[AF, "", "G"], [AF, "", "G"], [AF, "", "G"], [AF, "", ""], [RA, "", ""]],
		"open": [[EV, "6", "GC"], [EV, "6", "GC"], [EV, "6", "GC"], [EV, "2", ""], [EV, "2", "G"]]},
	11: {"initiative": 79, "rout": "2/3", "berserk": "6/5",
		"cover": [[RF, "", ""], [AF, "", ""], [AF, "", ""], [AF, "", ""], [EV, "2", ""]],
		"open": [[EV, "5", "GC"], [EV, "5", "GC"], [EV, "5", "GC"], [EV, "3", ""], [EV, "3", "G"]]},
	12: {"initiative": 47, "rout": "2/3", "berserk": "6/5",
		"cover": [[RG, "6", "C"], [RG, "6", ""], [AF, "", "G"], [AF, "", "G"], [RA, "", ""]],
		"open": [[EV, "5/6", "GC"], [EV, "5/6", "GC"], [EV, "5/6", "GC"], [EV, "2/3", ""], [EV, "2/3", ""]]},
	13: {"initiative": 31, "rout": "2/3", "berserk": "6/5",
		"cover": [[RG, "6", "C"], [RG, "6", ""], [AF, "", "G"], [SF, "", ""], [RA, "", ""]],
		"open": [[EV, "6/5", "GC"], [EV, "6/5", "GC"], [EV, "6/5", "GC"], [EV, "3/2", ""], [EV, "3/2", ""]]},
	14: {"initiative": 17, "rout": "2/3", "berserk": "6/5",
		"cover": [[RG, "5", "C"], [RG, "5", ""], [AF, "", "G"], [SF, "", ""], [SF, "", "G"]],
		"open": [[SP, "6", ""], [SP, "6", ""], [SP, "6", ""], [SP, "3", ""], [SP, "3", ""]]},
	15: {"initiative": 89, "rout": "2/3", "berserk": "6/5",
		"cover": [[RG, "6", "C"], [RG, "6", ""], [AF, "", "G"], [AF, "", "G"], [RA, "", ""]],
		"open": [[SP, "5", "C"], [SP, "5", "C"], [SP, "5", "C"], [SP, "2", ""], [SP, "2", ""]]},
	16: {"initiative": 77, "rout": "3/2", "berserk": "5/6",
		"cover": [[RG, "5/6", "C"], [RG, "5/6", ""], [RG, "1", ""], [RG, "1", ""], [RG, "1", ""]],
		"open": [[SN, "5/6", "C"], [SN, "5/6", "C"], [SN, "5/6", "C"], [SN, "2/3", ""], [SN, "2/3", ""]]},
	17: {"initiative": 65, "rout": "3/2", "berserk": "5/6",
		"cover": [[RG, "6/5", "C"], [RG, "6/5", ""], [RG, "4", ""], [RG, "4", ""], [RG, "4", ""]],
		"open": [[SN, "6/5", "C"], [SN, "6/5", "C"], [SN, "6/5", "C"], [SN, "3/2", ""], [SN, "3/2", ""]]},
	18: {"initiative": 15, "rout": "3/2", "berserk": "5/6",
		"cover": [[RF, "", "C"], [SF, "", ""], [SF, "", ""], [SF, "", ""], [SF, "", ""]],
		"open": [[RG, "5/6", "C"], [RG, "5/6", "C"], [RG, "5/6", "C"], [RG, "1/2", ""], [SP, "1/2", ""]]},
	19: {"initiative": 9, "rout": "3/2", "berserk": "5/6",
		"cover": [[RG, "6", "C"], [RG, "6", ""], [RG, "6", ""], [RG, "1/2", ""], [RG, "1/2", ""]],
		"open": [[RG, "4/5", "C"], [RG, "4/5", "C"], [RG, "4/5", "C"], [RG, "4/3", ""], [SP, "4/5", ""]]},
	20: {"initiative": 93, "rout": "3/2", "berserk": "5/6",
		"cover": [[RG, "4/5", "C"], [RG, "4/5", ""], [RG, "4/5", ""], [RG, "4/3", ""], [RG, "4/3", ""]],
		"open": [[SN, "1/6", "C"], [SN, "1/6", "C"], [SN, "1/6", "C"], [SN, "1/2", ""], [SN, "1/2", ""]]},
	21: {"initiative": 71, "rout": "2", "berserk": "6",
		"cover": [[SP, "5/6", "G"], [AF, "", "G"], [AF, "", "G"], [AF, "", "G"], [AF, "", "G"]],
		"open": [[SN, "4/5", "C"], [SN, "4/5", "C"], [SN, "4/5", "C"], [SN, "4/3", ""], [SN, "4/3", ""]]},
	22: {"initiative": 61, "rout": "2", "berserk": "6",
		"cover": [[SP, "6/5", "G"], [AF, "", "G"], [AF, "", "G"], [AF, "", ""], [AF, "", ""]],
		"open": [[EV, "1/6", "GC"], [EV, "1/6", "GC"], [EV, "1/6", "GC"], [EV, "1/2", "G"], [EV, "1/2", ""]]},
	23: {"initiative": 43, "rout": "2", "berserk": "6",
		"cover": [[SP, "6", ""], [AF, "", "G"], [AF, "", "G"], [AF, "", ""], [AF, "", "G"]],
		"open": [[EV, "4/5", "GC"], [EV, "4/5", "GC"], [EV, "4/5", "GC"], [EV, "4/3", "G"], [EV, "4/3", ""]]},
	24: {"initiative": 53, "rout": "2", "berserk": "6",
		"cover": [[SP, "5", ""], [AF, "", "G"], [AF, "", "G"], [RA, "", ""], [RA, "", ""]],
		"open": [[RF, "", ""], [RF, "", ""], [SF, "", ""], [SF, "", ""], [SF, "", ""]]},
	25: {"initiative": 7, "rout": "2", "berserk": "6",
		"cover": [[RF, "", ""], [RF, "", "G"], [SF, "", ""], [RA, "", ""], [RA, "", ""]],
		"open": [[RF, "", ""], [RF, "", ""], [RF, "", ""], [SF, "", ""], [SF, "", ""]]},
	26: {"initiative": 69, "rout": "3", "berserk": "5",
		"cover": [[AF, "", ""], [RF, "", "G"], [SF, "", ""], [RA, "", ""], [RA, "", ""]],
		"open": [[RG, "6/1", "C"], [RG, "6/1", "C"], [RG, "6/1", "C"], [RG, "2/1", ""], [SP, "2/1", ""]]},
	27: {"initiative": 75, "rout": "3", "berserk": "5",
		"cover": [[RF, "", ""], [RF, "", "G"], [SF, "", ""], [RA, "", ""], [RA, "", ""]],
		"open": [[RG, "5/4", "C"], [RG, "5/4", "C"], [RG, "5/4", "C"], [RG, "3/4", ""], [SP, "3/4", ""]]},
	28: {"initiative": 81, "rout": "3", "berserk": "5",
		"cover": [[AF, "", ""], [RF, "", "G"], [RF, "", ""], [RA, "", ""], [RA, "", ""]],
		"open": [[SP, "6", ""], [RF, "", ""], [RF, "", ""], [SF, "", ""], [SF, "", ""]]},
	29: {"initiative": 59, "rout": "3", "berserk": "5",
		"cover": [[RF, "", ""], [AF, "", "G"], [AF, "", ""], [RA, "", ""], [RA, "", ""]],
		"open": [[SP, "5", ""], [RF, "", ""], [SF, "", ""], [SF, "", ""], [SF, "", ""]]},
	30: {"initiative": 35, "rout": "3", "berserk": "5",
		"cover": [[RF, "", ""], [AF, "", "G"], [AF, "", ""], [RA, "", ""], [RA, "", ""]],
		"open": [[RF, "", ""], [RF, "", ""], [SF, "", ""], [SF, "", ""], [SF, "", ""]]},
	31: {"initiative": 1, "rout": "2/3", "berserk": "6/5",
		"cover": [[HI, "", ""], [HI, "", ""], [HI, "", ""], [HI, "", ""], [HI, "", ""]],
		"open": [[AF, "", ""], [RG, "5/6", ""], [EV, "1", ""], [EV, "1", ""], [HI, "", ""]]},
	32: {"initiative": 5, "rout": "2/3", "berserk": "6/5",
		"cover": [[AF, "", "G"], [HI, "", ""], [HI, "", ""], [HI, "", ""], [HI, "", ""]],
		"open": [[AF, "", "G"], [RG, "6/5", ""], [EV, "4", ""], [EV, "4", ""], [HI, "", ""]]},
	33: {"initiative": 11, "rout": "2/3", "berserk": "6/5",
		"cover": [[AF, "", "G"], [HI, "", ""], [HI, "", ""], [HI, "", ""], [HI, "", ""]],
		"open": [[AF, "", "G"], [RG, "5/6", ""], [SN, "1", ""], [AF, "", ""], [HI, "", ""]]},
	34: {"initiative": 13, "rout": "2/3", "berserk": "6/5",
		"cover": [[AF, "", "G"], [RF, "", ""], [HI, "", ""], [HI, "", ""], [HI, "", ""]],
		"open": [[AF, "", "G"], [RG, "6/5", ""], [SN, "4", ""], [AF, "", ""], [HI, "", ""]]},
	35: {"initiative": 21, "rout": "2/3", "berserk": "6/5",
		"cover": [[AF, "", "G"], [RF, "", "GC"], [HI, "", ""], [HI, "", ""], [HI, "", ""]],
		"open": [[SF, "", "G"], [EV, "5/6", ""], [RG, "5/6", ""], [AF, "", ""], [SN, "2/3", ""]]},
	36: {"initiative": 23, "rout": "3/2", "berserk": "5/6",
		"cover": [[RF, "", "G"], [SF, "", "G"], [HI, "", ""], [HI, "", ""], [HI, "", ""]],
		"open": [[RF, "", ""], [EV, "6/5", ""], [RG, "6/5", ""], [RF, "", ""], [SN, "3/2", ""]]},
	37: {"initiative": 25, "rout": "3/2", "berserk": "5/6",
		"cover": [[RF, "", "G"], [RF, "", "GC"], [HI, "", ""], [HI, "", ""], [HI, "", ""]],
		"open": [[RF, "", "G"], [EV, "5/6", ""], [SN, "5/6", ""], [EV, "2", ""], [SN, "1/2", ""]]},
	38: {"initiative": 27, "rout": "3/2", "berserk": "5/6",
		"cover": [[RF, "", "G"], [RF, "", ""], [RF, "", ""], [HI, "", ""], [HI, "", ""]],
		"open": [[SF, "", ""], [EV, "6/5", ""], [SN, "6/5", ""], [EV, "3", ""], [SN, "2/1", ""]]},
	39: {"initiative": 29, "rout": "3/2", "berserk": "5/6",
		"cover": [[RF, "", ""], [RF, "", "GC"], [SF, "", ""], [HI, "", ""], [HI, "", ""]],
		"open": [[SF, "", ""], [EV, "1/6", ""], [SN, "5/6", ""], [EV, "2/3", ""], [RA, "", ""]]},
	40: {"initiative": 33, "rout": "3/2", "berserk": "5/6",
		"cover": [[RF, "", ""], [RF, "", ""], [SF, "", ""], [HI, "", ""], [HI, "", ""]],
		"open": [[RF, "", ""], [EV, "4/5", ""], [SN, "6/5", ""], [EV, "3/2", ""], [RA, "", ""]]},
	41: {"initiative": 41, "rout": "2", "berserk": "6",
		"cover": [[RF, "", ""], [AF, "", "GC"], [HI, "", "G"], [HI, "", ""], [HI, "", ""]],
		"open": [[SP, "5/6", "GC"], [AF, "", ""], [SP, "5", "GC"], [EV, "2", ""], [RA, "", ""]]},
	42: {"initiative": 49, "rout": "2", "berserk": "6",
		"cover": [[RF, "", ""], [AF, "", ""], [AF, "", "G"], [HI, "", ""], [HI, "", ""]],
		"open": [[SP, "6/5", "GC"], [AF, "", "C"], [SP, "6", "GC"], [EV, "3", ""], [EV, "2", ""]]},
	43: {"initiative": 51, "rout": "2", "berserk": "6",
		"cover": [[RF, "", ""], [AF, "", ""], [AF, "", "G"], [HI, "", ""], [HI, "", ""]],
		"open": [[RG, "5/6", "C"], [AF, "", "C"], [AF, "", ""], [EV, "2/3", ""], [EV, "3", ""]]},
	44: {"initiative": 63, "rout": "3", "berserk": "5",
		"cover": [[RF, "", ""], [AF, "", ""], [AF, "", ""], [RA, "", ""], [HI, "", ""]],
		"open": [[RG, "6/5", "C"], [AF, "", "C"], [AF, "", ""], [EV, "3/2", ""], [SN, "3", ""]]},
	45: {"initiative": 83, "rout": "3", "berserk": "5",
		"cover": [[RG, "5/6", "C"], [EV, "5/6", ""], [SN, "5/6", ""], [RA, "", ""], [HI, "", ""]],
		"open": [[RG, "5/6", ""], [AF, "", ""], [AF, "", ""], [RA, "", ""], [SN, "2", ""]]},
	46: {"initiative": 85, "rout": "3", "berserk": "5",
		"cover": [[RG, "6/5", "C"], [EV, "6/5", ""], [SN, "6/5", ""], [RA, "", ""], [RA, "", ""]],
		"open": [[RG, "4/5", "C"], [RF, "", "G"], [AF, "", ""], [RA, "", ""], [EV, "1", ""]]},
	47: {"initiative": 87, "rout": "2/3", "berserk": "6/5",
		"cover": [[RG, "5/6", "C"], [RG, "5/6", "GC"], [SN, "1/6", ""], [SN, "2/3", ""], [RA, "", ""]],
		"open": [[RG, "6/1", "C"], [RF, "", ""], [AF, "", ""], [HI, "", ""], [EV, "4", ""]]},
	48: {"initiative": 91, "rout": "3/2", "berserk": "5/6",
		"cover": [[RG, "4/5", "C"], [RG, "6/5", "GC"], [SN, "4/5", ""], [SN, "3/2", ""], [RF, "", ""]],
		"open": [[RG, "5/4", "C"], [RF, "", ""], [AF, "", ""], [HI, "", ""], [EV, "2/3", ""]]},
	49: {"initiative": 95, "rout": "3/2", "berserk": "5/6",
		"cover": [[RG, "6/1", "C"], [RG, "5/6", ""], [SN, "5", ""], [SN, "1/2", ""], [RF, "", ""]],
		"open": [[RF, "", ""], [SN, "5", ""], [SN, "5", ""], [HI, "", ""], [EV, "3/2", ""]]},
	50: {"initiative": 99, "rout": "3/2", "berserk": "5/6",
		"cover": [[RG, "5/4", "C"], [RG, "6/5", ""], [SN, "6", ""], [SN, "2/1", ""], [AF, "", ""]],
		"open": [[SF, "", ""], [SN, "6", ""], [SN, "6", ""], [HI, "", ""], [HI, "", ""]]},
}


# Lo stato di morale ha una riga nelle tabelle della carta?
# (Berserk e Rout non ce l'hanno: agiscono d'istinto.)
static func has_table_row(morale: int) -> bool:
	return MORALE_ROW.has(morale)


# IL lookup: data carta, morale e copertura, l'ordine del nemico.
# Ritorna {order: Domain.Order, move: String, grenade: bool, charge: bool}.
static func lookup(serial: int, morale: int, in_cover: bool) -> Dictionary:
	assert(CARDS.has(serial), "Carta nemica inesistente: %d" % serial)
	assert(MORALE_ROW.has(morale), "Berserk/Rout non usano le tabelle della carta")
	var card: Dictionary = CARDS[serial]
	var table: Array = card["cover"] if in_cover else card["open"]
	var row: Array = table[MORALE_ROW[morale]]
	return {
		"order": row[0],
		"move": row[1],
		"grenade": "G" in row[2],
		"charge": "C" in row[2],
	}


# Valore di Initiative della carta (per l'Initiative Track).
static func initiative_of(serial: int) -> int:
	assert(CARDS.has(serial), "Carta nemica inesistente: %d" % serial)
	return CARDS[serial]["initiative"]


# Movimento stampato per i personaggi in Rout / Berserk.
static func rout_move(serial: int) -> String:
	return CARDS[serial]["rout"]


static func berserk_move(serial: int) -> String:
	return CARDS[serial]["berserk"]


# Tutti i seriali, ordinati: e' il mazzo completo da mescolare.
static func all_serials() -> Array[int]:
	var result: Array[int] = []
	for s in CARDS.keys():
		result.append(s)
	result.sort()
	return result
