extends SceneTree
## F7 GOES ROUND THREE WAYS, AND THE METER BILLS ONLY ITSELF — checked headless:
##
##     godot --headless --path . --script tools/live/meter_live.gd
##
##   1. F7 (the Frames button) opens the whole readout, then a bare line, then
##      shuts it, and round again (FrameMeter.cycle);
##   2. the bare line is one line, in a panel its own size against the top-right
##      corner — not the size of the readout it had just been — and the ledger
##      is off for it;
##   3. and it costs a fraction of what the whole readout costs a frame
##      (measured last: the meter is run by hand for it);
##   4. with the whole readout open, the meter's own row is the meter: the end
##      of the frame — the drawing, the wait for the frame cap — is on a row of
##      its own (DRAW_ROW), where it had made "FrameMeter" the dearest row on a
##      phone's bill; and script, solver and drawing add up to the frame.
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
	for i in 60:
		await process_frame
	print("THE FRAME METER")
	var ledger: Script = load("res://scripts/ledger.gd")
	var hud: Node = get_first_node_in_group("hud")
	var meter: Control = hud._frames
	while meter.visible:
		hud._toggle_frames()

	# 1 and 4. The whole readout, and what its own row holds.
	hud._toggle_frames()
	for i in 10:
		await process_frame
	check(meter.visible and not meter.bare and ledger.on, "the first press opens the whole readout")
	var own := 0.0
	var drawn := 0.0
	var pages := 0.0
	var split := 0.0
	for i in 60:
		await process_frame
		for row: Array in ledger.rows():
			if row[0] == "FrameMeter":
				own += float(row[1])
			elif row[0] == String(meter.DRAW_ROW):
				drawn += float(row[1])
		pages += ledger.page_ms()
		split += meter.script_ms + meter.solver_ms + meter.draw_ms
	own /= 60.0
	drawn /= 60.0
	pages /= 60.0
	split /= 60.0
	var full_height: float = meter.size.y
	check(drawn > 0.0 and own < 2.0 and own < drawn,
		"the meter's own row is the meter (%.2f ms), the drawing its own (%.2f)" % [own, drawn])
	check(absf(split - pages) <= pages * 0.15,
		"script, solver and drawing make up the frame (%.1f of %.1f ms)" % [split, pages])

	# 2. The bare line.
	hud._toggle_frames()
	for i in 4:
		await process_frame
	var said: String = meter._label.text
	var edge: float = root.get_visible_rect().size.x - meter.get_global_rect().end.x
	check(meter.visible and meter.bare and not ledger.on and said.contains("fps")
		and said.split("\n").size() == 1,
		"the second press shows one line, with the ledger off (\"%s\")" % said)
	var fits: bool = meter.size.is_equal_approx(meter.get_combined_minimum_size())
	check(fits and meter.size.y < full_height * 0.2 and absf(edge - 16.0) < 2.0,
		"in a panel its own size, in the corner (%.0f x %.0f px, was %.0f tall; %.0f px in)"
		% [meter.size.x, meter.size.y, full_height, edge])

	# 1. Shut, and round again.
	hud._toggle_frames()
	await process_frame
	await process_frame
	check(not meter.visible and not ledger.on, "the third press shuts it, the ledger with it")
	hud._toggle_frames()
	await process_frame
	check(meter.visible and not meter.bare, "and the fourth opens the whole readout again")

	# 3. What each costs a frame, last: run by hand, the meter's clock reads
	# frames of microseconds, and what it says after is not worth reading.
	for i in 10:
		await process_frame
	var full_us := _cost(meter)
	hud._toggle_frames()
	await process_frame
	var bare_us := _cost(meter)
	check(meter.bare and bare_us < full_us * 0.25 and bare_us < 100.0,
		"the bare line costs %.0f us a frame, the whole readout %.0f" % [bare_us, full_us])
	hud._toggle_frames()
	print("METER LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)


## What the meter's frame costs as it stands, in microseconds: its own tick,
## run by hand, averaged — the readout's slower rewrites and the slices of its
## walk of the world included, as they fall.
func _cost(meter: Node) -> float:
	var began := Time.get_ticks_usec()
	for i in 200:
		meter._process(1.0 / 60.0)
	return float(Time.get_ticks_usec() - began) / 200.0
