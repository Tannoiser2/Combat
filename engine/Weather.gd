## Meteo e condizioni del terreno (Rule 28).
##
## Il meteo da' un malus al WS per i tiri oltre i 2 hex (salvo tiratore e
## bersaglio nello stesso edificio) e puo' limitare la LOS massima (un valore
## tirato a inizio scenario: oltre quel raggio la visuale e' bloccata).
## Le condizioni del terreno (fango/neve) vietano certi ordini di movimento.
## Gli effetti sui veicoli (Rule 28/31-32) sono rimandati col resto dei mezzi.
class_name Weather
extends RefCounted

const D := preload("res://engine/Domain.gd")

enum Type { CLEAR, RAIN, HEAVY_RAIN, MIST, FOG }
enum Ground { NONE, MUD, SNOW, DEEP_SNOW }

const TYPE_NAMES := {
	Type.CLEAR: "Sereno", Type.RAIN: "Pioggia",
	Type.HEAVY_RAIN: "Pioggia battente", Type.MIST: "Foschia", Type.FOG: "Nebbia",
}
const GROUND_NAMES := {
	Ground.NONE: "Asciutto", Ground.MUD: "Fango",
	Ground.SNOW: "Neve", Ground.DEEP_SNOW: "Neve alta",
}

# Da nome (chiave di scenario) a enum.
const TYPE_BY_NAME := {
	"clear": Type.CLEAR, "rain": Type.RAIN, "heavy_rain": Type.HEAVY_RAIN,
	"mist": Type.MIST, "fog": Type.FOG,
}
const GROUND_BY_NAME := {
	"none": Ground.NONE, "mud": Ground.MUD,
	"snow": Ground.SNOW, "deep_snow": Ground.DEEP_SNOW,
}

# Malus al WS oltre i 2 hex (Rule 28.1).
const WS_BEYOND_2 := {
	Type.RAIN: -1, Type.HEAVY_RAIN: -1, Type.MIST: -1, Type.FOG: -2,
}

# Ordini di movimento vietati dalla condizione del terreno (Rule 28.2).
const FORBIDDEN := {
	Ground.MUD: [D.Order.SPRINT],
	Ground.SNOW: [D.Order.SPRINT],
	Ground.DEEP_SNOW: [D.Order.SPRINT, D.Order.EVADE, D.Order.RUN_AND_GUN],
}


# Visibilita' minima della Foschia (Mist = 1D6+4 -> minimo 5 hex). La Nebbia,
# piu' densa, non puo' mai dare visibilita' pari o superiore (Rule 28.1).
const MIST_MIN_LOS := 1 + 4


# Limite di visibilita' (max LOS) del meteo, tirato a inizio scenario.
# 0 = nessun limite. Rule 28.1.
static func roll_max_los(weather: int, rng: RandomNumberGenerator) -> int:
	match weather:
		Type.HEAVY_RAIN: return rng.randi_range(1, 6) + rng.randi_range(1, 6)
		Type.MIST: return rng.randi_range(1, 6) + 4
		Type.FOG:
			# La Nebbia (1D6) non puo' mai essere piu' rada della Foschia: se il
			# tiro raggiunge la visibilita' minima della Foschia, la nebbia
			# resta sotto (sempre piu' densa). Rule 28.1.
			var v := rng.randi_range(1, 6)
			return mini(v, MIST_MIN_LOS - 1)
		_: return 0


# Malus al WS del meteo per un tiro a distanza `dist`: vale solo oltre i
# 2 hex e salta se tiratore e bersaglio sono nello stesso edificio (Rule 28.1).
static func ws_modifier(state: GameState, firer: Character, target: Character, dist: int) -> int:
	if dist <= 2:
		return 0
	var mod: int = WS_BEYOND_2.get(state.weather, 0)
	if mod == 0:
		return 0
	if both_in_building(state, firer, target):
		return 0
	return mod


static func both_in_building(state: GameState, a: Character, b: Character) -> bool:
	var ha := state.hex_at(a.position.x, a.position.y)
	var hb := state.hex_at(b.position.x, b.position.y)
	return ha != null and hb != null \
		and ha.terrain == D.Terrain.BUILDING and hb.terrain == D.Terrain.BUILDING


static func order_forbidden(ground: int, order: int) -> bool:
	return order in FORBIDDEN.get(ground, [])


# Ordine "ridotto" quando quello scelto e' vietato dalla condizione del
# terreno: Mud/Snow -> Evade, Deep Snow -> Sneak (Rule 28.2). La direzione
# di movimento si conserva a parte (order_move).
static func demote_order(ground: int, order: int) -> int:
	if not order_forbidden(ground, order):
		return order
	return D.Order.SNEAK if ground == Ground.DEEP_SNOW else D.Order.EVADE


# Fine turno con Pioggia battente: 1d10, con 9 il terreno diventa Fango per
# il resto dello scenario (Rule 28.1). Ritorna true se il fango si e' formato.
static func maybe_make_mud(state: GameState) -> bool:
	if state.weather != Type.HEAVY_RAIN or state.ground == Ground.MUD:
		return false
	if Checks.roll_d10(state.rng) == 9:
		state.ground = Ground.MUD
		state.log_event("La pioggia battente trasforma il terreno in fango")
		return true
	return false
