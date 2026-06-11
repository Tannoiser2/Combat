## Definizioni del dominio di gioco di Combat!
##
## In Godot usiamo enum e costanti per dare nomi controllati ai concetti
## del regolamento (morale, ordini, terreno...). E' l'equivalente idiomatico
## dei tipi rigidi: invece di numeri sparsi nel codice, usiamo nomi parlanti.
##
## Questo e' un Autoload (singleton): accessibile ovunque come Domain.XXX
extends Node

# --- I sette stati di morale, dal piu' alto al piu' basso (Rule 17.0) ---
# L'ordine dei valori enum E' il livello: Berserk=0 (alto), Rout=6 (basso).
enum Morale {
	BERSERK,
	AGGRESSIVE,
	BOLD,
	NORMAL,
	CAUTIOUS,
	SHAKEN,
	ROUT,
}

# Nomi leggibili per debug/UI
const MORALE_NAMES := {
	Morale.BERSERK: "Berserk",
	Morale.AGGRESSIVE: "Aggressive",
	Morale.BOLD: "Bold",
	Morale.NORMAL: "Normal",
	Morale.CAUTIOUS: "Cautious",
	Morale.SHAKEN: "Shaken",
	Morale.ROUT: "Rout",
}

# --- Le sei direzioni della bussola (Rule 9.3) ---
# Direzioni 1-6. Le teniamo come interi 1..6 per aderenza al manuale.

# --- I lati ---
enum Side { FRIENDLY, ENEMY }

# --- Gli Ordini (Rule 7.0 e 10.0) ---
enum Order {
	AIMED_FIRE,
	RAPID_FIRE,
	SUPPRESSIVE_FIRE,
	RUN_AND_GUN,
	SNEAK,
	EVADE,
	SPRINT,
	CHARGE,
	GRENADE,
	SMOKE_GRENADE,
	RIFLE_GRENADE,
	PLAN,
	RELOAD,
	MEDICAL_AID,
	SEARCH,
	HIDE,
	RALLY,
	CARRY_DRAG,
	DUCK_BACK,
	MELEE,
	GUARD,
}

# Nomi leggibili degli ordini per debug/UI
const ORDER_NAMES := {
	Order.AIMED_FIRE: "Aimed Fire",
	Order.RAPID_FIRE: "Rapid Fire",
	Order.SUPPRESSIVE_FIRE: "Suppressive Fire",
	Order.RUN_AND_GUN: "Run & Gun",
	Order.SNEAK: "Sneak",
	Order.EVADE: "Evade",
	Order.SPRINT: "Sprint",
	Order.CHARGE: "Charge",
	Order.GRENADE: "Grenade",
	Order.SMOKE_GRENADE: "Smoke Grenade",
	Order.RIFLE_GRENADE: "Rifle Grenade",
	Order.PLAN: "Plan",
	Order.RELOAD: "Reload",
	Order.MEDICAL_AID: "Medical Aid",
	Order.SEARCH: "Search",
	Order.HIDE: "Hide",
	Order.RALLY: "Rally",
	Order.CARRY_DRAG: "Carry/Drag",
	Order.DUCK_BACK: "Duck Back",
	Order.MELEE: "Melee",
	Order.GUARD: "Guard",
}

# Cosa puo' fare un personaggio in ciascuno dei 4 impulsi (Rule 6.0).
enum ImpulseAction {
	NOTHING,    # 0  - non muove ne' spara
	MAY_MOVE_1, # 1 blu - puo' muovere 1 hex
	MUST_MOVE_1,# 1 nero - deve muovere 1 hex
	MAY_FIRE,   # 1 rosso - puo' sparare
	MUST_MOVE_2,# 2 nero - deve muovere 2 hex
	MELEE,      # M
}

# --- Tipi di terreno (Rule 11.0) ---
enum Terrain {
	OPEN_LEVEL_0, OPEN_LEVEL_1, OPEN_LEVEL_2, OPEN_LEVEL_3,
	ROCKS, BUILDING, TREES, MARSH, HEDGEROW, WALL,
	LONG_GRASS, DEPRESSION, STREAM, ORCHARD, LOGS,
	FIELD, FOXHOLE, RUBBLE, CRATER,
}

# Terreni che contano come "In Cover" per le tabelle delle Enemy Card.
# PROVVISORIO: classificazione di buon senso (protezione fisica si',
# semplice occultamento no). Da verificare contro il regolamento (Rule 9/11).
const COVER_TERRAINS := [
	Terrain.ROCKS, Terrain.BUILDING, Terrain.TREES, Terrain.HEDGEROW,
	Terrain.WALL, Terrain.DEPRESSION, Terrain.STREAM, Terrain.LOGS,
	Terrain.FOXHOLE, Terrain.RUBBLE, Terrain.CRATER,
]


func terrain_gives_cover(terrain: int) -> bool:
	return terrain in COVER_TERRAINS


# --- Tipi di check (Rule 19.0) ---
enum Check { MC, RC, TQC, WMC }

# --- Tipi di ferita (Rule 16.0) ---
enum Wound { LIGHT, BAD }

# Alza il morale di n livelli (verso BERSERK), senza superare un tetto.
# Ritorna il nuovo valore di morale.
func raise_morale(current: Morale, levels: int, cap: Morale = Morale.BERSERK) -> Morale:
	var new_value: int = max(int(cap), int(current) - levels)
	return new_value as Morale

# Abbassa il morale di n livelli (verso ROUT).
func lower_morale(current: Morale, levels: int) -> Morale:
	var new_value: int = min(int(Morale.ROUT), int(current) + levels)
	return new_value as Morale
