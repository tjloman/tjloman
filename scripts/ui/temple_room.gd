class_name TempleRoom
extends SubViewport
## THE HEAVENLY TEMPLE: the inside of a cube, and the only room in the game.
##
## Six sides, each about the geometry of one ordinary chunk of ground — a floor
## with the well cut into it, a ceiling with the chandelier, and four walls a
## god turns to face. The whole thing comes to roughly eight thousand
## triangles, which is under three creatures (the beast alone is 2,880, see
## tools/tri_budget.py), and it is drawn while the world is PAUSED AND CULLED,
## so it does not add to a scene — it replaces one.
##
## IT HAS ITS OWN WORLD. `own_world_3d` gives the room its own lights, its own
## environment and its own sky, which is the difference between a temple and a
## shed built somewhere on the map: the game's sun does not set in here, the
## fog does not reach, and nothing the room lights can touch anything outside
## it. The cost of that isolation is one render target, paid for by zeroing the
## main camera's cull mask on the way in — see Temple.
##
## NOTHING IS WRITTEN ON THE WALLS. Text on a surface at an angle goes soft,
## and a wall carrying a viewport texture is a fixed resolution being
## magnified; on a tablet held at arm's length it is unreadable. So the room
## gives the PLACE — you turn, and the north wall is where the dead are counted
## — and the words resolve crisply in 2D over it. See TempleCharts.

## How big the room is, in metres, and where the god's eye sits in it.
const HALF := 8.0
const TALL := 9.0
const EYE := 2.6

## How finely each side is cut. 23 subdivisions is 24x24 quads, 1,152
## triangles — the same as one near chunk of ground, which is the budget this
## room was designed to.
const CUT := 23

## The well: how wide the rim is, how far the water sits below it, and how big
## the water disc is. Wide enough to read a map in from across the room.
const WELL_R := 2.3
const WELL_DEEP := 0.55
const RIM_THICK := 0.22

## How fast the view swings from one wall to the next. Eased rather than
## snapped: a room that teleports you to face a wall is a menu with a skybox.
const SWING := 3.2

## LEANING OVER THE WELL IS A STEP AS WELL AS A TILT. From the middle of the
## room the well is DIRECTLY UNDERFOOT, and the only way to look at it from
## there is straight down — which fills the screen with water and shows none of
## the room. So the god walks to the rim and leans: back to the near edge, and
## down far enough that the shaft, the far rim and the world in the bottom are
## all in frame. Worked from the geometry — at EYE high and RIM_STAND back, a
## LEAN of this much puts the eye line on the floor about 1.9m ahead, which is
## inside a well of radius WELL_R.
const LEAN := -0.95
const RIM_STAND := 2.6

## The stone, the gilding, and the light. One palette, because a temple that
## does not agree with itself is a lobby.
const STONE := Color(0.20, 0.19, 0.24)
const STONE_LOW := Color(0.11, 0.10, 0.14)
const GOLD := Color(0.72, 0.56, 0.26)
const CANDLE := Color(1.0, 0.82, 0.48)
const DEEP_SKY := Color(0.03, 0.035, 0.06)

## Which way each of the four walls is, in radians, indexed as Temple's doors
## are. The well is not in here: it is a floor, and looking at it is a pitch.
const FACING: Array[float] = [0.0, PI * 0.5, PI, PI * 1.5]

var camera: Camera3D

var _yaw := 0.0
var _pitch := 0.0
var _want_yaw := 0.0
var _want_pitch := 0.0
var _want_at := Vector3(0.0, EYE, 0.0)
var _water: MeshInstance3D
var _chandelier: Node3D


func _ready() -> void:
	# THE ROOM KEEPS DRAWING WHILE THE WORLD IS STOPPED. That is the whole
	# point of it, and a SubViewport inherits the pause like anything else.
	process_mode = Node.PROCESS_MODE_ALWAYS
	own_world_3d = true
	transparent_bg = false
	# DRAWING NOTHING UNTIL SOMEBODY IS IN HERE. A SubViewport does not care
	# whether the CanvasLayer showing it is visible: left on UPDATE_ALWAYS this
	# would render a second full 3D scene every frame of the entire game, for a
	# room nobody has opened. Temple turns it on at the door. See `wake`.
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	msaa_3d = Quality.msaa_3d()
	_build_camera()
	_build_shell()
	_build_well()
	_build_chandelier()
	_build_lights()


## OPEN AND SHUT THE ROOM'S EYE. The whole cost of the temple is here: while
## this is false nothing in the room is drawn at all, and the meshes sitting in
## memory cost nothing per frame.
func wake(on: bool) -> void:
	render_target_update_mode = SubViewport.UPDATE_ALWAYS if on \
		else SubViewport.UPDATE_DISABLED
	if on:
		# Arrive already facing the right way rather than swinging into place
		# from wherever the last visit left off.
		camera.position = _want_at
		camera.rotation = Vector3(_want_pitch, _want_yaw, 0.0)
		_pitch = _want_pitch
		_yaw = _want_yaw


