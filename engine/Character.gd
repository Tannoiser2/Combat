## Un personaggio: il "single man" del gioco (Rule 8.0).
##
## E' un RefCounted: oggetto dati puro, SENZA grafica. La miniatura/segnalino
## visivo sara' un nodo separato nella scena che legge questo oggetto.
## Cosi' il motore resta testabile e indipendente dalla rappresentazione.
class_name Character
extends RefCounted

# Skill dei nemici Elite SS (Rule 24). Si assegnano in state.characters
# tramite Character.skills (vedi Scenario._make). Stringhe, non enum, cosi'
# si leggono nei log e si dichiarano facilmente nelle voci di scenario.
const SKILL_DODGE := "Dodge"           # -1 WS a chi spara, se il bersaglio e' in Evade
const SKILL_DODGE_2 := "Dodge-2"       # -2 WS (versione potenziata)
const SKILL_TOUGH := "Tough"           # ferito: pesca 2, applica la MENO dannosa
const SKILL_DEADLY := "Deadly"         # quando spara: pesca 2, applica la PIU' dannosa
const SKILL_EAGLE_EYES := "Eagle Eyes" # +1 TQ in spotting (TQ effettiva max 8)
const SKILL_SNIPER := "Sniper"         # +2 WS in Aimed Fire (non all'impulso 2)
const SKILL_KNIFE_EXPERT := "Knife Expert"  # +1 TQ in mischia (+ coltello da lancio)
const SKILL_WINTER_CAMO := "Winter Camouflage"  # -1 a essere individuato su neve (Rule 28.2)

# Identita'
var id: String
var display_name: String
var side: int            # Domain.Side
var team: String  # "Able"/"Baker"/"Charlie" oppure "Red"/"Yellow"/"White"/"Blue"
# Base del file del segnalino Vassal (es. "GE-RedTeam-Soldat-Jung"); la UI
# disegna "<counter>-f.png" da assets/counters/ se presente. "" = ripiego.
var counter: String = ""

# Attributi base
var troop_quality: int          # TQ
var leadership: int = 0         # LDR (0 = nessuna)
var weapon_skills: Dictionary = {}  # nome arma (String) -> WS (int)
var skills: Array[String] = []  # skill speciali (Rule 24), vedi le costanti SKILL_*

# Stato dinamico
var position: Vector2i          # (col, row) sulla griglia
var facing: int = 1             # direzione 1..6
var morale: int = Domain.Morale.NORMAL  # Domain.Morale
var order: int = -1             # Domain.Order, -1 = nessun ordine
var has_order: bool = false
# Estensioni dell'ordine stampate sulle Enemy Card (Rule 9.0)
var order_move: String = ""     # valore di movimento, es. "5/6" ("" = nessuno)
var order_grenade: bool = false # G: lancia una granata se possibile
var order_charge: bool = false  # C: carica se possibile
var thrown: bool = false        # granata gia' lanciata in questo turno
var wounds: Array[int] = []     # Domain.Wound

# Stato di conoscenza/allerta
var spotted: bool = false       # Friendly: visto dal nemico
var known: bool = false         # Enemy: identificato dal giocatore
var alerted: bool = false       # Enemy: ha sentito qualcosa (Rule 9.7)
# Preparato (Rule 9.7): proprieta' di scenario. Un nemico Preparato pesca un
# Ordine appena entra in Allerta; un Non-Preparato perde la prima attivazione
# (pesca l'Ordine solo dal turno successivo). Impostato allo schieramento.
var prepared: bool = true
var is_prisoner: bool = false   # Enemy in Rout che si e' arreso in mischia

# Marker
var low_ammo: bool = false
var no_ammo: bool = false

# Ruolo dello scenario ("Recruit", "NCO", "Officer"...): serve ai VP.
var role: String = ""
# Medico addestrato (Rule 30): disarmato, mai fuoco/mischia, +2 TQ alle cure,
# fugge se un avversario entra nel suo hex. Vale per friendly ed enemy.
var is_medic: bool = false
# MG Operator (Rule 14.3): belt-fed senza un compagno nello stesso hex
# (portatore di munizioni) = -3 WS; alla morte dell'operatore un compagno
# nell'hex prende il controllo dell'arma.
var mg_role: String = ""         # "operator" | ""

