class_name Temple
extends CanvasLayer
## THE TEMPLE, reached by holding the sun.
##
## Every option, every save, every number this game knows sits behind one
## gesture aimed at the one part of the screen that has never meant anything:
## the disk of the sun by day, of the moon by night. No button, no corner tab,
## no burger. The HUD does not grow.
##
## WHY THE DISK AND NOT THE SKY. A long press on bare sky is already taken —
## it is what opens the rune-casting session under a thumb (DivineHand.
## OPEN_HOLD), and on a mouse it is how you wind a throw up into the air. The
## sky is the busiest empty space in the game. The disks are genuinely unused,
## and the cone below is deliberately far wider than the sun actually looks
## (about seven degrees against its real half-degree) so that a thumb can find
## it — nothing else up there competes, so a generous target costs nothing.
##
## IT HOLDS THE WORLD STILL, and this is how a game that never had a pause gets
## one. There was nowhere to put a pause before — a god game has no menu bar,
## and stopping the world from the HUD would have meant a button on it.
##
## THAT WAS NOT FREE. The tree had only ever been paused on the opening screen,
## before there was a creature to get anything wrong about, so every "how long
## since..." in the simulation was measured against Time.get_ticks_msec(),
## which does not stop. See GameState.clock and tools/pause_walk.py; neither
## would exist without this door.
##
## WHAT YOU ARE ACTUALLY IN is the inside of a cube — TempleRoom — rendered in
## its own world while the real one is paused and culled to nothing, so the
## temple does not add to a scene, it replaces one. The room gives the PLACE:
## you turn, and the north wall is where the dead are counted. THE WORDS ARE
## 2D over it, because text on a surface at an angle goes soft and a wall
## carrying a viewport texture is a fixed resolution being magnified — on a
## tablet at arm's length it is unreadable.

## Hold this long on a disk to open. Longer than DivineHand.OPEN_HOLD (0.45)
## on purpose: opening the whole temple by accident is a worse mistake than
## opening the rune session by accident, and the gesture should feel deliberate.
const DISK_HOLD := 0.85

## How wide a cone around the true direction of the sun or moon still counts as
## pressing it, in radians. The sun's actual disk is about half a degree; this
## is fourteen times that, because a thumb is about this wide at arm's length
## and there is nothing else in the sky to hit by mistake.
const DISK_GRAB := deg_to_rad(7.0)

## Set false to let the world run on while the temple is open — everything that
## measures an interval now reads GameState.clock and is correct either way.
const HOLDS_THE_WORLD := true

## THE ROOMS, in the order the walls stand in. The first is the WELL and is not
## a wall at all — it is the floor, and opening it leans the god over it. The
## other four are the four walls, so this table IS the compass of the place and
## a row added in the middle silently re-points every wall.
const DOORS: Array[Array] = [
	["The Well", "◎", "_room_pool"],
	["The Chronicle", "𝍨", "_room_chronicle"],
	["The Reign", "☉", "_room_reign"],
	["Rites", "⚙", "_room_rites"],
	["Creatures", "☙", "_room_creatures"],
]

## How much of the screen a wall's panel covers, as a fraction of each side.
## Short of the whole, so the room is visible around what you are reading and
## you can still tell which way you are facing.
##
## BOTH numbers matter, and the height is not decoration: the panel sits in a
## CenterContainer, which hands its child the child's MINIMUM size and ignores
## size flags outright — so a panel given only a width collapses to the height
## of nothing and takes the chart inside it with it.
const PANEL_WIDE := 0.92
const PANEL_TALL := 0.66
const WELL_WIDE := 0.74
const WELL_TALL := 0.62

var world_gen: WorldGen
var profiles: ProfileMenu
var camera_rig: CameraRig

var _room: TempleRoom
var _view: TextureRect
var _pool: TemplePool
var _panel: PanelContainer
var _panel_body: VBoxContainer
var _title: Label
var _doors: Array[Button] = []
var _open_door := 0
## Did THIS door stop the world? The opening screen and the profile menu pause
## the tree too, and a temple that unpauses on the way out regardless would
## start the world running behind whichever of them is still up.
var _held_it := false
## What the world's camera was drawing before we hid it behind a temple.
var _was_culling := 0xFFFFF


