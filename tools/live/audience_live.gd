extends SceneTree
## THE HAND ON THE CREATURE — checked in a real engine, headless:
##
##     godot --headless --path . --script tools/live/audience_live.gd
##
## Every press here is pushed through the viewport as an input event, the way a
## finger arrives, and nothing is called on the hand directly:
##
##   1. a press lands on a villager the pointer was NOT over a moment ago, and
##      takes hold of them (the hover is asked at the press, not a tick later),
##   2. a hold on the creature calls it: it stands in HEED, turns to you, the
##      camera glides to the shot, and it greets you,
##   3. a slow rub over it is a stroke (praise), a fast swipe a slap (scolding),
##      a tap asks again, a tap away lets it go,
##   4. a press on it that moves straight away is the land, not a call; a
##      sleeping creature is not woken,
##   5. and the greeting reads its moods off the creature, not out of a hat.
## Exits non-zero on failure. Names no class of the game's (see look.gd).

var fails := 0
var main: Node
var hand: Node
var rig: Node
var beast: Node


func check(ok: bool, what: String) -> void:
	print("  %-66s %s" % [what, "yes" if ok else "NO"])
	if not ok:
		fails += 1


func button(at: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.position = at
	ev.global_position = at
	root.push_input(ev, true)


func motion(at: Vector2, by: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	ev.relative = by
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(ev, true)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func on_screen(at: Vector3) -> Vector2:
	return rig.camera.unproject_position(at)


func beast_middle() -> Vector2:
	return on_screen(beast.global_position + Vector3.UP * 2.55 * beast.scale.y * 0.5)


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await frames(120)
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	main = current_scene
	hand = main.divine_hand
	rig = main.camera_rig
	beast = main.creature
	print("THE HAND ON THE CREATURE")
	await pick_up_on_the_press()
	await call_it()
	await stroke_and_slap()
	await let_it_go()
	await not_a_call()
	await moods()
	print("AUDIENCE LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)


## 1. The press reads what is under it NOW.
func pick_up_on_the_press() -> void:
	var home: Node = main.world_gen.player_village
	var best: Node = null
	for v in get_nodes_in_group("villagers"):
		if v.is_adult() and not v.is_dying() and (best == null
				or v.global_position.distance_to(home.global_position)
				< best.global_position.distance_to(home.global_position)):
			best = v
	rig.snap_to(best.global_position)
	rig.zoom_distance = 16.0
	await frames(60)
	# The pointer was last somewhere else: a corner, with nothing under it.
	motion(Vector2(30, 30), Vector2.ZERO)
	await frames(10)
	var stale: Node = hand.hover_target
	var at := on_screen(best.global_position + Vector3.UP * 0.9)
	button(at, true)
	var held: Node = hand.held_body
	check(stale != best and held != null,
		"a press on somebody the pointer was not over takes hold (%s)"
		% [held.name if held != null else "nothing"])
	button(at, false)
	await frames(10)


## 2. Hold on it, and it comes to you.
func call_it() -> void:
	beast.state = beast.State.WANDER
	beast.fear = 0.0
	rig.snap_to(beast.global_position)
	rig.zoom_distance = beast.scale.y * 9.0
	rig.pitch_node.rotation_degrees.x = -30.0
	await frames(60)
	var at := beast_middle()
	motion(at, Vector2.ZERO)
	button(at, true)
	await wait(0.25)
	check(not hand.audience.is_open(), "half a hold is not yet a call")
	await wait(0.6)
	check(hand.audience.is_open(), "a held hand on it opens an audience")
	check(beast.state_name() == "HEED", "it stops for you (%s)" % beast.state_name())
	button(at, false)
	await frames(5)
	check(hand.audience.is_open(), "letting go of the hold that called it does not dismiss it")
	await wait(2.5)
	check(beast.state_name() == "HEED", "and it stays stopped (%s)" % beast.state_name())
	var to_eye: Vector3 = rig.camera.global_position - beast.global_position
	to_eye.y = 0.0
	var facing: Vector3 = beast.global_transform.basis.z
	facing.y = 0.0
	var off := rad_to_deg(facing.angle_to(to_eye))
	check(off < 30.0, "it has turned to face you (%.0f degrees off)" % off)
	var tall: float = 2.55 * beast.scale.y
	var aim: Vector3 = beast.global_position + Vector3.UP * tall * 0.72
	check(rig.framed and rig.global_position.distance_to(aim) < tall * 0.25
		and absf(rig.pitch_node.rotation_degrees.x + 14.0) < 3.0,
		"the camera has glided to the shot (%.1fm from it, pitch %.0f)"
		% [rig.global_position.distance_to(aim), rig.pitch_node.rotation_degrees.x])
	var said: Dictionary = hand.audience.greeting
	print("    it says: %s — \"%s\"" % [said.get("mood", "?"), said.get("line", "")])
	check(String(said.get("line", "")) != "", "it greets you")


## 3. A rub is praise; a swipe is a slap.
func stroke_and_slap() -> void:
	var lessons: int = beast.lessons
	var mid := beast_middle()
	var tall: float = root.get_visible_rect().size.y
	button(mid, true)
	var x := 0.0
	var step := 8.0
	var went := 0.0
	while went < tall * 0.6:
		x += step
		if absf(x) > 50.0:
			step = -step
		motion(mid + Vector2(x, 0.0), Vector2(step, 0.0))
		went += absf(step)
		OS.delay_msec(20)
		await process_frame
	button(mid + Vector2(x, 0.0), false)
	check(beast.lessons == lessons + 1 and hand.audience.touched == "stroke",
		"a slow rub over it is a stroke: it is praised, once")
	check(hand.audience.is_open(), "and the audience stays open")
	await frames(5)
	var fear: float = beast.fear
	var from := mid - Vector2(160.0, 0.0)
	button(from, true)
	for i in 8:
		var at := from + Vector2(40.0 * (i + 1), 0.0)
		motion(at, Vector2(40.0, 0.0))
		OS.delay_msec(8)
	button(from + Vector2(320.0, 0.0), false)
	check(beast.lessons == lessons + 2 and hand.audience.touched == "slap",
		"a fast swipe across it is a slap: it is scolded")
	check(beast.fear > fear, "and it stings (fear %.0f -> %.0f)" % [fear, beast.fear])
	await wait(1.8)
	print("    then it says: %s — \"%s\"" % [hand.audience.greeting.get("mood", "?"),
		hand.audience.greeting.get("line", "")])


## 3b. A tap asks again; a tap away is goodbye.
func let_it_go() -> void:
	var mid := beast_middle()
	hand.audience.greeting = {}
	button(mid, true)
	button(mid, false)
	check(not hand.audience.greeting.is_empty(), "a tap on it asks it again")
	var away := Vector2(root.get_visible_rect().size.x - 40.0, root.get_visible_rect().size.y - 40.0)
	motion(away, Vector2.ZERO)
	await frames(3)
	button(away, true)
	button(away, false)
	check(not hand.audience.is_open(), "a tap away from it lets it go")
	check(beast.greeting_eye == Vector3.INF and not rig.framed,
		"and nothing of the audience is left holding it or the camera")
	await frames(10)
	check(beast.state_name() != "HEED", "it goes back to its day (%s)" % beast.state_name())


## 4. A press that moves is the land; a sleeper is not woken.
func not_a_call() -> void:
	beast.state = beast.State.WANDER
	rig.snap_to(beast.global_position)
	await frames(30)
	var at := beast_middle()
	motion(at, Vector2.ZERO)
	button(at, true)
	await frames(2)
	motion(at + Vector2(60.0, 0.0), Vector2(60.0, 0.0))
	await wait(0.8)
	# Whether the land is then grabbed is asked of the VIEWPORT's mouse, which a
	# headless engine never moves — so what is checked is that the call is
	# dropped and the land drag asked for, not where it ends up.
	check(not hand.audience.is_open() and hand._greeting == null,
		"a press on it that moves at once is not a call")
	button(at + Vector2(60.0, 0.0), false)
	await frames(5)
	beast.state = beast.State.SLEEPING
	at = beast_middle()
	motion(at, Vector2.ZERO)
	button(at, true)
	await wait(0.8)
	button(at, false)
	check(not hand.audience.is_open() and beast.state_name() == "SLEEPING",
		"a sleeping creature is not woken by the hand")
	beast.state = beast.State.WANDER


## 5. The mood is read off it.
func moods() -> void:
	var greeting: Script = load("res://scripts/creature/creature_greeting.gd")
	var clock: float = root.get_node("/root/GameState").clock
	var plain := func() -> void:
		beast.heart.feeling = {}
		beast.fear = 0.0
		beast.boredom = 0.0
		beast.hunger = 10.0
		beast.energy = 90.0
		beast.trust = 60.0
		beast.mind.lately = []
		beast.mind.ethos.axis["mercy"] = 0.3
		beast.morality = 20.0
	plain.call()
	check(greeting.mood(beast) == "calm", "nothing held: calm")
	beast.heart.feeling["fury"] = 0.8
	check(greeting.mood(beast) == "angry", "fury held: angry")
	plain.call()
	beast.fear = 80.0
	check(greeting.mood(beast) == "frightened", "fear high: frightened")
	plain.call()
	beast.mind.lately = [["praised", clock], ["scolded", clock]]
	check(greeting.mood(beast) == "confused", "praised and scolded at once: confused")
	plain.call()
	beast.heart.feeling["grief"] = 0.6
	check(greeting.mood(beast) == "upset", "grief held: upset")
	plain.call()
	beast.boredom = 85.0
	check(greeting.mood(beast) == "bored", "nothing to do: bored")
	plain.call()
	beast.heart.feeling["delight"] = 0.7
	beast.mind.beliefs.episodes.append({"key": "throw|villager", "ctx": {},
		"at": clock, "place": "", "felt": "", "worth": 0.0})
	check(greeting.mood(beast) == "excited", "a gentle creature glad of a throw: excited")
	beast.mind.ethos.axis["mercy"] = -0.6
	beast.morality = -40.0
	var joke: Dictionary = greeting.compose(beast)
	print("    a cruel one: \"%s\"" % joke["line"])
	check(joke["mood"] == "cruelly joking" and String(joke["line"]).contains("hurling villagers"),
		"a cruel creature glad of a throw: cruelly joking, about the throw")
	plain.call()
	beast.hunger = 90.0
	beast.trust = 10.0
	var hungry: Dictionary = greeting.compose(beast)
	check(String(hungry["line"]).begins_with("Oh. It's you.")
		and String(hungry["line"]).ends_with("starving."),
		"it says when it is starving, and when it no longer trusts you")
