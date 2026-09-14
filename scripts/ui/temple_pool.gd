class_name TemplePool
extends Control
## THE REFLECTING POOL: the land, seen from above, in still water.
##
## THE WORLD IS ENDLESS, so this is a window and not a map: there is no extent
## to fit on screen, since `WorldGen.seeded_height_at` answers for any
## coordinate you care to name.
##
## WHICH IS EXACTLY WHY IT MUST BE FOGGED. The seed can draw a valley nobody
## has ever visited, and drawing it would be a lie — a god who has walked a
## country and a god who has been handed a survey of it are in different
## positions, and this is the one place that difference is visible. So the
## water shows only what WorldGen remembers raising: WALKED cells in full,
## SEEN ones (bare ground glimpsed out in the sight ring) dimmed, everything
## else fog. The scroll stops at the edge of the fog rather than drifting out
## into country that is not there.
##
## AND A PIN IS A DOOR HOME. Touch one and you leave the temple standing over
## that village, which answers the lost player and the uninformed one with the
## same gesture and is most of why the well is worth having.
##
## Villages are nodes and a node only exists inside the streaming rings, so the
## pins come from the villages loaded now PLUS SaveGame.village_memory: every
## town met and walked away from.
##
## IT NEVER HITCHES. Sampling the terrain is noise lookups, and a full window
## is tens of thousands of them, so the image is raised a few rows per frame
## and fades in as it settles — which is both the cheap way and the right
## picture for a pool.

## Somebody touched a pin and wants to be standing there. Temple relays it.
signal travel_to(spot: Vector3)

## The image the water holds. Square, because the window is square, and modest
## because every pixel is a biome lookup plus a height lookup.
const GRID := 176
## How many rows are raised per frame. The whole window settles in about a
## second, which reads as water going still.
const ROWS_PER_FRAME := 12

## How much land the pool shows across its width, in metres, and the range the
## scroll wheel and the pinch may take it to. Sixteen chunks at the default.
const SPAN_NEAR := 240.0
const SPAN_FAR := 3200.0
const SPAN_START := 768.0

## Height shading. The sea is flat and dark, the shore is pale, and the land
## climbs from grass into rock — the same order the world itself uses, so the
## pool reads as the country you just walked over.
const DEEP := Color(0.06, 0.13, 0.24)
const SHALLOW := Color(0.16, 0.35, 0.46)
const SHORE := Color(0.72, 0.68, 0.48)
const LOW := Color(0.24, 0.42, 0.22)
const HIGH := Color(0.52, 0.50, 0.40)
const PEAK := Color(0.82, 0.82, 0.86)
const ROOF := 26.0

## The pins, and the two switches over them. Villages and creatures are drawn
## as marks and never as models: a map that renders anybody is a second world
## being simulated for the sake of a dot.
const PIN_HOME := Color(1.0, 0.86, 0.45)
const PIN_FAITHFUL := Color(0.55, 0.85, 1.0)
const PIN_OTHER := Color(0.85, 0.55, 0.5)
const PIN_LOST := Color(0.45, 0.45, 0.5)
const PIN_BEAST := Color(0.9, 0.45, 0.95)
const PIN_YOU := Color(1.0, 1.0, 1.0)

## THE FOG, how far a dimmed cell is pulled toward it, and how close a finger
## has to land to count as touching a pin — generous, because a village is a
## dot and a thumb is not.
const FOG := Color(0.09, 0.10, 0.14)
const DIMMED := 0.45
const PIN_REACH := 18.0

## How far past the edge of the known world the scroll may drift, in chunks:
## enough to see the coast you are standing on, not enough to wander.
const FOG_MARGIN := 2

var world_gen: WorldGen

var show_villages := true
var show_creatures := true

## Where the pins landed on the last paint — {at, spot, name} — so a touch can
## find them without walking the village list again in the input handler.
var _pins: Array = []

var _img: Image
var _tex: ImageTexture
## Where the window is centred, in world metres, and how wide it is.
var _at := Vector2.ZERO
var _span := SPAN_START
## The row the raising has reached, and the settings the rows so far were
## raised at — a scroll mid-raise must start the water over or the image is
## half one place and half another.
var _row := 0
var _raised_at := Vector2.ZERO
var _raised_span := 0.0
var _dragging := false


func _ready() -> void:
	custom_minimum_size = Vector2(220, 220)
	_img = Image.create(GRID, GRID, false, Image.FORMAT_RGB8)
	_img.fill(DEEP)
	_tex = ImageTexture.create_from_image(_img)
	set_process(true)


## THE IMAGE IN THE WATER, for the room to lay on its own well. The same
## ImageTexture this Control draws, so the disc across the room and the crisp
## map you lean over can never be showing two different worlds.
func water() -> Texture2D:
	return _tex


