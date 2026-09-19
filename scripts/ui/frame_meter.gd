class_name FrameMeter
extends PanelContainer
## WHERE THE FRAME ACTUALLY WENT. ON THE DEVICE, IN NUMBERS, WHILE IT IS SLOW.
##
## A phone reported 133ms a frame — seven and a half pictures a second — and
## there was no way to tell from here which half of the machine was spending it.
## Everything after that question is guessing, and guessing is how you spend a
## week making the fast half faster.
##
## THE SPLIT IS THE WHOLE POINT. Godot will tell you what its own GDScript cost
## (`TIME_PROCESS`, `TIME_PHYSICS_PROCESS`) and what it asked the GPU to draw
## (draw calls, primitives). If the script time is most of the frame, the
## simulation is the problem and no amount of turning the picture down will help.
## If the script time is small and the frame is huge, the work is in the driver
## or the fragment pass and the simulation is innocent.
##
## AND THEN THERE IS THE THIRD THING, which is the one this was built to catch.
##
## Godot runs physics on a FIXED clock. At sixty ticks a second and a 133ms
## frame it owes eight ticks by the time the frame ends, and it runs all eight,
## up to `max_physics_steps_per_frame`. Every villager, every animal, every
## rigid body is simulated eight times for one picture. Which makes the frame
## longer. Which owes more ticks. A device that falls behind on this clock does
## not degrade — it falls down a hole, and the tell is a steps-per-frame number
## pinned at its ceiling while everything else looks merely bad. So this counts
## them, and says so.

## How often the readout is rewritten. Sixty times a second would put string
## formatting and a Label rewrite inside the very frame it is measuring.
const EVERY := 0.4
## HOW LONG A WORST IS REMEMBERED, and it is now every meter's worst rather
## than only the frame's.
##
## Every number on this readout is an INSTANT, and an instant is the one thing a
## person playing the game is not looking at: the frame that mattered has been
## and gone by the time they look up, and all they get is the calm number that
## followed it. "I'm not always immediately on top of every frame."
##
## So each line carries its own high-water mark, and the mark falls back to the
## present after this long. Both ends of that matter. A mark held FOR EVER is
## the loading hitch and nothing else — every reading in the session loses to
## the first frame, and the column stops meaning anything. A mark held for a
## second is the number you already missed. Twenty seconds is long enough to
## look up from the game and short enough that what it says is still about now.
const PEAK_HOLD := 20.0
## The smoothing on the headline figure. Long enough to read, short enough that
## walking into a town visibly moves it.
const BLEND := 0.1

## The physics priority that puts this node after everything else in the step.
## Nothing in this game sets one, so anything above zero would do; this is
## unmistakable rather than merely sufficient.
const ENGINE_LAST := 1000
## What the engine's own work is called on the bill. Parenthesised like
## "(everything else)", because it is not a class anybody wrote.
const ENGINE_ROW := &"(the solver)"

## WHAT IS THAT BAND ACROSS THE SKY.
##
## Something has been drawing a pale salmon ribbon over the landscape, and from
## a photograph there is no way to tell a stretched animal from a rope drawn to
## a dead anchor from a road doing exactly what it was told. Every answer anyone
## can give to a screenshot of it is a guess, and this codebase has a rule about
## guessing.
##
## So the meter names it: the biggest drawn thing in the world, with what it is,
## how wide it is and where it stands.
##
## IT IS PRINTED EVERY TIME, not only when it looks wrong. A line that appears
## only when some threshold decides there is a problem can only ever confirm
## what the threshold already believed — and the thing that is too big may well
## be a chunk of the ground, which is exactly what a skip list would hide. So
## the meter names the biggest drawn thing in the world, always, and how many
## are over GIANT. In a sane world that reads "Chunk/@MeshInstance3D 96m" and
## means nothing; when it reads "pig 812m" the hunt is over.
const GIANT := 120.0
## The only things skipped are the sky and the lights in it, which are meant to
## be the size of the world.
##
## MULTIMESHES USED TO BE SKIPPED TOO, on the grounds that a scatter's bounds
## are the whole field it covers rather than one blade of it. That was the
## reason this hunt was blind for a fortnight: a MultiMesh is the one thing in
## the game that can hold a transform NOBODY WROTE, and one of those is an
## animal-shaped mesh drawn somewhere nobody chose at a scale nobody chose. A
## herd's bounds are its spread, which is metres; if one ever reads in hundreds,
## that is the whole answer and it was being filtered out before it could be
## printed. They are counted, and the line says how many instances are in the
## book and how many of them the renderer may reach.
const VAST: Array[String] = ["Sky", "Sun", "Moon", "Horizon", "Star"]


