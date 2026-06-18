extends SceneTree
## Genera un'anteprima PNG del nuovo stile pedina: bordo colorato (= morale) al
## posto del pallino in alto a sinistra, piu' spesso quando la pedina e'
## evidenziata. Compositing via Image (CPU, nessun rendering GPU: gira headless).
## Uso: godot --headless --path . --script res://tools/border_preview.gd
## Output: /tmp/border_preview.png

const COUNTER := "res://assets/counters/US-Charlie-Pvt-Stubbs-f.png"

# Colori morale (da MapView.MORALE_COLORS).
const C_NORMAL := Color(0.30, 0.80, 0.30)
const C_BOLD := Color(0.25, 0.65, 0.95)
const C_CAUTIOUS := Color(0.95, 0.85, 0.15)
const C_SHAKEN := Color(0.90, 0.25, 0.20)
const BG := Color(0.12, 0.13, 0.15)
const TITLE_BAR := Color(0.20, 0.22, 0.26)


func _initialize() -> void:
	var canvas := Image.create(860, 470, false, Image.FORMAT_RGBA8)
	canvas.fill(BG)

	var side := 150
	var src := Image.load_from_file(COUNTER)
	if src == null:
		push_error("Counter non trovato: " + COUNTER)
		quit()
		return
	src.convert(Image.FORMAT_RGBA8)

	# Striscia titolo in alto.
	for y in range(0, 6):
		for x in range(canvas.get_width()):
			canvas.set_pixel(x, y, TITLE_BAR)

	# --- Riga 1: ATTUALE (pallino) | NUOVO normale (bordo sottile) | NUOVO evidenziato (bordo spesso) ---
	var y1 := 70
	var xs := [60, 360, 660]

	# 1) Stile ATTUALE: pallino verde in alto a sinistra (copre il nome).
	_blit(canvas, src, xs[0], y1, side)
	_dot(canvas, xs[0] + int(side * 0.17), y1 + int(side * 0.17), int(side * 0.13), C_NORMAL)

	var cr := int(side * 0.11)   # raggio d'angolo della pedina

	# 2) NUOVO normale: bordo verde sottile, nessun pallino (nome leggibile).
	_blit(canvas, src, xs[1], y1, side)
	_frame(canvas, xs[1], y1, side, side, cr, C_NORMAL, 5)

	# 3) NUOVO evidenziato: bordo verde piu' SPESSO + alone bianco/giallo.
	_blit(canvas, src, xs[2], y1, side)
	_frame(canvas, xs[2], y1, side, side, cr, C_NORMAL, 10)
	# Alone esterno: bianco vicino, giallo che sfuma piu' fuori.
	_ring(canvas, xs[2], y1, side, side, cr, Color(1, 1, 1, 0.95), 11)
	_ring(canvas, xs[2], y1, side, side, cr, Color(1, 0.95, 0.4, 0.85), 12)
	_ring(canvas, xs[2], y1, side, side, cr, Color(1, 0.9, 0.3, 0.55), 13)
	_ring(canvas, xs[2], y1, side, side, cr, Color(1, 0.9, 0.3, 0.30), 14)
	_ring(canvas, xs[2], y1, side, side, cr, Color(1, 0.9, 0.3, 0.15), 15)

	# Etichette-segnaposto: barrette colorate sotto a ogni pedina (no testo in
	# headless). Sinistra=grigio (attuale), centro/destra=verde (nuovo).
	_caption(canvas, xs[0], y1 + side + 12, side, Color(0.55, 0.55, 0.58))
	_caption(canvas, xs[1], y1 + side + 12, side, C_NORMAL)
	_caption(canvas, xs[2], y1 + side + 12, side, C_NORMAL.lightened(0.1))

	# --- Riga 2: palette dei colori morale (bordo sottile) ---
	var y2 := 320
	var side2 := 90
	var palette := [C_NORMAL, C_BOLD, C_CAUTIOUS, C_SHAKEN]
	var small := src.duplicate()
	small.resize(side2, side2, Image.INTERPOLATE_LANCZOS)
	var cr2 := int(side2 * 0.11)
	var px := 60
	for col in palette:
		_blit_ready(canvas, small, px, y2, side2)
		_frame(canvas, px, y2, side2, side2, cr2, col, 5)
		px += side2 + 90

	canvas.save_png("/tmp/border_preview.png")
	print("OK -> /tmp/border_preview.png")
	quit()