func _process(delta: float) -> void:
	if camera == null or not is_instance_valid(camera):
		return
	if render_target_update_mode == SubViewport.UPDATE_DISABLED:
		return
	var step := minf(SWING * delta, 1.0)
	_yaw += wrapf(_want_yaw - _yaw, -PI, PI) * step
	_pitch = lerpf(_pitch, _want_pitch, step)
	camera.position = camera.position.lerp(_want_at, step)
	camera.rotation = Vector3(_pitch, _yaw, 0.0)
	if _chandelier != null and is_instance_valid(_chandelier):
		_chandelier.rotation.y += delta * 0.06


## Resize with the window. Called by Temple, which is the only thing that knows
## how big the screen is — a SubViewport has no opinion about it.
func fit(to: Vector2i) -> void:
	# The room is rendered at the same fraction of native the world is, so a
	# phone that draws the country at three quarters draws the temple at three
	# quarters and the two feel like one game.
	var scaled := Vector2(to) * Quality.render_scale()
	size = Vector2i(maxi(int(scaled.x), 64), maxi(int(scaled.y), 64))


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.position = Vector3(0.0, EYE, 0.0)
	camera.fov = 68.0
	camera.near = 0.05
	camera.far = 60.0
	var air := Environment.new()
	air.background_mode = Environment.BG_COLOR
	air.background_color = DEEP_SKY
	air.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	air.ambient_light_color = Color(0.35, 0.33, 0.42)
	air.ambient_light_energy = 0.55
	# A little bloom on the candles and the water, and nothing else: this is a
	# dark room with a few bright things in it, which is exactly the case glow
	# was made for.
	air.glow_enabled = Quality.glow()
	air.glow_intensity = 0.55
	air.glow_bloom = 0.15
	camera.environment = air
	add_child(camera)


## THE SIX SIDES. Each is one PlaneMesh cut to a chunk's fineness, turned so
## its face looks INWARD — the room is the inside of a solid, not a box seen
## from outside, and a wall lit from behind is a wall that is not there.
func _build_shell() -> void:
	_side(PlaneMesh.FACE_Y, Vector3(0.0, 0.0, 0.0), 0.0, STONE_LOW, "floor")
	_side(PlaneMesh.FACE_Y, Vector3(0.0, TALL, 0.0), PI, STONE, "ceiling")
	for i in FACING.size():
		# Walls stand on the -Z face and are turned about the room's centre, so
		# the four of them are one piece of code and the door order and the
		# wall order cannot drift apart.
		_side(PlaneMesh.FACE_Z, Vector3(0.0, TALL * 0.5, -HALF),
			FACING[i], STONE, "wall%d" % i, true)


## One side. `turn` is about X for the floor and ceiling (to flip them over)
## and about Y for the walls (to place them), which is the only thing the
## `spun` flag decides.
func _side(facing: PlaneMesh.Orientation, at: Vector3, turn: float,
		tint: Color, called: String, spun := false) -> void:
	var plane := PlaneMesh.new()
	plane.orientation = facing
	plane.size = Vector2(HALF * 2.0, HALF * 2.0 if facing == PlaneMesh.FACE_Y else TALL)
	plane.subdivide_width = CUT
	plane.subdivide_depth = CUT
	var slab := MeshInstance3D.new()
	slab.name = called
	slab.mesh = plane
	slab.material_override = _stone(tint)
	if spun:
		var spin := Transform3D(Basis(Vector3.UP, turn), Vector3.ZERO)
		slab.transform = spin * Transform3D(Basis.IDENTITY, at)
	else:
		slab.position = at
		slab.rotation.x = turn
	add_child(slab)