## IS THE PLAYER POINTING AT THE SUN OR THE MOON? Returns "sun", "moon" or "",
## and is the whole of the doorway test.
##
## The disks are not nodes and cannot be raycast — they are two
## DirectionalLight3D pointing at the world plus a shader that paints where
## they point — so this compares the ray the finger casts against the direction
## each light comes FROM. A light's -Z is the way it shines, so the disk itself
## sits along +Z.
static func disk_at(cam: Camera3D, screen_pos: Vector2) -> String:
	if cam == null or not is_instance_valid(cam):
		return ""
	var ray := cam.project_ray_normal(screen_pos)
	# Below the horizon there is no sky, whatever the arithmetic says: the sun
	# is still a direction when it is under your feet.
	if ray.y < 0.0:
		return ""
	var best := ""
	var best_dot := cos(DISK_GRAB)
	for n in cam.get_tree().get_nodes_in_group("sky_disks"):
		var light := n as DirectionalLight3D
		if light == null or not is_instance_valid(light) or not light.visible:
			continue
		# A light that is not lighting anything has no disk to press.
		if light.light_energy <= 0.01:
			continue
		var toward := light.global_transform.basis.z.normalized()
		if toward.y < 0.0:
			continue
		var d := ray.dot(toward)
		if d > best_dot:
			best_dot = d
			best = "moon" if light.light_color.b > light.light_color.r else "sun"
	return best


func _ready() -> void:
	layer = 45
	# The temple is reachable while the world is held for any other reason —
	# and, since it holds the world itself, while it is holding it for this one.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	get_viewport().size_changed.connect(_fit)


## F6, for anyone who would rather not hold the sun — and for a desktop player
## who has the sun behind them. The gesture is the front door; this is the one
## a keyboard has.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("toggle_temple"):
		return
	get_viewport().set_input_as_handled()
	toggle()


func _build() -> void:
	_room = TempleRoom.new()
	add_child(_room)

	# THE ROOM ITSELF, behind everything and deaf to the finger: you turn by
	# choosing a door, not by poking the wall.
	_view = TextureRect.new()
	_view.texture = _room.get_texture()
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)

	var frame := MarginContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	# ONE PLACE THE SIDE GUTTER IS SET, and never a `padding` shorthand that
	# would zero it. A phone is 400px across and nothing must touch glass.
	frame.add_theme_constant_override("margin_left", 16)
	frame.add_theme_constant_override("margin_right", 16)
	frame.add_theme_constant_override("margin_top", 18)
	frame.add_theme_constant_override("margin_bottom", 18)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	frame.add_child(column)
	column.add_child(_build_lintel())
	column.add_child(_build_doors())

	# WHAT IS BEING READ, laid over the wall being faced. Translucent, so the
	# room shows through and you never lose track of where you are standing.
	var middle := CenterContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(middle)

	_panel = PanelContainer.new()
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_theme_stylebox_override("panel", _vellum())
	middle.add_child(_panel)

	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 14)
	inner.add_theme_constant_override("margin_right", 14)
	inner.add_theme_constant_override("margin_top", 10)
	inner.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(inner)

	_panel_body = VBoxContainer.new()
	_panel_body.add_theme_constant_override("separation", 8)
	inner.add_child(_panel_body)

	_pool = TemplePool.new()
	_pool.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pool.travel_to.connect(_go_there)
	_panel_body.add_child(_pool)


## The pool is kept ALIVE and merely taken out of the tree while another room
## is open, because it holds a raised terrain image that costs real
## milliseconds. Out of the tree it is nobody's child, so it has to be let go
## by hand or it outlives the temple as an orphan.
func _exit_tree() -> void:
	if _pool != null and is_instance_valid(_pool) and _pool.get_parent() == null:
		_pool.queue_free()


## The panel's ground: dark enough to read white text off, translucent enough
## that the stone behind it still reads as stone.
func _vellum() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.05, 0.08, 0.82)
	box.border_color = Color(0.72, 0.56, 0.26, 0.55)
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(0)
	return box


func _build_lintel() -> Control:
	var row := HBoxContainer.new()
	_title = Label.new()
	_title.text = "The Temple"
	_title.add_theme_font_size_override("font_size", 22)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_title)
	var shut := Button.new()
	shut.text = "  Leave  "
	shut.pressed.connect(close)
	row.add_child(shut)
	return row


## THE DOORS. A flow container rather than a ring around the well: a ring is
## the right picture and the wrong widget — at 400px across, five doors around
## a circle leave a well the size of a coin. This wraps to as many rows as the
## screen needs and goes to one line the moment there is room.
func _build_doors() -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	for i in DOORS.size():
		var door := Button.new()
		door.text = "%s  %s" % [DOORS[i][1], DOORS[i][0]]
		door.toggle_mode = true
		door.pressed.connect(_enter.bind(i))
		flow.add_child(door)
		_doors.append(door)
	return flow


