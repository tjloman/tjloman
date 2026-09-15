class_name LogoGame
extends Control
## SOMETHING TO DO WHILE THE WORLD ARRIVES.
##
## A loading screen is a promise that something is happening, and a progress
## bar is the weakest possible form of that promise. This one hands you the
## game's own verb instead: you draw on it with your finger, exactly as you
## will draw every miracle you ever cast, and the mark under your finger
## changes colour as you go. By the time the bar is full you have already
## learned the only control the game does not otherwise teach you.
##
## THE COLOUR IS THE WHOLE TOY. The mark begins purple and orange. Wherever
## your finger passes it turns green and blue — instantly, exactly along the
## path, at the width of a thumb — so the reveal is a drawing and not a wipe.
## It is a warm thing becoming a cool one under your hand, which is a small
## promise of its own about what this game is.
##
## THE MARK COMES OUT OF A FILE. `res://branding/logo.png` if it is there, and
## a racing checker if it is not — the same bargain ModelBank makes with every
## model in the game: art drops in later and no code changes. A two-tone image
## is all it wants. Whatever is DARK in the file becomes one half of the
## palette and whatever is LIGHT becomes the other, and anything transparent is
## not part of the mark at all, so a logo on a clear background works as it
## stands.

## Emitted the moment the whole mark has turned. Nothing depends on it — the
## toy is a toy — but the start screen brightens when it fires.
signal finished

## WHERE THE REAL MARK LIVES, when there is one.
const MARK_FILE := "res://branding/logo.png"

## HOW FINE THE MARK IS. A hundred and twenty-eight square is a 64KB texture
## upload on the frames a finger is moving and nothing at all on the frames it
## is not — small enough to be free on a phone, fine enough that the edge of a
## stroke reads as a stroke rather than as stairs.
const PIXELS := 128
## SQUARES ACROSS THE CHECKER, when there is no file to read. Eight is a racing
## flag; sixteen is a texture.
const SQUARES := 8

## HOW WIDE A FINGER IS, in mark pixels, and how far along a drag it steps
## between stamps. Half a brush, so a fast swipe lays a continuous line rather
## than a row of spots.
const BRUSH := 9.0
const STEP_OF_BRUSH := 0.5

## THE TWO PALETTES, dark half first. Warm to begin with, cool under the hand.
const WARM: Array[Color] = [Color(0.36, 0.13, 0.55), Color(0.98, 0.52, 0.13)]
const COOL: Array[Color] = [Color(0.10, 0.64, 0.42), Color(0.16, 0.52, 0.95)]

## How much of the mark has to turn before it counts as finished, and how long
## a finished stroke stays on screen.
const TURNED_ENOUGH := 0.94
const TRAIL_HOLDS := 0.55

## Which palette a pixel belongs to: 0 dark, 1 light, 2 not part of the mark.
const DARK := 0
const LIGHT := 1
const NOWHERE := 2

var _img: Image
var _tex: ImageTexture
## Per pixel: which half of the palette it is, and whether it has turned yet.
var _half := PackedByteArray()
var _turned := PackedByteArray()
var _of_the_mark := 0
var _turns := 0
var _done := false
## The stroke under the finger, in this control's own coordinates.
var _path := PackedVector2Array()
var _holding := 0.0
var _last := Vector2.INF


func _ready() -> void:
	# The size is whatever whoever built this asked for — set here it would
	# overwrite it, because `_ready` runs on add_child and the caller sets its
	# minimum before that.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_mark()


## HOW MUCH OF IT HAS TURNED, 0..1 — for anything that wants to show progress
## of its own, and for knowing when the toy is done with.
func turned() -> float:
	if _of_the_mark == 0:
		return 0.0
	return float(_turns) / float(_of_the_mark)


func is_finished() -> bool:
	return _done


## THE MARK ITSELF. A file if there is one, a racing checker if there is not.
func _build_mark() -> void:
	var source := _read_the_file()
	_img = Image.create_empty(PIXELS, PIXELS, false, Image.FORMAT_RGBA8)
	_half.resize(PIXELS * PIXELS)
	_turned.resize(PIXELS * PIXELS)
	var square := float(PIXELS) / float(SQUARES)
	# How many of the file's pixels one of ours is. `step` and not `scale`:
	# every Control has a `scale`, and shadowing it here is how a later edit
	# meaning the node's own comes to mean this instead.
	var step := Vector2.ONE
	if source != null:
		step = Vector2(source.get_width(), source.get_height()) / float(PIXELS)
	for y in PIXELS:
		for x in PIXELS:
			var at := y * PIXELS + x
			var side := NOWHERE
			if source != null:
				var px := source.get_pixel(
					mini(int(x * step.x), source.get_width() - 1),
					mini(int(y * step.y), source.get_height() - 1))
				# Transparent is not part of the mark; everything else is one
				# half of the palette or the other by how bright it is.
				if px.a > 0.5:
					side = LIGHT if px.get_luminance() > 0.5 else DARK
			else:
				# THE RACING CHECKER, which is every square of it.
				var col := int(float(x) / square)
				var row := int(float(y) / square)
				side = DARK if (col + row) % 2 == 0 else LIGHT
			_half[at] = side
			_turned[at] = 0
			if side == NOWHERE:
				_img.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				_of_the_mark += 1
				_img.set_pixel(x, y, WARM[side])
	_tex = ImageTexture.create_from_image(_img)