func _stone(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = 0.85
	mat.metallic = 0.0
	return mat


## THE WELL, in the middle of the floor: a gilded rim, a shaft of shadow, and
## the world lying in the water at the bottom of it.
##
## The water is a disc and not a screen. Seen from across the room it is a lit
## pool with a map in it; the crisp, touchable version of that map is the 2D
## one Temple lays over it when you lean in. One image, two presentations —
## see TemplePool.water.
func _build_well() -> void:
	var rim := MeshInstance3D.new()
	rim.name = "rim"
	var ring := TorusMesh.new()
	ring.inner_radius = WELL_R
	ring.outer_radius = WELL_R + RIM_THICK
	ring.rings = 24
	ring.ring_segments = 8
	rim.mesh = ring
	var gilt := StandardMaterial3D.new()
	gilt.albedo_color = GOLD
	gilt.metallic = 0.85
	gilt.roughness = 0.35
	rim.material_override = gilt
	rim.position = Vector3(0.0, 0.08, 0.0)
	add_child(rim)

	# The shaft, so the well has a depth rather than being a coin on the floor.
	var shaft := MeshInstance3D.new()
	shaft.name = "shaft"
	var tube := CylinderMesh.new()
	tube.top_radius = WELL_R
	tube.bottom_radius = WELL_R
	tube.height = WELL_DEEP
	tube.radial_segments = 32
	tube.rings = 0
	tube.cap_top = false
	tube.cap_bottom = false
	shaft.mesh = tube
	var inside := _stone(Color(0.05, 0.05, 0.08))
	inside.cull_mode = BaseMaterial3D.CULL_FRONT   # we are looking INTO it
	shaft.material_override = inside
	shaft.position = Vector3(0.0, -WELL_DEEP * 0.5 + 0.06, 0.0)
	add_child(shaft)

	_water = MeshInstance3D.new()
	_water.name = "water"
	var disc := CylinderMesh.new()
	disc.top_radius = WELL_R - 0.04
	disc.bottom_radius = WELL_R - 0.04
	disc.height = 0.02
	disc.radial_segments = 40
	disc.rings = 0
	disc.cap_bottom = false
	_water.mesh = disc
	_water.position = Vector3(0.0, -WELL_DEEP + 0.08, 0.0)
	add_child(_water)


## WHAT THE WATER HOLDS. Handed in by Temple once TemplePool has raised it, and
## re-handed whenever the pool is rebuilt — the same ImageTexture, so the room
## and the 2D map can never show two different worlds.
func show_world(image: Texture2D) -> void:
	if _water == null or not is_instance_valid(_water):
		return
	var skin := StandardMaterial3D.new()
	skin.albedo_texture = image
	skin.roughness = 0.25
	skin.metallic = 0.1
	# The map is the brightest thing in the room and lights the god's face from
	# below, which is most of why leaning over a well reads as leaning over a
	# well. Emission carries that without a second light.
	skin.emission_enabled = true
	skin.emission_texture = image
	skin.emission_energy_multiplier = 0.9
	_water.material_override = skin


## THE CHANDELIER. A gilded ring of candles, turning slowly, hung high enough
## that it is something you look up at rather than something in the way.
func _build_chandelier() -> void:
	_chandelier = Node3D.new()
	_chandelier.name = "chandelier"
	_chandelier.position = Vector3(0.0, TALL - 2.2, 0.0)
	add_child(_chandelier)

	var hoop := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 1.5
	ring.outer_radius = 1.62
	ring.rings = 16
	ring.ring_segments = 6
	hoop.mesh = ring
	var gilt := StandardMaterial3D.new()
	gilt.albedo_color = GOLD
	gilt.metallic = 0.9
	gilt.roughness = 0.3
	hoop.material_override = gilt
	_chandelier.add_child(hoop)

	var flame := StandardMaterial3D.new()
	flame.albedo_color = CANDLE
	flame.emission_enabled = true
	flame.emission = CANDLE
	flame.emission_energy_multiplier = 3.0
	for i in 8:
		var ball := MeshInstance3D.new()
		var bead := SphereMesh.new()
		bead.radius = 0.10
		bead.height = 0.26
		bead.radial_segments = 6
		bead.rings = 3
		ball.mesh = bead
		ball.material_override = flame
		var turn := TAU * float(i) / 8.0
		ball.position = Vector3(sin(turn) * 1.56, 0.16, cos(turn) * 1.56)
		_chandelier.add_child(ball)


## TWO LIGHTS AND NO SUN. Warm from the chandelier, cold from the water — so
## the room is lit the way a room with a hole in the floor onto the world would
## be, and a god leaning over the well is underlit by their own country.
func _build_lights() -> void:
	var candles := OmniLight3D.new()
	candles.light_color = CANDLE
	candles.light_energy = 2.4
	candles.omni_range = 22.0
	candles.shadow_enabled = false
	candles.position = Vector3(0.0, TALL - 2.4, 0.0)
	add_child(candles)

	var below := OmniLight3D.new()
	below.light_color = Color(0.55, 0.78, 1.0)
	below.light_energy = 1.6
	below.omni_range = 9.0
	below.shadow_enabled = false
	below.position = Vector3(0.0, -WELL_DEEP + 0.5, 0.0)
	add_child(below)


## TURN TO FACE SOMETHING. `which` is -1 for the well — the god steps to the
## rim and leans over it — and 0..3 for the four walls, in the same order
## Temple's doors are listed.
func face(which: int) -> void:
	if which < 0:
		_want_pitch = LEAN
		# Step back to the rim, keeping whichever way you were already facing,
		# so opening the well does not also spin you round.
		_want_at = Vector3(sin(_want_yaw), 0.0, cos(_want_yaw)) * RIM_STAND
		_want_at.y = EYE
		return
	_want_pitch = 0.0
	_want_at = Vector3(0.0, EYE, 0.0)
	_want_yaw = FACING[clampi(which, 0, FACING.size() - 1)]