## Centre the pool on whatever the god is looking at, and raise the water
## again. Called every time the door is opened.
func look_again() -> void:
	var here := GameState.camera_focus
	if is_finite(here.x) and is_finite(here.z):
		_at = Vector2(here.x, here.z)
	_restart()


## THE SCROLL STOPS AT THE EDGE OF THE FOG — clamped to the box the known cells
## fit in, with a couple of chunks of slack so the coast you are standing on is
## visible, and never enough to drift into country that is not there.
func _restart() -> void:
	if world_gen != null and is_instance_valid(world_gen):
		var box := world_gen.known_bounds()
		var edge := float(FOG_MARGIN) * WorldGen.CHUNK_SIZE
		var lo := Vector2(box.position) * WorldGen.CHUNK_SIZE
		var hi := Vector2(box.end) * WorldGen.CHUNK_SIZE
		_at.x = clampf(_at.x, lo.x - edge, hi.x + edge)
		_at.y = clampf(_at.y, lo.y - edge, hi.y + edge)
	_row = 0
	_raised_at = _at
	_raised_span = _span


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _row < GRID:
		_raise_rows()
	# The pins move with the world whether or not the water is still.
	queue_redraw()


## RAISE A FEW ROWS. One height lookup and one biome lookup per pixel, which is
## why this is rationed rather than done in one go.
func _raise_rows() -> void:
	if world_gen == null or not is_instance_valid(world_gen):
		_row = GRID
		return
	var metres := _raised_span / float(GRID)
	var left := _raised_at.x - _raised_span * 0.5
	var top := _raised_at.y - _raised_span * 0.5
	var last := mini(_row + ROWS_PER_FRAME, GRID)
	while _row < last:
		var z := top + (float(_row) + 0.5) * metres
		for x in GRID:
			var wx := left + (float(x) + 0.5) * metres
			# THE FOG FIRST, and before the height is even asked for: an
			# unvisited cell costs nothing to draw and must not be drawn.
			var standing := world_gen.knows(WorldGen.cell_of(wx, z))
			if standing == 0:
				_img.set_pixel(x, _row, FOG)
				continue
			var tint := _tint(world_gen.seeded_height_at(wx, z))
			if standing == WorldGen.SEEN:
				tint = tint.lerp(FOG, 1.0 - DIMMED)
			_img.set_pixel(x, _row, tint)
		_row += 1
	_tex.update(_img)


## WHAT A HEIGHT LOOKS LIKE FROM ABOVE. Bands rather than one long gradient,
## because a single lerp from sea to peak makes every hill the same brown and
## loses the coastline, which is the one line on a map that matters.
static func _tint(h: float) -> Color:
	if h < WorldGen.WATER_LEVEL - 3.0:
		return DEEP
	if h < WorldGen.WATER_LEVEL:
		return SHALLOW.lerp(DEEP, clampf(-h / 3.0, 0.0, 1.0))
	if h < WorldGen.WATER_LEVEL + 0.6:
		return SHORE
	var up := clampf(h / ROOF, 0.0, 1.0)
	if up < 0.5:
		return LOW.lerp(HIGH, up * 2.0)
	return HIGH.lerp(PEAK, (up - 0.5) * 2.0)


func _draw() -> void:
	var side := minf(size.x, size.y)
	var box := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
	draw_texture_rect(_tex, box, false, Color(1, 1, 1, _settled()))
	# The rim of the basin.
	draw_rect(box, Color(0.65, 0.6, 0.45, 0.5), false, 2.0)
	if show_villages:
		_draw_villages(box)
	if show_creatures:
		_draw_creatures(box)
	_draw_you(box)
	_draw_scale(box)


## How far the water has gone still, 0..1 — the image fades in as it raises
## rather than appearing a band at a time.
func _settled() -> float:
	return clampf(float(_row) / float(GRID), 0.15, 1.0)


## World metres to a point in the basin, and whether it is in the basin at all.
func _spot(box: Rect2, world: Vector2) -> Vector2:
	var off := (world - _raised_at) / _raised_span + Vector2(0.5, 0.5)
	return box.position + off * box.size


func _inside(box: Rect2, at: Vector2) -> bool:
	return box.grow(-1.0).has_point(at)


