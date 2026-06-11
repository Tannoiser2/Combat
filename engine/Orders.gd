## Cosa fa ogni Order nei 4 impulsi (Rule 6.0/10.0), trascritto dagli
## impulse track stampati sui segnalini ordine:
## cifra BLU = puo' muovere, NERA = deve muovere, ROSSA = puo' sparare,
## 0 = nessuna azione, M = melee.
## Gli ordini "fermi" (Hide, Rally, Plan, Reload, Medical Aid, Search,
## Guard) hanno track 0000: agiscono fuori dagli impulsi.
class_name Orders
extends RefCounted

const D := preload("res://engine/Domain.gd")

const I := D.ImpulseAction

# Order -> [azione impulse 1, 2, 3, 4]
const IMPULSES := {
	D.Order.AIMED_FIRE: [I.NOTHING, I.MAY_FIRE, I.NOTHING, I.MAY_FIRE],
	D.Order.RAPID_FIRE: [I.MAY_FIRE, I.MAY_FIRE, I.MAY_FIRE, I.MAY_FIRE],
	D.Order.SUPPRESSIVE_FIRE: [I.MAY_FIRE, I.MAY_FIRE, I.MAY_FIRE, I.MAY_FIRE],
	D.Order.RUN_AND_GUN: [I.MUST_MOVE_1, I.MAY_FIRE, I.MUST_MOVE_1, I.MAY_FIRE],
	D.Order.SNEAK: [I.NOTHING, I.MAY_MOVE_1, I.NOTHING, I.MUST_MOVE_1],
	D.Order.EVADE: [I.MUST_MOVE_1, I.MUST_MOVE_1, I.MUST_MOVE_1, I.MUST_MOVE_1],
	D.Order.SPRINT: [I.MUST_MOVE_1, I.MUST_MOVE_2, I.MUST_MOVE_2, I.MUST_MOVE_2],
	D.Order.CHARGE: [I.MUST_MOVE_1, I.MUST_MOVE_1, I.MUST_MOVE_2, I.MELEE],
	D.Order.MELEE: [I.NOTHING, I.MELEE, I.NOTHING, I.MELEE],
	D.Order.GRENADE: [I.NOTHING, I.MAY_MOVE_1, I.MAY_FIRE, I.MAY_MOVE_1],
	D.Order.SMOKE_GRENADE: [I.NOTHING, I.MAY_MOVE_1, I.MAY_FIRE, I.MAY_MOVE_1],
	D.Order.RIFLE_GRENADE: [I.NOTHING, I.NOTHING, I.MAY_FIRE, I.NOTHING],
	D.Order.CARRY_DRAG: [I.NOTHING, I.MUST_MOVE_1, I.NOTHING, I.MUST_MOVE_1],
	D.Order.RELOAD: [I.NOTHING, I.NOTHING, I.NOTHING, I.NOTHING],
	D.Order.MEDICAL_AID: [I.NOTHING, I.NOTHING, I.NOTHING, I.NOTHING],
	D.Order.SEARCH: [I.NOTHING, I.NOTHING, I.NOTHING, I.NOTHING],
	D.Order.PLAN: [I.NOTHING, I.NOTHING, I.NOTHING, I.NOTHING],
	D.Order.HIDE: [I.NOTHING, I.NOTHING, I.NOTHING, I.NOTHING],
	D.Order.RALLY: [I.NOTHING, I.NOTHING, I.NOTHING, I.NOTHING],
	D.Order.GUARD: [I.NOTHING, I.NOTHING, I.NOTHING, I.NOTHING],
	D.Order.DUCK_BACK: [I.NOTHING, I.NOTHING, I.NOTHING, I.NOTHING],
}

# Modificatore al WS dell'attaccante stampato sul segnalino (-2 per
# Run & Gun / Rapid Fire / Suppressive, +1 Charge): vedi Fire Resolution.
const FIRE_WS_MOD := {
	D.Order.RAPID_FIRE: -2,
	D.Order.SUPPRESSIVE_FIRE: -2,
	D.Order.RUN_AND_GUN: -2,
	D.Order.CHARGE: 1,
}