## The file, as an Image, or null when there is not one. Never fails loudly: a
## missing logo is the ordinary case, not an error.
func _read_the_file() -> Image:
	if not ResourceLoader.exists(MARK_FILE):
		return null
	var art := load(MARK_FILE) as Texture2D
	if art == null:
		return null
	var img := art.get_image()
	if img == null or img.get_width() < 2 or img.get_height() < 2:
		return null
	# An imported texture usually arrives VRAM-compressed, and `get_pixel` on
	# compressed data errors rather than answering. Cheap here — it happens once
	# on a screen whose whole job is waiting — and the difference between a logo
	# appearing and a screenful of red errors.
	if img.is_compressed():
		if img.decompress() != OK:
			return null
	return img


func _process(delta: float) -> void:
	if _holding > 0.0:
		_holding -= delta
		if _holding <= 0.0:
			_path.clear()
			queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.button_index != MOUSE_BUTTON_LEFT:
			return
		if click.pressed:
			_path.clear()
			_holding = 0.0
			_last = click.position
			_path.append(click.position)
			_stroke(click.position, click.position)
		else:
			_last = Vector2.INF
			_holding = TRAIL_HOLDS
		accept_event()
	elif event is InputEventMouseMotion and _last != Vector2.INF:
		var moved := event as InputEventMouseMotion
		_stroke(_last, moved.position)
		_last = moved.position
		_path.append(moved.position)
		# A long drag is a long array, and only the tail of it is a trail.
		if _path.size() > 96:
			_path = _path.slice(_path.size() - 96)
		accept_event()


## ONE SEGMENT OF FINGER, turned. Walks the line in mark pixels stamping discs,
## so a fast swipe lays a continuous stroke rather than a row of spots.
func _stroke(from: Vector2, to: Vector2) -> void:
	var a := _to_mark(from)
	var b := _to_mark(to)
	# A FINGER THAT CAME IN FROM THE SIDE STILL PAINTS. The mark is a centred
	# square inside a control that may be wider, so a stroke begun in the
	# margin has one end off the mark — and refusing both ends meant that,
	# having started there, you could never paint at all.
	if a == Vector2.INF and b == Vector2.INF:
		return
	if a == Vector2.INF:
		a = b
	elif b == Vector2.INF:
		b = a
	var span := a.distance_to(b)
	var steps := maxi(1, int(span / (BRUSH * STEP_OF_BRUSH)))
	var before := _turns
	for i in range(steps + 1):
		_stamp(a.lerp(b, float(i) / float(steps)))
	if _turns == before:
		queue_redraw()   # the trail moved even where nothing turned
		return
	_tex.update(_img)
	queue_redraw()
	if not _done and turned() >= TURNED_ENOUGH:
		_done = true
		finished.emit()


## A round stamp of cool colour at a point in mark space.
func _stamp(at: Vector2) -> void:
	var r := int(ceil(BRUSH))
	var rr := BRUSH * BRUSH
	for dy in range(-r, r + 1):
		var y := int(at.y) + dy
		if y < 0 or y >= PIXELS:
			continue
		for dx in range(-r, r + 1):
			var x := int(at.x) + dx
			if x < 0 or x >= PIXELS:
				continue
			if float(dx * dx + dy * dy) > rr:
				continue
			var i := y * PIXELS + x
			if _turned[i] == 1 or _half[i] == NOWHERE:
				continue
			_turned[i] = 1
			_turns += 1
			_img.set_pixel(x, y, COOL[_half[i]])


## WHERE THE MARK IS DRAWN, in this control: the largest centred square that
## fits. One answer, used by the drawing and by the hit testing, so the pixel
## your finger is over is the pixel that turns.
func _frame() -> Rect2:
	var side := minf(size.x, size.y)
	return Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))


## A point in this control, as a point in the mark, or INF if it missed.
func _to_mark(at: Vector2) -> Vector2:
	var box := _frame()
	if box.size.x <= 0.0:
		return Vector2.INF
	var u := (at - box.position) / box.size
	if u.x < 0.0 or u.x > 1.0 or u.y < 0.0 or u.y > 1.0:
		return Vector2.INF
	return u * float(PIXELS)


func _draw() -> void:
	var box := _frame()
	if _tex != null:
		draw_texture_rect(_tex, box, false)
	# THE SAME STROKE THE MIRACLES ARE DRAWN WITH. See GestureTrail.paint: one
	# recipe, so the line you learn here is the line you cast with.
	GestureTrail.paint(self, _path)
