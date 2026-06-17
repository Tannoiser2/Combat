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
	# Vol. 2 (Rule 26). Thompson: sostituibile al Grease Gun, gittata un po'
	# piu' lunga. Springfield M1903: fucile con mirino (scoped), Slow, +1 in
	# Aimed Fire oltre i 3 hex. StG 44: ROF 3 entro 13 hex, ROF 1 oltre.
	"M1 Thompson": {"max_range": 16, "rof": 3, "flags": [],
		"bands": [[1, 2], [3, 1], [6, 0], [10, -2], [16, -4]]},
	"M1903 Springfield": {"max_range": 55, "rof": 1, "flags": ["slow", "scoped"],
		"bands": [[1, 2], [3, 1], [12, 0], [30, -2], [55, -4]]},
	"StG 44": {"max_range": 66, "rof": 3, "flags": [],
		"rof_bands": [[13, 3], [66, 1]],
		"bands": [[1, 2], [3, 1], [13, 0], [22, -2], [33, -4], [66, -6]]},
	# Coltello da lancio del Knife Expert (Rule 24): ROF 1, gittata 2; il WS
	# (= TQ - gittata) lo calcola Fire._compute_ws dal flag "knife". "pistol"
	# = niente consumo munizioni.
	"Thrown Knife": {"max_range": 2, "rof": 1, "flags": ["knife", "pistol"],
		"bands": [[2, 0]]},
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
	# Rule 31-32: armi anticarro (AT) e armi montate sui veicoli.
	# pen_base + 1d{pen_die} vs armatura del bersaglio.
	"M2 .50cal": {"max_range": 200, "rof": 4, "flags": ["very_heavy", "belt"],
		"pen_base": 2, "pen_die": 3,   # 1D3+2 (media 3.5)
		"bands": [[4, 1], [10, 0], [20, -1], [50, -2], [200, -4]]},
	"Bazooka M9": {"max_range": 40, "rof": 1, "flags": ["at", "slow"],
		"pen_base": 7, "pen_die": 6,   # 7+1D6 (media 10.5)
		# Fasce dal Vehicle Display M9 (1:+1, 2-3:0, 4-8:-1, ...).
		"bands": [[1, 1], [3, 0], [8, -1], [12, -2], [20, -4], [30, -6], [40, -8]]},
	"Panzerfaust 60": {"max_range": 6, "rof": 1, "flags": ["at", "single_use"],
		"pen_base": 15, "pen_die": 6,  # 15+1D6 (media 18.5)
		"bands": [[1, 1], [3, 0], [6, -2]]},
	"Panzerfaust 100": {"max_range": 10, "rof": 1, "flags": ["at", "single_use"],
		"pen_base": 15, "pen_die": 6,
		# Chart: 1:+1, 2-3:0, 4-6:-2, 7-8:-4, 9-10:-6.
		"bands": [[1, 1], [3, 0], [6, -2], [8, -4], [10, -6]]},
	"75mm L40 HE": {"max_range": 100, "rof": 1, "flags": ["main_gun", "he"],
		"damage": 4, "frag": 4,
		"pen_base": 1, "pen_die": 6,   # 1+1D6 vs AFV (solo per AT di emergenza)
		"bands": [[4, 2], [12, 1], [25, 0], [50, -1], [100, -3]]},
	"75mm L40 AP": {"max_range": 100, "rof": 1, "flags": ["main_gun", "at"],
		"pen_base": 6, "pen_die": 6,   # 6+1D6 (media 9.5)
		"bands": [[4, 2], [12, 1], [25, 0], [50, -1], [100, -3]]},
	"KwK 7.5cm HE": {"max_range": 100, "rof": 1, "flags": ["main_gun", "he"],
		"damage": 3, "frag": 4,
		"pen_base": 1, "pen_die": 6,
		"bands": [[4, 2], [12, 1], [25, 0], [50, -1], [100, -3]]},
	"KwK 7.5cm AP": {"max_range": 100, "rof": 1, "flags": ["main_gun", "at"],
		"pen_base": 9, "pen_die": 6,   # 9+1D6 (media 12.5)
		"bands": [[4, 2], [12, 1], [25, 0], [50, -1], [100, -3]]},
	"MG34 Vehicle": {"max_range": 300, "rof": 4, "flags": ["heavy", "belt"],
		"bands": [[5, 2], [10, 1], [20, 0], [40, -2], [100, -4], [200, -6], [300, -8]]},
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


# Bazooka / Light AT che richiede caricamento (Rule 32.1): arma "at" di fanteria
# non monouso (il Panzerfaust e' monouso e non si ricarica).
static func is_loadable_at(name: String) -> bool:
	var f: Array = info(name)["flags"]
	return "at" in f and not ("main_gun" in f) and not ("single_use" in f)


# Rate of Fire alla gittata data. Le armi senza "rof_bands" hanno ROF fisso;
# lo StG 44 (Rule 26) spara a ROF 3 entro 13 hex e ROF 1 oltre.
static func rof_at(name: String, dist: int) -> int:
	var w := info(name)
	if w.has("rof_bands"):
		for band in w["rof_bands"]:  # [gittata_max, rof]
			if dist <= int(band[0]):
				return int(band[1])
	return int(w["rof"])


# Modificatore WS per la gittata, o null (fuori gittata / NA).
static func range_ws_modifier(name: String, dist: int) -> Variant:
	var w := info(name)
	if dist > int(w["max_range"]):
		return null
	for band in w["bands"]:
		if dist <= int(band[0]):
			return null if int(band[1]) == -99 else int(band[1])
	return null
