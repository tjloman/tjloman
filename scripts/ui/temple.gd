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
## IT DOES NOT PAUSE THE WORLD. A reflecting pool that shows a still frame is a
## screenshot; one that shows your villages moving while you read is the thing
## itself, and a god who steps into a temple has not stopped time. The cost is
## real — wolves do not wait while you read a chart — so `HOLDS_THE_WORLD`
## below is the one line that changes it, and it is a line not a rewrite.
##
## WHAT IS ACTUALLY HERE, for anyone reading this before the rest is built: the
## shell, the pool, and the doors. Each door is a Control handed to `_show`,
## so a new room is a new file and one row in DOORS — nothing here needs to
## know what a room contains.

## Hold this long on a disk to open. Longer than DivineHand.OPEN_HOLD (0.45)
## on purpose: opening the whole temple by accident is a worse mistake than
## opening the rune session by accident, and the gesture should feel deliberate.
const DISK_HOLD := 0.85

## How wide a cone around the true direction of the sun or moon still counts as
## pressing it, in radians. The sun's actual disk is about half a degree; this
## is fourteen times that, because a thumb is about this wide at arm's length
## and there is nothing else in the sky to hit by mistake.
const DISK_GRAB := deg_to_rad(7.0)

## Set true to hold the world still while the temple is open. See the header.
const HOLDS_THE_WORLD := false

## THE ROOMS. Title, the glyph that stands over the door, and the method that
## builds the room. Adding one is a row here and a builder below.
const DOORS: Array[Array] = [
	["The Pool", "◎", "_room_pool"],
	["The Chronicle", "𝍨", "_room_chronicle"],
	["The Reign", "☉", "_room_reign"],
	["Rites", "⚙", "_room_rites"],
	["Creatures", "☙", "_room_creatures"],
]

var world_gen: WorldGen
var profiles: ProfileMenu

var _backdrop: ColorRect
var _pool: TemplePool
var _room: PanelContainer
var _room_body: VBoxContainer
var _room_title: Label
var _doors: Array[Button] = []
var _open_door := 0


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
	# and if HOLDS_THE_WORLD is on, while it is holding it for this one.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


## F6, for anyone who would rather not hold the sun — and for a desktop player
## who has the sun behind them. The gesture is the front door; this is the one
## a keyboard has.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("toggle_temple"):
		return
	get_viewport().set_input_as_handled()
	toggle()


func _build() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.02, 0.03, 0.06, 0.72)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	var frame := MarginContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	# ONE PLACE THE SIDE GUTTER IS SET, and never a `padding` shorthand that
	# would zero it. A phone is 400px across and the pool must not touch glass.
	frame.add_theme_constant_override("margin_left", 16)
	frame.add_theme_constant_override("margin_right", 16)
	frame.add_theme_constant_override("margin_top", 18)
	frame.add_theme_constant_override("margin_bottom", 18)
	add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	frame.add_child(column)

	column.add_child(_build_lintel())
	column.add_child(_build_doors())

	# THE ROOM, which is the pool until you open another door. It takes the
	# whole of what is left, so a chart has room to be a chart.
	_room = PanelContainer.new()
	_room.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_room)

	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 12)
	inner.add_theme_constant_override("margin_right", 12)
	inner.add_theme_constant_override("margin_top", 10)
	inner.add_theme_constant_override("margin_bottom", 12)
	_room.add_child(inner)

	_room_body = VBoxContainer.new()
	_room_body.add_theme_constant_override("separation", 8)
	inner.add_child(_room_body)

	_pool = TemplePool.new()
	_pool.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _build_lintel() -> Control:
	var row := HBoxContainer.new()
	_room_title = Label.new()
	_room_title.text = "The Temple"
	_room_title.add_theme_font_size_override("font_size", 22)
	_room_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_room_title)
	var shut := Button.new()
	shut.text = "  Leave  "
	shut.pressed.connect(close)
	row.add_child(shut)
	return row


## THE DOORS. A flow container rather than a ring around the pool: a ring is
## the right picture and the wrong widget — at 400px across, five doors around
## a circle leaves a pool the size of a coin. This wraps to as many rows as the
## screen needs and puts them all on one line the moment there is room.
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


## OPEN. `why` is "sun" or "moon" and only changes the greeting — the temple is
## the same room at either hour.
func open(why := "sun") -> void:
	if visible:
		return
	visible = true
	if HOLDS_THE_WORLD:
		get_tree().paused = true
	_room_title.text = "The Temple" if why == "sun" else "The Temple, by moonlight"
	_enter(_open_door)


func close() -> void:
	visible = false
	if HOLDS_THE_WORLD:
		get_tree().paused = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## WALK INTO ONE. Every room is rebuilt on entry rather than kept alive behind
## the others: these are read once and closed, and a chart that goes on
## redrawing itself behind four other rooms is heat for nothing.
func _enter(which: int) -> void:
	_open_door = clampi(which, 0, DOORS.size() - 1)
	for i in _doors.size():
		_doors[i].set_pressed_no_signal(i == _open_door)
	for child in _room_body.get_children():
		# The pool is kept — it holds a built terrain image that costs real
		# milliseconds to raise, and rebuilding it every time somebody looks at
		# a chart and comes back is the one thing here that would be felt.
		_room_body.remove_child(child)
		if child != _pool:
			child.queue_free()
	call(String(DOORS[_open_door][2]))


func _room_pool() -> void:
	_pool.world_gen = world_gen
	_room_body.add_child(_pool)
	_pool.look_again()


func _room_chronicle() -> void:
	_room_body.add_child(TempleCharts.new())


func _room_reign() -> void:
	_room_body.add_child(TempleReign.new())


## THE OPTIONS, which already exist and already work. A temple door onto a
## settings panel somebody else maintains is better than a second copy of it.
func _room_rites() -> void:
	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Quality, sound and the rest are still on the opening screen " \
		+ "and F2. Moving them in here is the next thing this door does."
	_room_body.add_child(note)


func _room_creatures() -> void:
	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "The creatures you have raised, and the saves they live in."
	_room_body.add_child(note)
	var go := Button.new()
	go.text = "Open the profiles"
	go.pressed.connect(_open_profiles)
	_room_body.add_child(go)


func _open_profiles() -> void:
	close()
	if profiles != null and is_instance_valid(profiles):
		profiles.open()
