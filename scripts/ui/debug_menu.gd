class_name DebugMenu
extends CanvasLayer
## The workshop drawer (F3): a deliberate checkpoint save, a reload, the way
## through to the creatures you have raised, and REGENERATE — roll a new land
## but keep the creature. Below those sit the small cheats that make testing the
## long systems bearable: prayer, growth, and instant converts.
##
## The world writes itself down on its own now (see SaveGame), so nothing here
## is load-bearing any more. What is left that cannot be undone still ARMS
## before it fires: the first press turns the button red and asks again, and it
## disarms itself after a few seconds. No stray click throws away an hour of
## raising a creature.

const ARM_SECONDS := 4.0

var world_gen: WorldGen
var creature: Creature
var tutorial: Tutorial
var profiles: ProfileMenu

var _panel: PanelContainer
var _friends_button: Button = null
var _supporter_button: Button = null
var _sculpt_button: Button = null
var _map_name: LineEdit = null
var _armed: Button = null
var _arm_time := 0.0
var _armed_label := ""


func _ready() -> void:
	# AWAKE WHILE THE WORLD IS HELD. The opening screen pauses the tree, and a
	# paused node is offered no input — so without this the buttons that open
	# this very menu would be shouting at something asleep.
	process_mode = Node.PROCESS_MODE_ALWAYS

	layer = 12
	_build()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	# WHICH WAY IT GROWS, and it has to be said out loud. The preset is applied
	# before the buttons exist, so the panel's minimum size is still zero and it
	# comes out as a hairline pinned to the right edge; every control then grows
	# to fit its contents in whatever direction `grow_*` names. The default is
	# GROW_DIRECTION_END — outwards, off the right of the screen — so the whole
	# 274-pixel drawer opened just past the edge of the window and could not be
	# seen or clicked. It has to grow INWARD from the edge it is anchored to,
	# which is what the touch controls and the praise/scold pair already say.
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.09, 0.88)
	style.border_color = Color(0.5, 0.55, 0.7, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(_heading("WORKSHOP  [F3]"))

	box.add_child(_button("Save now", _on_save,
		"Write this world down. The game already saves itself every couple\n"
		+ "of minutes and whenever you leave, so this is only a checkpoint."))
	box.add_child(_button("Reload last save", _on_load,
		"Throw away what has happened since the last save."))
	box.add_child(_button("The creatures you have raised  [F5]", _on_profiles,
		"Switch between creatures, or name and begin a new one. Each has\n"
		+ "its own world, and none of them costs the others anything."))
	box.add_child(_gap())

	box.add_child(_heading("START AGAIN"))
	box.add_child(_button("New land, SAME creature", _on_regenerate,
		"Roll a brand new world. Your creature comes along with every\n"
		+ "habit, belief and pound of fat it has earned.", true))
	box.add_child(_gap())

	# THE ONE PLAYER-FACING SETTING so far, and it lives here because there is
	# no options screen yet. When there is, this row moves there unchanged; the
	# entitlement toggle under it stays in the workshop, where it belongs.
	box.add_child(_heading("THE WOOD"))
	_friends_button = _button("", _on_friends,
		"Bees over the flowers, crickets after dark, squirrels working the\n"
		+ "limbs. None of it changes the game — it is there to be listened to.")
	box.add_child(_friends_button)
	_supporter_button = _button("", _on_supporter,
		"Stands in for the purchase, until there is one to check. The tree\n"
		+ "friends are the supporters' build; nothing else is gated.")
	box.add_child(_supporter_button)
	box.add_child(_gap())

	# THE MAP EDITOR, and it is not a tool — it is the game with the prayer
	# turned off. Sculpt the coast with lava and lightning, then write the
	# result out. See MapFile for why that is the whole of it.
	box.add_child(_heading("MAPS"))
	_sculpt_button = _button("", _on_sculpt,
		"Bottomless prayer, so the earth-movers are a sculpting tool.\n"
		+ "Nothing else changes: the world goes on living while you work.")
	box.add_child(_sculpt_button)
	_map_name = LineEdit.new()
	_map_name.placeholder_text = "map name"
	_map_name.custom_minimum_size = Vector2(250, 30)
	box.add_child(_map_name)
	box.add_child(_button("Save this map", _on_save_map,
		"Writes the seed and every reshaping to user://maps.\n"
		+ "That pair IS the map — there is no second copy of the terrain.\n"
		+ "The soot is left out: you keep the shape, not the burning."))
	box.add_child(_button("Save it burnt", _on_save_burnt,
		"The same, keeping every scorch mark — for a map that is\n"
		+ "MEANT to look like somewhere a god has been."))
	box.add_child(_button("Load that map", _on_load_map,
		"Reads it back and re-cuts every chunk, so the new ground is\n"
		+ "the ground you see as well as the one you walk on.", true))
	box.add_child(_button("What maps are there?", _on_list_maps,
		"Print every saved map to the announcement line."))
	box.add_child(_gap())

	box.add_child(_heading("CHEATS"))
	box.add_child(_button("+500 prayer", _on_prayer, "Fill the reservoir."))
	box.add_child(_button("Grow creature", _on_grow,
		"Add about ten thousand stature — a few hours of ordinary growing."))
	box.add_child(_button("Convert nearest village", _on_convert,
		"Make the closest town believe — the quick way to test unlocks."))
	box.add_child(_button("What does it believe?", _on_creed,
		"Print the creature's mind and creed to the announcement line."))
	box.add_child(_button("Replay the lessons", _on_tutorial,
		"Run the opening tutorial again from the top, without touching your save."))

	_panel.add_child(box)
	add_child(_panel)
	_show_settings()


## The two toggles say what they ARE, not what they would do — a button reading
## "Tree friends: on" cannot be misread the way "Turn off tree friends" can.
func _show_settings() -> void:
	if _friends_button == null or not is_instance_valid(_friends_button):
		return
	_friends_button.text = "Tree friends: %s" % (
		"on" if GameState.tree_friends else
		"off (supporters)" if not GameState.supporter else "off")
	_friends_button.disabled = not GameState.supporter
	_supporter_button.text = "Supporter: %s" % ("yes" if GameState.supporter else "no")
	_refresh_sculpt()


func _on_friends() -> void:
	GameState.tree_friends = not GameState.tree_friends
	_show_settings()
	GameState.announce("The small things %s." % (
		"stir in the trees" if GameState.tree_friends else "go quiet"))


## STANDING IN FOR A RECEIPT. There is no store yet; when there is, it sets
## GameState.supporter at boot and this row is the only thing that changes.
func _on_supporter() -> void:
	GameState.supporter = not GameState.supporter
	_show_settings()


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.72, 0.8, 1.0))
	return label