func _draw_villages(box: Rect2) -> void:
	_pins.clear()
	# The towns that exist right now, as nodes.
	for n in get_tree().get_nodes_in_group("village"):
		var town := n as Village
		if town == null or not is_instance_valid(town):
			continue
		var at := _spot(box, Vector2(town.global_position.x, town.global_position.z))
		if not _inside(box, at):
			continue
		var tint := PIN_OTHER
		if town.is_player_home:
			tint = PIN_HOME
		elif town.converted:
			tint = PIN_FAITHFUL
		# A town is drawn at the size of its people: a hamlet and a city should
		# not be the same dot.
		var r := clampf(2.5 + float(town.population()) * 0.22, 3.0, 9.0)
		draw_circle(at, r, tint)
		draw_arc(at, r + 1.5, 0.0, TAU, 18, tint * Color(1, 1, 1, 0.5), 1.0)
		_pins.append({"at": at, "spot": town.global_position,
			"name": town.village_name})
	# And the towns you have met and left behind, which are memory and not
	# nodes. Drawn hollow, because that is honestly what they are.
	for entry: Variant in SaveGame.village_memory:
		if not entry is Dictionary:
			continue
		var pos: Variant = (entry as Dictionary).get("pos", [])
		if not pos is Array or (pos as Array).size() < 2:
			continue
		var flat := Vector2(float((pos as Array)[0]), float((pos as Array)[1]))
		var at := _spot(box, flat)
		if not _inside(box, at):
			continue
		draw_arc(at, 4.0, 0.0, TAU, 16, PIN_LOST, 1.5)
		# A remembered town has no node and so no ground height; the world will
		# put the camera down on whatever is actually there.
		_pins.append({"at": at, "spot": Vector3(flat.x, 0.0, flat.y),
			"name": String((entry as Dictionary).get("name", "a village"))})


func _draw_creatures(box: Rect2) -> void:
	for n in get_tree().get_nodes_in_group("creature"):
		var beast := n as Node3D
		if beast == null or not is_instance_valid(beast):
			continue
		var at := _spot(box, Vector2(beast.global_position.x, beast.global_position.z))
		if not _inside(box, at):
			continue
		draw_circle(at, 5.0, PIN_BEAST)
		draw_arc(at, 8.0, 0.0, TAU, 20, PIN_BEAST * Color(1, 1, 1, 0.6), 1.5)


## WHERE YOU ARE LOOKING, which is not a creature and not a village and is the
## thing a player actually orients by.
func _draw_you(box: Rect2) -> void:
	var here := GameState.camera_focus
	if not is_finite(here.x) or not is_finite(here.z):
		return
	var at := _spot(box, Vector2(here.x, here.z))
	if not _inside(box, at):
		return
	draw_line(at - Vector2(7, 0), at + Vector2(7, 0), PIN_YOU, 1.0)
	draw_line(at - Vector2(0, 7), at + Vector2(0, 7), PIN_YOU, 1.0)


## A bar and a number, because a map with no scale is a picture.
func _draw_scale(box: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var bar := box.size.x * 0.25
	var metres := _raised_span * 0.25
	var foot := box.position + Vector2(10.0, box.size.y - 12.0)
	draw_line(foot, foot + Vector2(bar, 0.0), Color(1, 1, 1, 0.75), 2.0)
	draw_string(font, foot + Vector2(0.0, -5.0), "%d m" % int(metres),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.75))


## SCROLLING AND ZOOMING. Both restart the raising, which is what makes a drag
## feel like water being disturbed rather than like a map tearing.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		match click.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(0.8)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(1.25)
			MOUSE_BUTTON_LEFT:
				# A PRESS ON A PIN IS A JOURNEY, not the start of a drag. Tested
				# on press rather than release so that leaving the temple never
				# depends on holding still — the whole point of this is the
				# player who is lost, and a lost player is not a steady one.
				if click.pressed and _touched_pin(click.position):
					return
				_dragging = click.pressed
	elif event is InputEventMouseMotion and _dragging:
		var side := maxf(minf(size.x, size.y), 1.0)
		_at -= (event as InputEventMouseMotion).relative / side * _span
		_restart()
	elif event is InputEventMagnifyGesture:
		_zoom(1.0 / maxf((event as InputEventMagnifyGesture).factor, 0.01))
	elif event is InputEventPanGesture:
		var side := maxf(minf(size.x, size.y), 1.0)
		_at += (event as InputEventPanGesture).delta / side * _span * 24.0
		_restart()


## Did that land on a pin? Nearest wins, so two towns close together on a
## zoomed-out well still resolve to whichever you actually meant.
func _touched_pin(where: Vector2) -> bool:
	var best: Dictionary = {}
	var best_d := PIN_REACH
	for pin: Dictionary in _pins:
		var d: float = (pin["at"] as Vector2).distance_to(where)
		if d < best_d:
			best_d = d
			best = pin
	if best.is_empty():
		return false
	travel_to.emit(best["spot"] as Vector3)
	return true


func _zoom(by: float) -> void:
	_span = clampf(_span * by, SPAN_NEAR, SPAN_FAR)
	_restart()