## WHAT THE FRAME IS MADE OF, most recently measured. Public so a smoke test can
## assert on the same numbers the player is looking at.
var frame_ms := 0.0
var process_ms := 0.0
var physics_ms := 0.0
var steps := 0.0

var _label: Label
var _next := 0.0
var _worst := 0.0
## Terrain samples taken in the last frame. See WorldGen.reads.
var _land := 0
## Every meter's high-water mark, and how long each has left to hold it.
var _peaks := {}
var _peak_left := {}
## Physics ticks counted since the last drawn frame, and the running average.
var _ticks := 0
var _steps_seen := 0.0
## The wall clock at the last drawn frame. See `_process` — `delta` is world
## time and this meter has to report real time.
var _tocked := 0


## A PANEL CONTAINER AND NOT A CONTROL, and the difference is the whole of why
## this readout ran off the right-hand edge of the screen.
##
## A PLAIN Control LAYS NOTHING OUT. It has no minimum size of its own however
## much is inside it, so anchoring one with PRESET_MODE_MINSIZE pins a rect of
## ZERO WIDTH at the corner — and a panel added inside that rect is not
## positioned by it at all. It sits at the corner and grows whichever way it
## likes, which from the RIGHT edge is off the screen.
##
## A Container computes its minimum size from its children, so the preset has
## something real to pin and `grow_horizontal` has something real to grow. See
## HUD._build_roster, which is the same three lines done correctly, and the
## note there recording that this exact omission once put the workshop drawer
## off the screen too. tools/panels.py now refuses both.
func _ready() -> void:
	name = "FrameMeter"
	# LAST IN EVERY PHYSICS STEP, ON PURPOSE.
	#
	# A ledger clock is shut by the next one opening, so whatever ran LAST in a
	# step keeps its clock through the engine's own solve — collision, the
	# heightmaps, every CharacterBody3D's move — and is billed for all of it.
	# That is how `Animal 116.3ms` came back under a physics total of 84.9: it
	# was not Animal, it was Animal plus the solver.
	#
	# Godot runs `_physics_process` in priority order, higher last, so this node
	# closes the last class's clock and opens one named for the engine. What the
	# scripts cost and what the ENGINE costs are two different questions and the
	# bill could not tell them apart.
	process_physics_priority = ENGINE_LAST
	# AND LAST IN THE IDLE FRAME TOO, for a different reason that produces the
	# same lie. The ledger's page is turned in this file's own `_process`, and
	# turning it shuts whatever clock is open — so a meter that runs half way
	# down the tree turns the page half way through the frame. Everything after
	# it opens rows on the NEXT page, and whichever of those ran last keeps its
	# clock through the entire render and on into the following frame.
	#
	# That is how one muck pile came back at 14.2ms for a single call, top of
	# the bill, in a frame whose whole idle script time was 23ms. Poop._process
	# sets a scale and a height; it was being charged for the renderer.
	process_priority = ENGINE_LAST
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT,
		Control.PRESET_MODE_MINSIZE, 16)
	# INWARD FROM THE CORNER, both ways, said out loud. The default grows END,
	# which from a TOP edge points down the screen and from a RIGHT edge points
	# off it — so one of these two is load-bearing and the other only looks it,
	# and writing only the load-bearing one is how the next person learns the
	# wrong rule.
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_END
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color(0.05, 0.06, 0.08, 0.72)
	skin.content_margin_left = 10.0
	skin.content_margin_right = 10.0
	skin.content_margin_top = 8.0
	skin.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", skin)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A FIXED-WIDTH READOUT. Numbers that move about while you are reading them
	# off a phone in one hand are numbers you read wrong.
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_constant_override("line_spacing", 2)
	add_child(_label)