func _gap() -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	return spacer


func _button(text: String, action: Callable, tip: String, dangerous := false) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(250, 32)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	if dangerous:
		b.add_theme_color_override("font_color", Color(1.0, 0.78, 0.7))
		b.pressed.connect(_confirm.bind(b, text, action))
	else:
		b.pressed.connect(action)
	return b


## Two-press safety on the world-shaking buttons.
func _confirm(button: Button, label: String, action: Callable) -> void:
	if _armed == button:
		_disarm()
		action.call()
		return
	_disarm()
	_armed = button
	_armed_label = label
	_arm_time = ARM_SECONDS
	button.text = "Really? Press again"
	button.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))


func _disarm() -> void:
	if _armed != null and is_instance_valid(_armed):
		_armed.text = _armed_label
		_armed.add_theme_color_override("font_color", Color(1.0, 0.78, 0.7))
	_armed = null
	_arm_time = 0.0


func _process(delta: float) -> void:
	if _arm_time > 0.0:
		_arm_time -= delta
		if _arm_time <= 0.0:
			_disarm()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		_panel.visible = not _panel.visible
		if not _panel.visible:
			_disarm()


## Actions ---------------------------------------------------------------------

func _on_save() -> void:
	if world_gen != null and is_instance_valid(creature):
		SaveGame.save_to_disk(world_gen, creature)


func _on_load() -> void:
	SaveGame.load_game()


func _on_regenerate() -> void:
	SaveGame.regenerate_world(creature)


## Beginning again no longer means throwing anything away: it makes a NEW
## creature, in its own profile, beside the ones already raised.
func _on_profiles() -> void:
	if profiles != null and is_instance_valid(profiles):
		_panel.visible = false
		profiles.open(SaveGame.profiles.is_empty())


## SCULPT MODE. Prayer stops being a resource, so the earth-movers can be used
## the way a sculptor uses a chisel — dozens of times a minute without waiting.
## It is a toggle rather than a one-off top-up because sculpting a coastline
## takes an afternoon, and topping up by hand every ninety seconds is the thing
## that would make it unbearable.
func _on_sculpt() -> void:
	GameState.sculpting = not GameState.sculpting
	if GameState.sculpting:
		# So the reservoir READS full as well as being bottomless — a bar that
		# says empty while nothing costs anything is a confusing thing to work
		# under for an afternoon.
		GameState.set_max_prayer_power(maxf(GameState.max_prayer_power, 500.0))
		GameState.add_prayer_power(500.0)
	_refresh_sculpt()
	GameState.announce("Sculpting: prayer is bottomless." if GameState.sculpting
		else "Sculpting off. Prayer costs again.")