# Pedina-esca (Dummy): nessun valore reale; quando viene individuata si
# rivela e sparisce. removed = tolta dal gioco (esca rivelata o uscita).
var is_dummy: bool = false
var removed: bool = false
# Nemico fuggito dalla mappa in Rout: conta come eliminato per i VP.
var routed_off: bool = false
# Ha gia' ricevuto il primo ordine? (per gli ordini forzati di scenario)
var had_first_order: bool = false
# Veicolo (Rule 31-32): is_vehicle=true per Jeep/Halftrack/carri armati.
var is_vehicle: bool = false
var vehicle_type: String = ""   # "Jeep", "M3A1 Halftrack", "M4A3 Sherman", "PzIVH"
var hull_damage: int = 0        # 0=OK, 1=immobilizzato, 2=distrutto
var is_buttoned_up: bool = false
# Torretta (Rule 31.6): solo gli AFV (carri) hanno una torretta che ruota
# indipendentemente dallo scafo. turret_facing 1..6 e' assoluto (come facing);
# 0 = non applicabile (Jeep/Halftrack senza torretta). Lo scafo (facing) gira
# col movimento, la torretta gira 1 hex-side per impulso verso il bersaglio.
var turret_facing: int = 0
# fire_mode per cannoni principali: "AP" o "HE" scelto dal Loader; "" = auto (prima arma)
var fire_mode: String = ""
# Rule 31.1.3: stato di carica del cannone principale. Il Loader deve caricarlo;
# ogni colpo lo svuota e la ricarica consuma un impulso. Parte carico.
var main_gun_loaded: bool = true
# Guasti da hit-location (Rule 31.10): cingoli/sospensioni colpiti = immobilizzato
# (non muove piu'); cannone distrutto = non spara col main gun; torretta inceppata
# = non ruota piu' (puo' sparare solo se gia' allineata); coassiale/bow MG distrutte.
var immobilized: bool = false
var main_gun_wrecked: bool = false
var turret_jammed: bool = false
var coax_wrecked: bool = false
var bow_mg_wrecked: bool = false
# Rule 31.9.4c: se true il Gunner spara la MG coassiale invece del cannone
# (usato sul membro Gunner del veicolo).
var fires_coax: bool = false
# Rule 31.6: Emergency Stop — il Driver ha smesso di avanzare per una minaccia AT.
# -2 WS a tutto il fuoco del veicolo; +1 WS per chi spara contro il veicolo.
var emergency_stop: bool = false
# Equipaggio (Rule 31). I crew sono Character veri con un ruolo: nel modello
# intermedio sono feribili/uccidibili individualmente e possono abbandonare
# il mezzo (bail out). Tenerli come Character (non semplici contatori) rende
# incrementale il futuro modello completo (spotting/LOS/Target Marker per ruolo).
var crew: Array = []              # solo sul veicolo: i Character dell'equipaggio
var embarked: bool = false        # crew: ancora a bordo del mezzo (false = sceso/a piedi)
var crew_role: String = ""        # "Commander"/"Driver"/"Gunner"/"Loader"/"Co-Driver"
# Evitiamo un riferimento forte al veicolo (ciclo RefCounted): la lista
# vehicle.crew e' la fonte di verita' sull'appartenenza. Per il futuro
# modello completo il mezzo si ritrova cercando in state.characters.


func _init(p_id: String, p_name: String, p_side: int, p_team: String) -> void:
	id = p_id
	display_name = p_name
	side = p_side
	team = p_team


# Possiede una skill speciale (Rule 24)?
func has_skill(skill: String) -> bool:
	return skill in skills


# Allerta a meta' partita per una delle condizioni della Rule 9.8 (colpo udito,
# avvistamento, esplosione, mischia...). NON tocca `prepared`: Preparato/Non
# Preparato e' una proprieta' di scenario fissata allo schieramento (Rule 9.7).
# Idempotente.
func alert() -> void:
	alerted = true


# Membro di equipaggio (Rule 31), dentro o fuori dal mezzo.
func is_crew() -> bool:
	return not crew_role.is_empty()


func set_order(p_order: int, p_move: String = "", p_grenade: bool = false, p_charge: bool = false) -> void:
	order = p_order
	order_move = p_move
	order_grenade = p_grenade
	order_charge = p_charge
	has_order = true


func clear_order() -> void:
	order = -1
	order_move = ""
	order_grenade = false
	order_charge = false
	has_order = false
	thrown = false


# Somma dei modificatori TQ dovuti alle ferite (Rule 16.2).
# Light = -1, Bad = -3 (valori dai marker del manuale).
func wound_tq_modifier() -> int:
	var total := 0
	for w in wounds:
		match w:
			Domain.Wound.LIGHT: total -= 1
			Domain.Wound.BAD: total -= 3
	return total


# Totale (positivo) del malus da ferite.
func wound_total() -> int:
	return -wound_tq_modifier()


# "Fuori gioco" = morto o incapacitato (per attivazione/bersaglio).
# Note del Fire Resolution Chart: Enemy morto se malus ferite >= TQ;
# Friendly incapacitato se = TQ, morto se > TQ.
func is_dead() -> bool:
	if removed:
		return true
	if is_vehicle:
		return hull_damage >= 2
	if side == Domain.Side.ENEMY:
		return wound_total() >= troop_quality
	return wound_total() >= troop_quality  # incap o morto: comunque fuori


# Friendly incapacitato (malus ferite = TQ): fuori azione ma non ucciso,
# recuperabile col Medic. I nemici non hanno questo stato.
func is_incapacitated() -> bool:
	return side == Domain.Side.FRIENDLY and wound_total() == troop_quality


# Davvero ucciso (KIA), per i conteggi di vittoria.
func is_killed() -> bool:
	if side == Domain.Side.ENEMY:
		return wound_total() >= troop_quality
	return wound_total() > troop_quality
