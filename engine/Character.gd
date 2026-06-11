## Un personaggio: il "single man" del gioco (Rule 8.0).
##
## E' un RefCounted: oggetto dati puro, SENZA grafica. La miniatura/segnalino
## visivo sara' un nodo separato nella scena che legge questo oggetto.
## Cosi' il motore resta testabile e indipendente dalla rappresentazione.
class_name Character
extends RefCounted

# Identita'
var id: String
var display_name: String
var side: int            # Domain.Side
var team: String  # "Able"/"Baker"/"Charlie" oppure "Red"/"Yellow"/"White"/"Blue"

# Attributi base
var troop_quality: int          # TQ
var leadership: int = 0         # LDR (0 = nessuna)
var weapon_skills: Dictionary = {}  # nome arma (String) -> WS (int)

# Stato dinamico
var position: Vector2i          # (col, row) sulla griglia
var facing: int = 1             # direzione 1..6
var morale: int = Domain.Morale.NORMAL  # Domain.Morale
var order: int = -1             # Domain.Order, -1 = nessun ordine
var has_order: bool = false
var wounds: Array[int] = []     # Domain.Wound

# Stato di conoscenza/allerta
var spotted: bool = false       # Friendly: visto dal nemico
var known: bool = false         # Enemy: identificato dal giocatore
var alerted: bool = false       # Enemy: ha sentito qualcosa

# Marker
var low_ammo: bool = false
var no_ammo: bool = false


func _init(p_id: String, p_name: String, p_side: int, p_team: String) -> void:
	id = p_id
	display_name = p_name
	side = p_side
	team = p_team


# Somma dei modificatori TQ dovuti alle ferite (Rule 16.2).
# Light = -1, Bad = -3 (valori dai marker del manuale).
func wound_tq_modifier() -> int:
	var total := 0
	for w in wounds:
		match w:
			Domain.Wound.LIGHT: total -= 1
			Domain.Wound.BAD: total -= 3
	return total


# Un personaggio e' morto se le ferite portano la TQ a 0 o sotto (Rule 16.2).
func is_dead() -> bool:
	return troop_quality + wound_tq_modifier() <= 0