# Descrizioni per la UI: cosa fa l'ordine, in breve.
const DESC := {
	D.Order.AIMED_FIRE: "Fuoco mirato: spara agli impulsi 2 e 4 con la migliore precisione. L'ordine difensivo standard.",
	D.Order.RAPID_FIRE: "Fuoco rapido: puo' sparare a OGNI impulso, ma a -2 sul WS. Volume di fuoco contro precisione.",
	D.Order.SUPPRESSIVE_FIRE: "Fuoco di soppressione (-2 WS): non ferisce, ma costringe il bersaglio a un Morale Check. Ottimo per inchiodare.",
	D.Order.RUN_AND_GUN: "Avanza e spara alternando: movimento obbligato (1 hex) agli impulsi 1 e 3, fuoco a -2 agli impulsi 2 e 4.",
	D.Order.SNEAK: "Avanza furtivo: difficile da avvistare, movimento lento (impulsi 2 e 4). Il modo discreto di avvicinarsi.",
	D.Order.EVADE: "Si muove zigzagando via dal nemico, 1 hex a ogni impulso. Difficile da colpire, ma non spara.",
	D.Order.SPRINT: "Corsa a perdifiato verso il nemico: 1-2-2-2 hex per impulso. Veloce ma molto esposto.",
	D.Order.CHARGE: "Carica all'arma bianca (+1 WS): avanza 1-1-2 e ingaggia in mischia all'impulso 4.",
	D.Order.MELEE: "Combattimento corpo a corpo con un avversario adiacente (impulsi 2 e 4).",
	D.Order.GRENADE: "Lancia una granata (entro 3 hex, Grenade Check): esplode a fine turno. Puo' muovere prima e dopo il lancio.",
	D.Order.SMOKE_GRENADE: "Lancia un fumogeno (entro 3 hex): il fumo blocca la vista e penalizza il fuoco (-4, poi -2), per 2 turni.",
	D.Order.RIFLE_GRENADE: "Granata da fucile: lancio piu' lungo, spara all'impulso 3.",
	D.Order.PLAN: "Pianifica: a fine turno genera una carta extra (o piazza una carica C4 negli scenari di demolizione).",
	D.Order.RELOAD: "Ricarica l'arma: a fine turno rimuove Low/No Ammo. Non agisce negli impulsi.",
	D.Order.MEDICAL_AID: "Cura un commilitone ferito adiacente (TQC a fine turno): rimuove una ferita.",
	D.Order.SEARCH: "Perquisisce/cerca: rivela nemici nascosti (ed esche) negli hex adiacenti a fine turno.",
	D.Order.HIDE: "Si nasconde: difficilissimo da avvistare e da colpire. Nessuna azione.",
	D.Order.RALLY: "Si ricompone: Rally Check all'impulso 1 per recuperare morale (mai fino a Berserk).",
	D.Order.CARRY_DRAG: "Trasporta o trascina (un ferito, un'arma): movimento obbligato agli impulsi 2 e 4.",
	D.Order.DUCK_BACK: "Si butta a terra/al riparo: stato difensivo dopo un colpo subito. Nessuna azione.",
	D.Order.GUARD: "Vigila un prigioniero o una posizione: puo' reagire ma non agisce negli impulsi.",
}


# La track degli impulsi in formato leggibile, es. "1:- 2:spara 3:- 4:spara".
static func track_text(order: int) -> String:
	if not IMPULSES.has(order):
		return ""
	var names := {
		I.NOTHING: "-", I.MAY_MOVE_1: "muove 1", I.MUST_MOVE_1: "MUOVE 1",
		I.MAY_FIRE: "spara", I.MUST_MOVE_2: "MUOVE 2", I.MELEE: "mischia",
	}
	var parts: Array[String] = []
	for i in range(4):
		parts.append("%d:%s" % [i + 1, names[IMPULSES[order][i]]])
	return "  ".join(parts)


# La track come righe estese, una per impulse: "1 - muove 1 esagono".
static func track_lines(order: int) -> Array[String]:
	var out: Array[String] = []
	if not IMPULSES.has(order):
		return out
	var names := {
		I.NOTHING: "nessuna azione",
		I.MAY_MOVE_1: "puo' muovere 1 esagono",
		I.MUST_MOVE_1: "DEVE muovere 1 esagono",
		I.MAY_FIRE: "puo' sparare",
		I.MUST_MOVE_2: "DEVE muovere 2 esagoni",
		I.MELEE: "mischia",
	}
	for i in range(4):
		out.append("%d - %s" % [i + 1, names[IMPULSES[order][i]]])
	return out


# Azione dell'ordine in un dato impulse (1..4).
static func impulse_action(order: int, impulse: int) -> int:
	if not IMPULSES.has(order):
		return I.NOTHING
	return IMPULSES[order][impulse - 1]
