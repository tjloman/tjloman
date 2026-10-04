extends SceneTree
## SEE THE GAME, without a screen: render real frames and save them as PNGs.
##
## On a machine with no GPU, a software Vulkan driver (Mesa's lavapipe) and a
## virtual X display (Xvfb) are enough to run the real renderer — slowly, a few
## frames a second, but every shader compiled and every pixel drawn:
##
##     xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --audio-driver Dummy \
##         --rendering-method mobile --resolution 1280x720 \
##         --script tools/look/look.gd -- out.png [hour] [distance] [pitch]
##
## `hour` is the time of day, 0..1 (0.3 a low morning sun, 0.5 noon); the camera
## stands `distance` metres off and looks down at `pitch` degrees. Loads the
## normal main scene, waits for the land, puts the start screen away, holds the
## hour, and saves the frame. (Run `godot --headless --path . --import` once
## first if a new class_name has been added.)
##
## It names no class of the game's: a --script is compiled before the autoloads
## exist, and anything it names would be compiled then too, and fail.

var out := "look.png"
var hour := 0.35
var distance := -1.0
var pitch := -1.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1:
		hour = float(args[1])
	if args.size() > 2:
		distance = float(args[2])
	if args.size() > 3:
		pitch = float(args[3])
	change_scene_to_file("res://scenes/main.tscn")
	var began := Time.get_ticks_msec()
	for i in 400:
		await process_frame
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	var state := root.get_node("/root/GameState")
	var rigs := root.find_children("*", "CameraRig", true, false)
	if not rigs.is_empty():
		var rig = rigs[0]
		if distance > 0.0:
			rig.zoom_distance = distance
		if pitch > 0.0 and rig.pitch_node != null:
			rig.pitch_node.rotation_degrees.x = -pitch
	for i in 240:
		# Held every frame: a save loaded behind the start screen brings its own.
		state.game_years = fposmod(hour - 0.35, 1.0) * float(state.DAY_YEARS)
		await process_frame
	var sky := root.find_child("ShadowSky", true, false)
	if sky != null:
		print("LOOK hour %.3f, sun %s" % [state.day_fraction(), sky.get_sent_sun()])
	root.get_viewport().get_texture().get_image().save_png(out)
	print("LOOK saved %s after %.0fs at %.0f fps, %d baked shadows" % [out,
		(Time.get_ticks_msec() - began) / 1000.0, Engine.get_frames_per_second(),
		root.find_children("Shadow", "MeshInstance3D", true, false).size()])
	quit()
