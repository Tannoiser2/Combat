## I quattro check del gioco (Rule 19.0), trascritti dalle Check Tables.
## Dado: 1d10 con facce 0..9. Il confronto e' con la Troop Quality
## EFFETTIVA (TQ stampata + modificatori ferite). 0 e 9 naturali
## scavalcano il confronto.
##
## Ogni check applica subito l'effetto al personaggio e ritorna un
## Dictionary {roll, effect, delta} per il log; "delta" e' la variazione
## di livelli di morale applicata (positiva = morale alzato).
class_name Checks
extends RefCounted

const D := preload("res://engine/Domain.gd")


static func roll_d10(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(0, 9)


static func effective_tq(c: Character) -> int:
	return c.troop_quality + c.wound_tq_modifier()


# MC - Morale Check
static func morale_check(c: Character, rng: RandomNumberGenerator) -> Dictionary:
	var roll := roll_d10(rng)
	var delta := 0
	if roll == 0:
		delta = 1
	elif roll == 9:
		delta = -2
	elif roll > effective_tq(c):
		delta = -1
	return _apply(c, roll, delta, D.Morale.BERSERK)


# RC - Rally Check (gli aumenti non possono portare a Berserk)
static func rally_check(c: Character, rng: RandomNumberGenerator) -> Dictionary:
	var roll := roll_d10(rng)
	var delta := 0
	if roll == 0:
		delta = 2
	elif roll == 9:
		delta = -1
	elif roll <= effective_tq(c):
		delta = 1
	return _apply(c, roll, delta, D.Morale.AGGRESSIVE)


# TQC - Troop Quality Check (anche per Charge e Grenade Check).
# Non tocca il morale: ritorna {roll, passed}.
static func troop_quality_check(c: Character, rng: RandomNumberGenerator) -> Dictionary:
	var roll := roll_d10(rng)
	return {"roll": roll, "passed": roll <= effective_tq(c)}


# WMC - Wound Morale Check
static func wound_morale_check(c: Character, rng: RandomNumberGenerator) -> Dictionary:
	var roll := roll_d10(rng)
	var delta := 0
	if roll == 0:
		delta = 0
	elif roll == 9:
		delta = -3
	elif roll <= effective_tq(c):
		delta = -1
	else:
		delta = -2
	return _apply(c, roll, delta, D.Morale.BERSERK)


static func _apply(c: Character, roll: int, delta: int, cap: int) -> Dictionary:
	var before := c.morale
	if delta > 0:
		c.morale = D.raise_morale(c.morale, delta, cap)
	elif delta < 0:
		c.morale = D.lower_morale(c.morale, -delta)
	return {
		"roll": roll,
		"delta": delta,
		"before": before,
		"after": c.morale,
	}
