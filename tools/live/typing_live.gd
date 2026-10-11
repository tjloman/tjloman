extends SceneTree
## A NAME FIELD LETS GO OF THE KEYBOARD — checked in a real engine, headless:
##
##     godot --headless --path . --script tools/live/typing_live.gd
##
## The workshop panel's map-name field, once clicked into, took every key for
## the rest of the session: the camera's W A S D were typed into it. It lets go
## on Enter or Escape, a click anywhere else, or the panel closing.
## Exits non-zero on failure. Names no class of the game's (see look.gd).

var fails := 0


func check(ok: bool, what: String) -> void:
	print("  %-66s %s" % [what, "yes" if ok else "NO"])
	if not ok:
		fails += 1


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for i in 150:
		await process_frame
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	await process_frame
	var menu: Node = null
	for n in root.find_children("*", "CanvasLayer", true, false):
		if n.get_script() != null and String(n.get_script().get_global_name()) == "DebugMenu":
			menu = n
	print("A NAME FIELD")
	if menu == null:
		check(false, "the workshop panel has a map-name field")
		_done()
		return
	var field: LineEdit = menu._map_name
	menu._panel.visible = true
	await process_frame
	field.grab_focus()
	await process_frame
	check(field.has_focus(), "clicked into, the field has the keys")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(20, 400)
	Input.parse_input_event(click)
	await process_frame
	await process_frame
	check(not field.has_focus(), "a click anywhere else and it lets them go")
	field.grab_focus()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await process_frame
	await process_frame
	check(not field.has_focus(), "and so does Escape")
	menu._panel.visible = false
	_done()


func _done() -> void:
	print("TYPING LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)
