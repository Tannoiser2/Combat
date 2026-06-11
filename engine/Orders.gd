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


# Azione dell'ordine in un dato impulse (1..4).
static func impulse_action(order: int, impulse: int) -> int:
	if not IMPULSES.has(order):
		return I.NOTHING
	return IMPULSES[order][impulse - 1]