# Ridimensiona e fonde il counter nel canvas a (x,y) con lato `side`.
func _blit(canvas: Image, src: Image, x: int, y: int, side: int) -> void:
	var s := src.duplicate()
	s.resize(side, side, Image.INTERPOLATE_LANCZOS)
	_blit_ready(canvas, s, x, y, side)


# Fonde un'immagine gia' ridimensionata.
func _blit_ready(canvas: Image, s: Image, x: int, y: int, side: int) -> void:
	canvas.blend_rect(s, Rect2i(0, 0, side, side), Vector2i(x, y))


# Punto dentro un rettangolo ad angoli arrotondati (raggio cr).
func _rr(px: int, py: int, x0: int, y0: int, w: int, h: int, cr: float) -> bool:
	if px < x0 or py < y0 or px > x0 + w - 1 or py > y0 + h - 1:
		return false
	# Centri dei 4 archi d'angolo.
	var cxl := x0 + cr
	var cxr := x0 + w - 1 - cr
	var cyt := y0 + cr
	var cyb := y0 + h - 1 - cr
	var ax := px
	var ay := py
	if px < cxl and py < cyt: ax = cxl; ay = cyt           # alto-sx
	elif px > cxr and py < cyt: ax = cxr; ay = cyt          # alto-dx
	elif px < cxl and py > cyb: ax = cxl; ay = cyb          # basso-sx
	elif px > cxr and py > cyb: ax = cxr; ay = cyb          # basso-dx
	else: return true                                       # zona dritta
	var dx := px - ax
	var dy := py - ay
	return dx * dx + dy * dy <= cr * cr


# Cornice arrotondata di spessore `t` ATTORNO alla pedina (verso l'esterno):
# banda tra il bordo esterno (pedina cresciuta di t) e quello della pedina.
func _frame(canvas: Image, x0: int, y0: int, w: int, h: int, cr: float, col: Color, t: int) -> void:
	for y in range(y0 - t, y0 + h + t):
		for x in range(x0 - t, x0 + w + t):
			if _rr(x, y, x0 - t, y0 - t, w + 2 * t, h + 2 * t, cr + t) \
					and not _rr(x, y, x0, y0, w, h, cr):
				_px(canvas, x, y, col)


# Anello arrotondato spesso 1px a distanza `inset` dalla pedina (alone selezione).
func _ring(canvas: Image, x0: int, y0: int, w: int, h: int, cr: float, col: Color, inset: int) -> void:
	var i0 := inset - 1
	for y in range(y0 - inset, y0 + h + inset):
		for x in range(x0 - inset, x0 + w + inset):
			if _rr(x, y, x0 - inset, y0 - inset, w + 2 * inset, h + 2 * inset, cr + inset) \
					and not _rr(x, y, x0 - i0, y0 - i0, w + 2 * i0, h + 2 * i0, cr + i0):
				_px(canvas, x, y, col)


# Pallino pieno con anello nero (replica il pallino morale attuale).
func _dot(canvas: Image, cx: int, cy: int, r: int, col: Color) -> void:
	_circle(canvas, cx, cy, r + 2, Color(0, 0, 0, 0.85))
	_circle(canvas, cx, cy, r, col)


func _circle(canvas: Image, cx: int, cy: int, r: int, col: Color) -> void:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			var dx := x - cx
			var dy := y - cy
			if dx * dx + dy * dy <= r * r:
				_px(canvas, x, y, col)


# Barretta-didascalia (colore = stato), sotto la pedina.
func _caption(canvas: Image, x: int, y: int, w: int, col: Color) -> void:
	for yy in range(y, y + 10):
		for xx in range(x, x + w):
			_px(canvas, xx, yy, col)


func _px(canvas: Image, x: int, y: int, col: Color) -> void:
	if x < 0 or y < 0 or x >= canvas.get_width() or y >= canvas.get_height():
		return
	if col.a >= 1.0:
		canvas.set_pixel(x, y, col)
	else:
		var bg := canvas.get_pixel(x, y)
		canvas.set_pixel(x, y, bg.lerp(col, col.a))