## COUNTED, NOT TIMED. Every physics tick between two drawn frames is one the
## whole simulation paid for, and their number is the thing that runs away.
func _physics_process(_delta: float) -> void:
	# FIRST LINE, like every other clock in the game — everything above an open
	# is billed to whoever ran before, and the rule does not get an exception
	# for the file that reports on it.
	Ledger.open(ENGINE_ROW)
	_ticks += 1


func _process(delta: float) -> void:
	# The steps are counted whether or not anybody is looking, because the
	# average has to be right the moment the meter is opened rather than four
	# tenths of a second afterwards.
	_steps_seen = lerpf(_steps_seen, float(_ticks), BLEND)
	_ticks = 0
	var now := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var fixed := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	# THE WALL CLOCK, AND NOT `delta`.
	#
	# `delta` has already been through Engine.time_scale, and this game runs the
	# world at 0.75 for as long as a rune is being drawn (DivineHand._tick_focus)
	# — so a perfectly steady frame arrives here a quarter shorter the moment
	# anybody casts, and the meter reports a device that just got faster. Worse,
	# it made the script time exceed the frame it was supposedly part of, which
	# is how a reading of "script 155ms, frame 101ms, draw 0" came back off a
	# phone: the draw figure was not zero, it was the subtraction going negative
	# and being clamped. Quality._process learned this same lesson separately.
	var tick := Time.get_ticks_usec()
	var whole := float(tick - _tocked) / 1000.0 if _tocked > 0 else delta * 1000.0
	_tocked = tick
	frame_ms = lerpf(frame_ms, whole, BLEND)
	process_ms = lerpf(process_ms, now, BLEND)
	physics_ms = lerpf(physics_ms, fixed, BLEND)
	steps = _steps_seen
	# THE LEDGER IS ON ONLY WHILE SOMEBODY IS READING IT, and its page turns
	# here — once a frame, in the one place that is already once a frame.
	Ledger.on = visible
	Ledger.turn_the_page()
	# EVERY FRAME, AND NOT EVERY REDRAW. The readout is rewritten two and a half
	# times a second; a worst sampled there would miss most of the frames it
	# exists to catch, and the spike a player looks up because of is exactly the
	# one that happens between two redraws.
	#
	# AND WHILE THE METER IS SHUT, which is the whole point: something stutters,
	# you press F7, and the last twenty seconds are already on the screen. The
	# bill's own rows are the exception and cannot be — the ledger is off while
	# nobody is reading it, which is what makes it free.
	_age_peaks(delta)
	_worst = _peak(&"frame", whole)
	_peak(&"script", now + fixed)
	_peak(&"_process", now)
	_peak(&"_physics", fixed)
	_peak(&"draw", maxf(whole - now - fixed, 0.0))
	_peak(&"calls", Performance.get_monitor(
		Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_peak(&"queue", float(Spool.waiting()))
	# HOW HARD THE LAND WAS ASKED. Read and reset here because this is the one
	# place in the game that runs exactly once a frame — see WorldGen.reads.
	_land = WorldGen.reads
	_peak(&"land", float(_land))
	WorldGen.reads = 0
	for row: Array in Ledger.rows():
		_peak(StringName("row " + String(row[0])), float(row[1]))
	if not visible:
		return
	_next -= delta
	if _next > 0.0:
		return
	_next = EVERY
	_label.text = _readout()


## EVERY MARK GETS OLDER, whether or not anything asked after it this frame.
##
## Ageing only the ones that were asked about would freeze the mark on a row
## that has stopped appearing — Poop's row exists only while there is muck in
## the world — and the stale number would be waiting the next time one turned
## up. A worst that is older than its own window is not a worst, it is a rumour.
func _age_peaks(delta: float) -> void:
	for what: StringName in _peak_left:
		_peak_left[what] = float(_peak_left[what]) - delta


## RAISE A MARK, or take the present if the old one has run out its hold.
func _peak(what: StringName, value: float) -> float:
	var held: float = float(_peaks.get(what, 0.0))
	if value >= held or float(_peak_left.get(what, 0.0)) <= 0.0:
		held = value
		_peak_left[what] = PEAK_HOLD
	_peaks[what] = held
	return held


## WHAT A MARK IS, without touching it — for the readout, which runs on its own
## slower clock and must not be the thing that decides when a worst expires.
func _seen(what: StringName) -> float:
	return float(_peaks.get(what, 0.0))


## ONE LINE OF THE READOUT with its own worst, in a column of its own so the
## four of them can be read down rather than hunted for.
## The pad is the width of the widest of the four (the physics line, with its
## steps), so the column is a column rather than four numbers at four places.
func _with_peak(text: String, worst: float) -> String:
	return "%-38s peak %5.1f" % [text, worst]


## THE BIGGEST DRAWN THING IN THE WORLD, whatever it is.
##
## Walks every drawn node once every EVERY seconds, and only while the meter is
## open, which is the only reason a walk of six thousand nodes in GDScript is an
## acceptable thing to do at all. It is a debugging instrument and it is priced
## like one.
func _the_biggest_thing() -> String:
	var worst := 0.0
	var named := ""
	var flock := ""
	var at := Vector3.ZERO
	var huge := 0
	for n in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var vi := n as VisualInstance3D
		if vi == null or not vi.is_visible_in_tree():
			continue
		var kin := vi.get_parent()
		var skip := false
		for word: String in VAST:
			if vi.name.contains(word) or (kin != null and kin.name.contains(word)):
				skip = true
				break
		if skip:
			continue
		# THE WORLD-SPACE BOX, THE ONLY WAY GODOT 4 HAS OF SAYING IT.
		#
		# `get_transformed_aabb()` is a Godot 3 method and does not exist here.
		# It failed twice, differently: `var box := ...` would not COMPILE (no
		# type to infer), and typing it by hand only moved the failure to the
		# first frame the meter was opened, where the call itself does not
		# exist. Transform times local box is the idiom this codebase already
		# uses — see ModelBank._true_box.
		var box: AABB = vi.global_transform * vi.get_aabb()
		var across: float = box.size[box.get_longest_axis_index()]
		# A NON-FINITE VERTEX makes an infinite box, and Godot draws that as a
		# smear across the whole world. It is the likeliest way a thing gets to
		# be a mile wide, and it must not be silently sorted to the bottom.
		if not is_finite(across):
			return "BIGGEST: %s/%s has a NON-FINITE box" \
				% [String(kin.name) if kin != null else "?", vi.name]
		if across > GIANT:
			huge += 1
		if across > worst:
			worst = across
			named = "%s/%s" % [String(kin.name) if kin != null else "?", vi.name]
			at = box.get_center()
			# AND HOW MANY OF IT THERE ARE, when what won is a scatter. A herd
			# reading four hundred metres across with four hundred in its book
			# and every one of them visible says what went wrong in one line.
			flock = ""
			var mmi := vi as MultiMeshInstance3D
			if mmi != null and mmi.multimesh != null:
				flock = " [%d of %d shown]" % [
					mmi.multimesh.visible_instance_count
						if mmi.multimesh.visible_instance_count >= 0
						else mmi.multimesh.instance_count,
					mmi.multimesh.instance_count]
	if named == "":
		return ""
	return "big: %s %.0fm @ %.0f,%.0f%s%s" % [named.left(22), worst, at.x, at.z,
		flock, "  (%d over %dm)" % [huge, int(GIANT)] if huge > 1 else ""]


## THE READOUT. Ordered so the first three lines answer the only question that
## matters — which half of the machine is spending the frame — and everything
## below them is there to explain whichever one it turns out to be.
func _readout() -> String:
	var scripted := process_ms + physics_ms
	var elsewhere := maxf(frame_ms - scripted, 0.0)
	var rows := PackedStringArray()
	rows.append("%.1f ms   %.1f fps   (worst %.0f)"
		% [frame_ms, 1000.0 / maxf(frame_ms, 0.001), _worst])
	rows.append("")
	rows.append(_with_peak("script  %6.1f ms  %3d%%   %s"
		% [scripted, int(_share(scripted)), _bar(_share(scripted))], _seen(&"script")))
	rows.append(_with_peak("   _process   %6.1f" % process_ms, _seen(&"_process")))
	rows.append(_with_peak("   _physics   %6.1f  x%.1f steps/frame%s"
		% [physics_ms, steps, "  <-- PINNED" if _spiralling() else ""],
		_seen(&"_physics")))
	rows.append(_with_peak("draw    %6.1f ms  %3d%%   %s"
		% [elsewhere, int(_share(elsewhere)), _bar(_share(elsewhere))],
		_seen(&"draw")))
	rows.append("")
	rows.append("%s land reads (peak %s)"
		% [_thousands(_land), _thousands(int(_seen(&"land")))])
	rows.append("%d draw calls (peak %d), %s primitives"
		% [int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(_seen(&"calls")),
			_thousands(int(Performance.get_monitor(
				Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))])
	rows.append("%d nodes, %d bodies, %d ORPHANS" % [
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))])
	rows.append(_what_is_here())
	var biggest := _the_biggest_thing()
	if biggest != "":
		rows.append(biggest)
	rows.append("")
	# THE BILL. What each numerous class cost this frame and how many of them
	# ran — the second number matters as much as the first, because a game that
	# starts at twenty frames and decays to ten is a game where something is
	# GROWING, and a count climbing while its cost climbs with it says which.
	# AND WHAT ONE OF THEM COSTS. The total and the count together are two
	# facts and the interesting one is their quotient: a row whose COUNT is
	# climbing is a population problem and a row whose EACH is climbing is a
	# code problem, and they want opposite fixes. Working that out by hand off a
	# photograph of a phone is exactly the sort of arithmetic nobody does.
	rows.append("WHERE THE SCRIPT WENT      ms     x   each   peak")
	for row: Array in Ledger.rows():
		if float(row[1]) < 0.05:
			continue
		var ran := maxi(int(row[2]), 1)
		rows.append("   %-18s %6.1f %5d %6.3f %6.1f"
			% [row[0], row[1], row[2], float(row[1]) / float(ran),
				_seen(StringName("row " + String(row[0])))])
	# WHAT THE BILL COMES TO, against what Godot says the scripts cost. A row is
	# an UPPER BOUND — see Ledger — and when the total passes the engine's own
	# figure the rows are absorbing the solver and each other, so it says so
	# rather than letting the biggest row be read as a culprit.
	var billed := Ledger.counted()
	if billed > scripted * 1.05:
		rows.append("   %-18s %6.1f  of %.1f  <-- OVER-BILLED"
			% ["(counted)", billed, scripted])
		rows.append("   rows include the solver and each other; read them as")
		rows.append("   an order, not as milliseconds.")
	else:
		rows.append("   %-18s %6.1f" % ["(everything else)",
			maxf(scripted - billed, 0.0)])
	rows.append("")
	rows.append("tier %s (%s)   3D at %d%%   physics %d Hz" % [
		Quality.Tier.keys()[Quality.effective_tier()], Quality.heat_word(),
		int(Quality.render_scale() * 100.0), Engine.physics_ticks_per_second])
	rows.append("%d thinking a frame, %d in the line (worst %d)"
		% [Spool.served(), Spool.waiting(), int(_seen(&"queue"))])
	return "\n".join(rows)


## IS THE PHYSICS CLOCK RUNNING AWAY? Pinned at the ceiling means the frame is
## no longer merely slow — every extra millisecond is buying more simulation,
## which buys more milliseconds. See the header.
func _spiralling() -> bool:
	return steps >= float(Engine.max_physics_steps_per_frame) - 0.35


func _share(part: float) -> float:
	return clampf(part / maxf(frame_ms, 0.001) * 100.0, 0.0, 100.0)


## Ten cells of a bar, because a share is easier to see than to read.
func _bar(share: float) -> String:
	var lit := int(round(share / 10.0))
	return "%s%s" % ["#".repeat(lit), ".".repeat(10 - lit)]


## WHAT IS STANDING IN THE WORLD RIGHT NOW. The counts that a frame time means
## nothing without: two hundred villagers at 40ms is a different problem from
## twelve at 40ms.
func _what_is_here() -> String:
	var tree := get_tree()
	# `ground` and not `chunks`: a chunk puts its collision body in that group
	# and there is no group of chunks to count. One body, one chunk.
	return "%d souls, %d beasts afoot, %d herds, %d chunks" % [
		tree.get_nodes_in_group("villagers").size(),
		tree.get_nodes_in_group("animals").size(),
		tree.get_nodes_in_group("herds").size(),
		tree.get_nodes_in_group("ground").size()]


## A thousands separator, by hand. Primitive counts run to seven figures and an
## unbroken seven-figure number is unreadable at this size.
func _thousands(n: int) -> String:
	var digits := str(n)
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out