func _refresh_sculpt() -> void:
	if _sculpt_button == null or not is_instance_valid(_sculpt_button):
		return
	_sculpt_button.text = "Sculpt mode: ON" if GameState.sculpting else "Sculpt mode: off"


func _on_save_burnt() -> void:
	_write_map(true)


func _on_save_map() -> void:
	_write_map(false)


func _write_map(keep_scorch: bool) -> void:
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world == null:
		return
	var written := MapFile.save_as(world, _map_name.text, keep_scorch)
	if written == "":
		GameState.announce("That map needs a name.")
		return
	GameState.announce("Map written: %s" % written)


func _on_load_map() -> void:
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world == null:
		return
	if MapFile.load_into(world, _map_name.text):
		GameState.announce("Map loaded: %s" % MapFile.describe(_map_name.text))
	else:
		GameState.announce("No map by that name.")


func _on_list_maps() -> void:
	var maps := MapFile.all_maps()
	if maps.is_empty():
		GameState.announce("No maps saved yet.")
		return
	for one: String in maps:
		GameState.announce(MapFile.describe(one))


func _on_prayer() -> void:
	GameState.set_max_prayer_power(maxf(GameState.max_prayer_power, 500.0))
	GameState.add_prayer_power(500.0)
	GameState.announce("Prayer floods in: %.0f." % GameState.prayer_power)


func _on_grow() -> void:
	if not is_instance_valid(creature):
		return
	creature.gain_stature(Creature.FULL_STATURE * 0.15)
	GameState.announce("Your creature surges to stature %s." % creature.stature_text())


func _on_convert() -> void:
	var here := creature.global_position if is_instance_valid(creature) else Vector3.ZERO
	var best: Village = null
	var best_dist := INF
	for v in get_tree().get_nodes_in_group("village"):
		var vil := v as Village
		if not is_instance_valid(vil) or vil.converted:
			continue
		var d := vil.global_position.distance_to(here)
		if d < best_dist:
			best_dist = d
			best = vil
	if best == null:
		GameState.announce("Every village in sight already believes in you.")
		return
	best.change_belief(100.0)


## Run the opening lessons again — for testing a change to them, or for anyone
## who skipped them and wishes they had not.
func _on_tutorial() -> void:
	if tutorial != null and is_instance_valid(tutorial):
		tutorial.restart()
		_panel.visible = false
		GameState.announce("The lessons begin again.")


func _on_creed() -> void:
	if not is_instance_valid(creature):
		return
	var creed := PackedStringArray()
	for line: String in creature.mind.beliefs.creed():
		creed.append(line)
	for rite: String in creature.mind.rites():
		creed.append(rite)
	for habit: String in creature.mind.character_account():
		creed.append(habit)
	for picture: String in creature.mind.world_picture():
		creed.append(picture)
	creed.append("feels %s" % " and ".join(creature.heart.account()))
	creed.append("understands %d kinds of circumstance from the inside (empathy %d%%)"
		% [creature.heart.wisdom(), int(creature.heart.empathy * 100.0)])
	creed.append("the device is %s (%.1fms a frame)" % [
		Quality.heat_word(), Quality.frame_ms()])
	# WHAT THE TOWN IS WAITING ON. The one number worth watching while tuning
	# Quality.decisions: if the line is never more than a handful deep the
	# budget is generous, and if it is hundreds deep the town is thinking as
	# fast as the frame will let it — which is the spool doing its job, not a
	# fault, until the wait starts showing as people standing about.
	creed.append("%d thinking a frame, %d standing in the line" % [
		Spool.served(), Spool.waiting()])
	# WHAT THE EYE HAS MADE OF THE LIGHT. The gap between the two numbers is the
	# adaptation still happening — walk away from a fire and watch the second
	# chase the first down for nine seconds while the stars come up.
	var nightfall := get_tree().get_first_node_in_group("nightfall") as Nightfall
	if nightfall != null and is_instance_valid(nightfall):
		var meter := nightfall.meter
		creed.append("it is %.3f lux here and the eye has settled on %.3f (%d%% stars)"
			% [meter.lux(), meter.adapted(), int(meter.starlight() * 100.0)])
	var said := "  ·  ".join(creed) if not creed.is_empty() \
		else "It has learned nothing it can put into words yet."
	GameState.announce("%s (%s, %s) — %s" % [
		creature.mind.strongest_urge(), creature.morality_word(),
		creature.body.condition_word(), said])
