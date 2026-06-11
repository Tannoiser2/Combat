## Caratteristiche delle armi, trascritte dal Weapon Characteristics Chart.
##
## Ogni arma ha: gittata massima, fasce di gittata con modificatore al WS
## (bands: [fino_a_hex, modificatore] in ordine crescente), Rate of Fire
## (attacchi per azione di fuoco) e flag (heavy, belt, slow...).
## Le granate hanno Damage/Frag invece delle fasce (TODO quando faremo
## l'attacco con granate).
class_name Weapons
extends RefCounted

const DATA := {
	"M1 Garand": {"max_range": 50, "rof": 1, "flags": [],
		"bands": [[1, 2], [3, 1], [10, 0], [25, -2], [50, -4]]},
	"M3 Grease Gun": {"max_range": 12, "rof": 3, "flags": [],
		"bands": [[1, 2], [3, 1], [6, 0], [10, -2], [12, -4]]},
	"BAR": {"max_range": 150, "rof": 2, "flags": ["heavy"],
		"bands": [[1, 2], [3, 1], [12, 0], [30, -2], [50, -4], [80, -6], [150, -8]]},
	"M1911": {"max_range": 7, "rof": 1, "flags": ["pistol"],
		"bands": [[1, 2], [2, 1], [4, 0], [6, -2], [7, -4]]},
	"M1919": {"max_range": 150, "rof": 4, "flags": ["very_heavy", "belt"],
		"bands": [[3, 2], [7, 1], [20, 0], [50, -2], [150, -4]]},
	"KAR 98K": {"max_range": 55, "rof": 1, "flags": ["slow"],
		"bands": [[1, 2], [3, 1], [12, 0], [30, -2], [55, -4]]},
	"MP40": {"max_range": 20, "rof": 3, "flags": [],
		"bands": [[1, 2], [3, 1], [6, 0], [10, -2], [15, -4], [20, -6]]},
	"MG42": {"max_range": 510, "rof": 5, "flags": ["heavy", "belt"],
		"bands": [[5, 2], [10, 1], [20, 0], [40, -2], [100, -4], [200, -6], [510, -8]]},
	"P38": {"max_range": 11, "rof": 1, "flags": ["pistol"],
		"bands": [[1, 2], [2, 1], [4, 0], [6, -2], [8, -4], [11, -6]]},
	# Lanciagranate: NA sotto i 5 hex, poi 0/+1/+2 (gittate si', fasce
	# invertite rispetto alle armi da fuoco). Damage/Frag TODO.
	"M7 Grenade Launcher": {"max_range": 25, "rof": 1, "flags": ["grenade"],
		"bands": [[4, -99], [12, 0], [20, 1], [25, 2]]},
}

# Alias usati nei dati di prova / nomi generici dei personaggi.
const ALIASES := {
	"Rifle": "KAR 98K",
	"SMG": "M3 Grease Gun",
}


static func info(name: String) -> Dictionary:
	var key: String = ALIASES.get(name, name)
	assert(DATA.has(key), "Arma sconosciuta: %s" % name)
	return DATA[key]


# Modificatore WS per la gittata, o null (fuori gittata / NA).
static func range_ws_modifier(name: String, dist: int) -> Variant:
	var w := info(name)
	if dist > int(w["max_range"]):
		return null
	for band in w["bands"]:
		if dist <= int(band[0]):
			return null if int(band[1]) == -99 else int(band[1])
	return null