## Size the room's render target to the window. The room is drawn at the same
## fraction of native the world is, so a phone that renders the country at
## three quarters renders the temple at three quarters.
func _fit() -> void:
	if _room != null and is_instance_valid(_room):
		_room.fit(get_viewport().get_visible_rect().size)


## OPEN. `why` is "sun" or "moon" and only changes the greeting — the temple is
## the same room at either hour.
func open(why := "sun") -> void:
	if visible:
		return
	visible = true
	_fit()
	# The room draws nothing until now, and stops again on the way out. See
	# TempleRoom.wake: a SubViewport does not stop for a hidden CanvasLayer.
	_room.wake(true)
	_held_it = HOLDS_THE_WORLD and not get_tree().paused
	if _held_it:
		get_tree().paused = true
	# THE WORLD STOPS BEING DRAWN AT ALL. The room covers the screen, so every
	# triangle of the country behind it is work thrown away — and a cull mask
	# of nothing is the cheapest way there is to say so. It changes no game
	# state, which is why it is safe to do to a camera somebody else owns.
	if camera_rig != null and is_instance_valid(camera_rig) \
			and camera_rig.camera != null:
		_was_culling = camera_rig.camera.cull_mask
		camera_rig.camera.cull_mask = 0
	_title.text = "The Temple" if why == "sun" else "The Temple, by moonlight"
	_enter(_open_door)


func close() -> void:
	visible = false
	_room.wake(false)
	if camera_rig != null and is_instance_valid(camera_rig) \
			and camera_rig.camera != null:
		camera_rig.camera.cull_mask = _was_culling
	if _held_it:
		get_tree().paused = false
	_held_it = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## WALK INTO ONE: turn to that wall, and put its words up over it. Every room
## is rebuilt on entry rather than kept alive behind the others — these are
## read once and closed, and a chart that goes on redrawing itself behind four
## other rooms is heat for nothing.
func _enter(which: int) -> void:
	_open_door = clampi(which, 0, DOORS.size() - 1)
	for i in _doors.size():
		_doors[i].set_pressed_no_signal(i == _open_door)
	# Door 0 is the floor. The rest are the walls, in order.
	_room.face(_open_door - 1)
	for child in _panel_body.get_children():
		# The pool is kept — it holds a built terrain image that costs real
		# milliseconds to raise, and rebuilding it every time somebody reads a
		# chart and comes back is the one thing here that would be felt.
		_panel_body.remove_child(child)
		if child != _pool:
			child.queue_free()
	var screen := get_viewport().get_visible_rect().size
	var wide := WELL_WIDE if _open_door == 0 else PANEL_WIDE
	var tall := WELL_TALL if _open_door == 0 else PANEL_TALL
	_panel.custom_minimum_size = Vector2(screen.x * wide, screen.y * tall)
	call(String(DOORS[_open_door][2]))


## THE WELL. The room already has the world lying in its water; this is the
## crisp, touchable copy of it laid over the same spot, which is what leaning
## in actually means.
func _room_pool() -> void:
	_pool.world_gen = world_gen
	_panel_body.add_child(_pool)
	_pool.look_again()
	_room.show_world(_pool.water())


func _room_chronicle() -> void:
	_panel_body.add_child(TempleCharts.new())


func _room_reign() -> void:
	var room := TempleReign.new()
	room.world_gen = world_gen
	_panel_body.add_child(room)


func _room_rites() -> void:
	_panel_body.add_child(TempleRites.new())


func _room_creatures() -> void:
	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "The creatures you have raised, and the saves they live in."
	_panel_body.add_child(note)
	var go := Button.new()
	go.text = "Open the profiles"
	go.pressed.connect(_open_profiles)
	_panel_body.add_child(go)


func _open_profiles() -> void:
	close()
	if profiles != null and is_instance_valid(profiles):
		profiles.open()


## A PIN WAS TOUCHED. Leave, and be standing over that village — the same door
## the village roster (V) uses, so there is one way to arrive somewhere and not
## two. This is the answer to the lost player, and it is the reason the well is
## worth more than a picture of the world.
func _go_there(spot: Vector3) -> void:
	close()
	if camera_rig != null and is_instance_valid(camera_rig):
		camera_rig.snap_to(spot)
