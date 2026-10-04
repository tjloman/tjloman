class_name ShadeGround
extends RefCounted
## THE GROUND UNDER THE SHADOWS, read once for all of them.
##
## A baked shadow was laid on a flat plane through its caster's foot, so on any
## slope it hung in the air on the downhill side and was swallowed by the rise
## on the other. The ground is what it has to lie on — so the ground around the
## camera is read into a small height map (SIZE x SIZE texels, CELL metres
## each) and handed to the shadow shader, which sets every vertex of every
## shadow down on the height under it. One read of the land for every shadow in
## view, instead of a read per shadow per step.
##
## READ A FEW ROWS A FRAME, never all at once: a map is SIZE * SIZE drawn-ground
## lookups, sliced to a budget of BUDGET_USEC a frame, and shown only when it is
## whole. A new one is begun every REREAD seconds — the beat the sun moves on
## (Shade.STEP_SECONDS), so the land under the shadows is fresh each time they
## turn — or sooner if the camera has wandered towards the edge of the last.

## Texels a side, and metres a texel: 96 x 2m is 192m across, the far edge of a
## walker's shadow on any tier (Quality.shadow_reach) with room to spare. Two
## metres is the near ground's own cut (Quality.chunk_cells), so the map holds
## every corner the drawn land has.
const SIZE := 96
const CELL := 2.0
## How long a frame may spend reading, in microseconds.
const BUDGET_USEC := 1200
## How often a fresh map is begun, and how far the camera may stray from the
## middle of the shown one before a fresh one is begun at once.
const REREAD := 4.0
const STRAY := 32.0

var _heights := PackedFloat32Array()
var _texture: ImageTexture = null
var _row := -1                    # the row being read; -1 when idle
var _corner := Vector2.ZERO       # world x,z of the corner being read
var _shown_middle := Vector2.INF  # middle of the map the shader has
var _since := REREAD


## A frame's worth: begin a map if one is due, read rows to the budget, and
## hand it over when it is whole. True on the frame a new map is shown.
func step(world: WorldGen, eye: Vector3, delta: float) -> bool:
	if world == null:
		return false
	_since += delta
	var here := Vector2(eye.x, eye.z)
	if _row < 0:
		if _since < REREAD and here.distance_to(_shown_middle) < STRAY:
			return false
		_since = 0.0
		_row = 0
		var half := SIZE * CELL * 0.5
		_corner = Vector2(snappedf(here.x - half, CELL), snappedf(here.y - half, CELL))
		_heights.resize(SIZE * SIZE)
	var began := Time.get_ticks_usec()
	while _row < SIZE:
		# Sample i sits in the MIDDLE of texel i, so the shader's uv is simply
		# (x - corner) / span.
		var z := _corner.y + (float(_row) + 0.5) * CELL
		var at := _row * SIZE
		for i in SIZE:
			# Water stands over the lakebed: a shadow on a lake lies on the water.
			_heights[at + i] = maxf(
				world.drawn_height_at(_corner.x + (float(i) + 0.5) * CELL, z), WorldGen.WATER_LEVEL)
		_row += 1
		if Time.get_ticks_usec() - began > BUDGET_USEC:
			return false
	_show()
	return true


## The map the shader reads: its corner, its span, and whether there is one.
func area() -> Vector4:
	if _texture == null:
		return Vector4.ZERO
	return Vector4(_corner.x, _corner.y, SIZE * CELL, 1.0)


func _show() -> void:
	var image := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RF,
		_heights.to_byte_array())
	if _texture == null:
		_texture = ImageTexture.create_from_image(image)
	else:
		_texture.update(image)
	_row = -1
	_shown_middle = _corner + Vector2.ONE * (SIZE * CELL * 0.5)
	RenderingServer.global_shader_parameter_set(&"shade_ground", _texture)
	RenderingServer.global_shader_parameter_set(&"shade_ground_area", area())
