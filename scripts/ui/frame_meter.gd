class_name FrameMeter
extends PanelContainer
## WHERE THE FRAME ACTUALLY WENT. ON THE DEVICE, IN NUMBERS, WHILE IT IS SLOW.
##
## A phone reported 133ms a frame — seven and a half pictures a second — and
## there was no way to tell from here which half of the machine was spending it.
## Everything after that question is guessing, and guessing is how you spend a
## week making the fast half faster.
##
## THE SPLIT IS THE WHOLE POINT. Every part of the frame is on the ledger's
## page, one clock for all of it: the scripts, the engine's physics solve
## (ENGINE_ROW), and the drawing with the wait for the screen (DRAW_ROW). If the
## script time is most of the frame, the simulation is the problem and no amount
## of turning the picture down will help. If the drawing is, the work is in the
## driver or the fragment pass and the simulation is innocent.
##
## NOT GODOT'S OWN `TIME_PROCESS`, which this used to read. It runs from the
## first _process to the end of the DRAW, so it holds the drawing, and it is the
## worst single frame of the last second, set once a second (main.cpp,
## Main::iteration). "Script" came out larger than the frame it was part of, and
## the frame less that read "draw 0.0 ms" on a phone spending half of it drawing.
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
## "(unclocked)", because it is not a class anybody wrote — see the bill.
const ENGINE_ROW := &"(the solver)"
## AND WHAT EVERYTHING AFTER THE LAST SCRIPT OF THE FRAME IS CALLED: the deferred
## calls and frees, the drawing, and the wait for the next refresh of the screen
## (or the frame cap). This meter runs last in the idle frame, so the clock it
## opened for itself stayed open through all of that — and on a phone
## "FrameMeter" came back at 25 to 36 ms of a 50 ms frame, the dearest row on
## the bill, for a readout rewritten twice a second. The meter hands its clock
## on to this the moment its own work is done, as `_physics_process` hands the
## solver's to ENGINE_ROW.
const DRAW_ROW := &"(draw+wait)"
## THE BILL'S DEAREST ROWS, and no more: the rest are tenths of a millisecond,
## and on a phone they pushed the end of the readout off the screen.
const BILL_ROWS := 12
## THE BARE COUNTER (see `cycle`): its one line is rewritten this often, in a
## larger hand than the whole readout's.
const BARE_EVERY := 0.5
const FONT := 13
const BARE_FONT := 16

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
## HOW SLOW A FRAME HAS TO BE BEFORE THE METER KEEPS ITS PAGE ON SCREEN, in
## milliseconds. A hitch is a frame; a STALL is a frame you look up from the
## game about. Sixty is four frames at the target rate and well past anything
## the tier ladder is meant to smooth over.
const STALL_WORTH_NAMING := 60.0
## How many of the worst frame's rows to name. Three is enough to see whether a
## stall was one class or the whole world at once.
const WORST_ROWS_SHOWN := 3
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
## The two walks of the world (see `_survey_some`): how many nodes a frame, and
## how often a fresh walk begins.
const SURVEY_SLICE := 400
## And buildings a frame for the seating walk: each is five reads of the land.
const SURVEY_SEATS := 40
const SURVEY_EVERY := 3.0


## WHAT THE FRAME IS MADE OF, most recently measured, off the ledger's page
## (see `_split_the_page`). Public so a smoke test can assert on the same
## numbers the player is looking at.
var frame_ms := 0.0
var script_ms := 0.0
var solver_ms := 0.0
var draw_ms := 0.0
var steps := 0.0
## Showing one bare line rather than the whole readout. See `cycle`.
var bare := false

var _label: Label
var _next := 0.0
var _worst := 0.0
## Terrain samples taken in the last frame. See WorldGen.reads.
var _land := 0
## And the ones answered from the shared grid instead. See WorldGen.shared_reads.
var _shared := 0
## Every meter's high-water mark, and how long each has left to hold it.
var _peaks := {}
var _peak_left := {}
## Physics ticks counted since the last drawn frame, and the running average.
var _ticks := 0
var _steps_seen := 0.0
## The wall clock at the last drawn frame. See `_process` — `delta` is world
## time and this meter has to report real time.
var _tocked := 0
var _survey: Array = []
var _seats: Array = []
var _survey_left := 0.0
var _big := {}
var _seat := {}
var _big_line := ""
var _seated_line := ""
## The panel is to be shrunk to what it says, after a change of mode. See `_fit`.
var _refit := false


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
	_pin()
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
	_label.add_theme_font_size_override("font_size", FONT)
	_label.add_theme_constant_override("line_spacing", 2)
	add_child(_label)


## F7, AND THE FRAMES BUTTON: the whole readout, then one bare line, then
## nothing, and round again.
##
## The whole readout is fifty lines, and on a phone the bottom of it is off the
## screen; while playing, all anybody wants of it is the frame rate. The bare
## line is that — frames a second, the frame, the worst of the last PEAK_HOLD
## seconds — and it costs what a shut meter costs: the ledger is off for it and
## the world is not walked. Says whether this press opened the whole readout,
## which is a fresh sitting (HUD._toggle_frames).
func cycle() -> bool:
	if not visible:
		visible = true
		bare = false
	elif not bare:
		bare = true
	else:
		visible = false
		bare = false
	_label.add_theme_font_size_override("font_size", BARE_FONT if bare else FONT)
	_label.text = ""
	_next = 0.0
	_refit = true
	return visible and not bare


## COUNTED, NOT TIMED. Every physics tick between two drawn frames is one the
## whole simulation paid for, and their number is the thing that runs away.
func _physics_process(_delta: float) -> void:
	# FIRST LINE, like every other clock in the game — everything above an open
	# is billed to whoever ran before, and the rule does not get an exception
	# for the file that reports on it.
	Ledger.open(ENGINE_ROW)
	_ticks += 1


func _process(delta: float) -> void:
	Ledger.open(&"FrameMeter")
	# The steps are counted whether or not anybody is looking, because the
	# average has to be right the moment the meter is opened rather than four
	# tenths of a second afterwards.
	_steps_seen = lerpf(_steps_seen, float(_ticks), BLEND)
	_ticks = 0
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
	steps = _steps_seen
	# THE LEDGER IS ON ONLY WHILE SOMEBODY IS READING IT — the whole readout,
	# not the bare line, which reads nothing but the clock — and its page turns
	# here, once a frame, in the one place that is already once a frame.
	Ledger.on = visible and not bare
	Ledger.turn_the_page()
	# AND THE METER PAYS FOR ITSELF, ON THE BILL. Everything below — the marks,
	# and above all the readout, fifty lines of text laid out afresh — ran
	# after the page had turned and before anything opened the next one, so it
	# was charged to nobody and turned up as a frame that was slow for no
	# reason anyone could see. Measured, it was most of the "unclocked" time.
	Ledger.open(&"FrameMeter")
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
	_peak(&"calls", Performance.get_monitor(
		Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_peak(&"queue", float(Spool.waiting()))
	# HOW HARD THE LAND WAS ASKED. Read and reset here because this is the one
	# place in the game that runs exactly once a frame — see WorldGen.reads.
	_land = WorldGen.reads
	_peak(&"land", float(_land))
	WorldGen.reads = 0
	_shared = WorldGen.shared_reads
	WorldGen.shared_reads = 0
	_split_the_page()
	if not visible:
		return
	if bare:
		_bare_line(delta)
		return
	_survey_some()
	_next -= delta
	if _next <= 0.0:
		_next = EVERY
		_label.text = _readout()
		_fit()
	# AND FROM HERE TO THE NEXT FRAME'S FIRST SCRIPT IS THE DRAWING: see DRAW_ROW.
	# Last, so the readout just written is the meter's, and nothing after it is.
	Ledger.open(DRAW_ROW)


## THE FRAME, SPLIT THREE WAYS off the page just turned — one frame on one
## clock: the drawing and the wait for the screen (DRAW_ROW), the engine's
## physics solve (ENGINE_ROW), and every script, which is the rest of what was
## counted. And each row's worst, sampled here, every frame.
func _split_the_page() -> void:
	var drew := 0.0
	var solved := 0.0
	for row: Array in Ledger.rows():
		_peak(StringName("row " + String(row[0])), float(row[1]))
		if row[0] == DRAW_ROW:
			drew = float(row[1])
		elif row[0] == ENGINE_ROW:
			solved = float(row[1])
	var scripted := maxf(Ledger.counted() - drew - solved, 0.0)
	script_ms = lerpf(script_ms, scripted, BLEND)
	solver_ms = lerpf(solver_ms, solved, BLEND)
	draw_ms = lerpf(draw_ms, drew, BLEND)
	_peak(&"script", scripted)
	_peak(&"solver", solved)
	_peak(&"draw", drew)


## THE BARE LINE, rewritten every BARE_EVERY: frames a second, the frame, and
## its worst — and the frame cap, when the cap is what is holding it there.
func _bare_line(delta: float) -> void:
	_next -= delta
	if _next > 0.0:
		return
	_next = BARE_EVERY
	# HELD BY THE CAP when the frame sits on the cap's period, not merely
	# inside it: a frame faster than the cap is a frame the cap is holding back
	# only if it is the cap's own length.
	var cap := Quality.fps_cap
	var held := cap > 0 and absf(frame_ms - 1000.0 / float(cap)) <= 1000.0 / float(cap) * 0.08
	_label.text = "%.1f fps   %.1f ms   worst %.0f%s" % [1000.0 / maxf(frame_ms, 0.001),
		frame_ms, _worst, "   (cap %d)" % cap if held else ""]
	_fit()


## SHRUNK TO WHAT IT SAYS, against its corner, after a change of mode. A
## Control grows to its content by itself and never shrinks back, so the bare
## line kept the width of the whole readout it had just been. Only then: done
## at every rewrite, the panel would twitch with the width of the numbers.
func _fit() -> void:
	if not _refit:
		return
	_refit = false
	reset_size()
	_pin()


## TO THE TOP-RIGHT CORNER, at the size of what it says.
func _pin() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT,
		Control.PRESET_MODE_MINSIZE, 16)
	# INWARD FROM THE CORNER, both ways, said out loud. The default grows END,
	# which from a TOP edge points down the screen and from a RIGHT edge points
	# off it — so one of these two is load-bearing and the other only looks it,
	# and writing only the load-bearing one is how the next person learns the
	# wrong rule.
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_END


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


## WHAT THE WORST FRAME OF THIS SITTING WAS MADE OF.
##
## Every other row here is the frame you are in, which is never the frame you
## want. A ten-second hang is over before you can look at it, and the page it
## was written on was turned and discarded while you were still noticing — so
## the meter could tell you a stall of 10273.7ms had happened and nothing
## whatever about what it was.
##
## The ledger keeps that page whole now (Ledger.worst_rows), and this prints
## its three dearest rows plus its head. The record is cleared each time the
## meter is opened, so it is the worst frame SINCE YOU LOOKED — open it, do the
## thing that stutters, read the answer.
func _the_worst_frame() -> Array:
	var span := Ledger.worst_ms()
	if span < STALL_WORTH_NAMING:
		return []
	var out := ["worst frame %.0f ms, since the meter opened:" % span]
	var shown := 0
	for row: Array in Ledger.worst_rows():
		if shown >= WORST_ROWS_SHOWN or float(row[1]) < span * 0.01:
			break
		out.append("   %-18s %8.1f  x%d" % [row[0], float(row[1]), int(row[2])])
		shown += 1
	out.append("   %-18s %8.1f  before any script ran"
		% ["(head of frame)", maxf(span - Ledger.worst_counted(), 0.0)])
	# WHAT THE HEAD WAS, when it can be told: nodes torn down land there, and a
	# worst frame that lost thousands of them was a frame spent freeing.
	out.append("   %-18s %8d  nodes that frame" % ["(the world)", Ledger.worst_nodes()])
	var held := Ledger.worst_physics()
	out.append("   %-18s %8d  pairs touching, %d bodies awake" % ["(physics)", held.x, held.y])
	out.append("")
	return out


## THE WORST-SEATED BUILDING IN THE WORLD, and by how much.
##
## "Half the houses are great, but many are still sunken into the dirt" is a
## thing a screenshot shows and an argument cannot settle. Buildings are seated
## on the land as it is DRAWN now (WorldGen.settle_height, re-asked whenever the
## ground under them is cut), so this should read zero for every building in
## every town — and if it does not, it names the one to go and look at.
##
## Measured against the same footprint the building was seated with, so the
## number here and the number the seater worked to are the same number.
##
## Walked at the rate the readout is rewritten rather than per frame, and only
## while the meter is open.
func _worst_seated() -> String:
	return _seated_line


## THE BIGGEST DRAWN THING IN THE WORLD, whatever it is, as the last whole
## survey found it. See `_survey_some`.
func _the_biggest_thing() -> String:
	return _big_line


## THE TWO WALKS OF THE WORLD, A SLICE A FRAME.
##
## The biggest drawn thing and the worst-seated building were each found by a
## walk of everything there is — six thousand drawn nodes, three hundred
## buildings each asked its ground — every time the readout was written, two and
## a half times a second. Measured, writing the readout cost twenty-two
## milliseconds, almost all of it these two: the meter was putting a hitch into
## every frame it was opened to look at. Now each walk goes SURVEY_SLICE nodes a
## frame, and says what it found when it has been round once.
func _survey_some() -> void:
	if _survey.is_empty():
		_survey_left -= get_process_delta_time()
		if _survey_left > 0.0:
			return
		_survey_left = SURVEY_EVERY
		# THE TREE ITSELF, opened a node at a time: gathering every drawn node
		# in one call was twenty milliseconds on its own.
		_survey = [get_tree().root]
		_seats = get_tree().get_nodes_in_group(WorldGen.SEATED)
		_big = {"worst": 0.0, "named": "", "flock": "", "at": Vector3.ZERO, "huge": 0, "odd": ""}
		_seat = {"worst": 0.0, "named": "", "at": Vector3.ZERO}
	for i in SURVEY_SLICE:
		if _survey.is_empty():
			break
		var next = _survey.pop_back()
		if not is_instance_valid(next):
			continue
		_survey.append_array((next as Node).get_children())
		if next is GeometryInstance3D:
			_measure_one(next)
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	for i in SURVEY_SEATS:
		if _seats.is_empty() or world == null:
			break
		_seat_one(world, _seats.pop_back())
	if _survey.is_empty():
		_publish_survey()


## ONE DRAWN THING: is it the biggest yet?
func _measure_one(n: Variant) -> void:
	if not is_instance_valid(n):
		return
	var vi := n as VisualInstance3D
	if vi == null or not vi.is_visible_in_tree():
		return
	var kin := vi.get_parent()
	for word: String in VAST:
		if vi.name.contains(word) or (kin != null and kin.name.contains(word)):
			return
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
	var name_of := "%s/%s" % [String(kin.name) if kin != null else "?", vi.name]
	# A NON-FINITE VERTEX makes an infinite box, and Godot draws that as a
	# smear across the whole world. It is the likeliest way a thing gets to
	# be a mile wide, and it must not be silently sorted to the bottom.
	if not is_finite(across):
		_big["odd"] = name_of
		return
	if across > GIANT:
		_big["huge"] = int(_big["huge"]) + 1
	if across > float(_big["worst"]):
		_big["worst"] = across
		_big["named"] = name_of
		_big["at"] = box.get_center()
		# AND HOW MANY OF IT THERE ARE, when what won is a scatter. A herd
		# reading four hundred metres across with four hundred in its book
		# and every one of them visible says what went wrong in one line.
		_big["flock"] = ""
		var mmi := vi as MultiMeshInstance3D
		if mmi != null and mmi.multimesh != null:
			_big["flock"] = " [%d of %d shown]" % [
				mmi.multimesh.visible_instance_count
					if mmi.multimesh.visible_instance_count >= 0
					else mmi.multimesh.instance_count,
				mmi.multimesh.instance_count]


## ONE BUILDING: how far under its ground is it?
func _seat_one(world: WorldGen, n: Variant) -> void:
	if not is_instance_valid(n):
		return
	var thing := n as Node3D
	if thing == null:
		return
	var here := thing.global_position
	var half := float(thing.get_meta("seat_half", 2.5))
	var under := world.settle_height(here.x, here.z, half) - here.y
	if under > float(_seat["worst"]):
		_seat["worst"] = under
		_seat["named"] = thing.get_class() if not thing.has_meta("hover_name") \
			else String(thing.get_meta("hover_name"))
		_seat["at"] = here


func _publish_survey() -> void:
	if String(_big["odd"]) != "":
		_big_line = "BIGGEST: %s has a NON-FINITE box" % _big["odd"]
	elif String(_big["named"]) != "":
		var at: Vector3 = _big["at"]
		var huge := int(_big["huge"])
		_big_line = "big: %s %.0fm @ %.0f,%.0f%s%s" % [String(_big["named"]).left(22),
			float(_big["worst"]), at.x, at.z, _big["flock"],
			"  (%d over %dm)" % [huge, int(GIANT)] if huge > 1 else ""]
	var seat_at: Vector3 = _seat["at"]
	_seated_line = "buildings all sit on the ground" if float(_seat["worst"]) < 0.05 \
		else "worst seated: %s %.2fm under, at %.0f,%.0f" % [_seat["named"],
			float(_seat["worst"]), seat_at.x, seat_at.z]


## THE READOUT. Ordered so the first three lines answer the only question that
## matters — which half of the machine is spending the frame — and everything
## below them is there to explain whichever one it turns out to be.
func _readout() -> String:
	var rows := PackedStringArray()
	rows.append("%.1f ms   %.1f fps   (worst %.0f)"
		% [frame_ms, 1000.0 / maxf(frame_ms, 0.001), _worst])
	rows.append("")
	rows.append(_with_peak("script     %6.1f ms  %3d%%   %s"
		% [script_ms, int(_share(script_ms)), _bar(_share(script_ms))], _seen(&"script")))
	rows.append(_with_peak("solver     %6.1f ms  x%.1f steps/frame%s"
		% [solver_ms, steps, "  <-- PINNED" if _spiralling() else ""], _seen(&"solver")))
	rows.append(_with_peak("draw+wait  %6.1f ms  %3d%%   %s"
		% [draw_ms, int(_share(draw_ms)), _bar(_share(draw_ms))], _seen(&"draw")))
	rows.append("")
	rows.append("%s land reads (peak %s), %s shared"
		% [_thousands(_land), _thousands(int(_seen(&"land"))), _thousands(_shared)])
	# AND WHOSE: the three classes that asked most.
	var askers := Ledger.land_rows()
	if not askers.is_empty():
		var who := PackedStringArray()
		for row: Array in askers.slice(0, 3):
			who.append("%s %s" % [row[0], _thousands(int(row[1]))])
		rows.append("   by " + ", ".join(who))
	# THE SLOWEST SINGLE CALL, now and since the meter opened: one thing taking
	# a second, or many things a millisecond each, and what it was doing.
	for ever: bool in [false, true]:
		var slow := Ledger.slowest_call(ever)
		if not slow.is_empty():
			rows.append("%s %s %.1f ms%s" % ["   slowest ever:" if ever else "slowest call:",
				slow[0], slow[2], _doing(slow[0], slow[1])])
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
	rows.append("WHERE THE FRAME WENT       ms     x   each   peak")
	var bill := Ledger.rows()
	for row: Array in bill.slice(0, BILL_ROWS):
		if float(row[1]) < 0.05:
			continue
		var ran := maxi(int(row[2]), 1)
		rows.append("   %-18s %6.1f %5d %6.3f %6.1f"
			% [row[0], row[1], row[2], float(row[1]) / float(ran),
				_seen(StringName("row " + String(row[0])))])
	if bill.size() > BILL_ROWS:
		rows.append("   ...and %d more, under %.1f ms each"
			% [bill.size() - BILL_ROWS, float(bill[BILL_ROWS - 1][1])])
	# WHAT NO ROW HOLDS, footed against the page: the same clock as every row,
	# so the subtraction is between two real numbers. With the solver and the
	# drawing on rows of their own, the ledger's baton runs the whole frame and
	# this reads nothing; if it ever reads more, a gap has opened between two
	# clocks and that is worth seeing. (It used to be footed against Godot's own
	# TIME_PROCESS, which holds the drawing and is a per-second worst — see the
	# header — and a screenshot came back with "script" four times its frame.)
	var page := Ledger.page_ms()
	var billed := Ledger.counted()
	rows.append("   %-18s %6.1f  of %.1f ms of frame"
		% ["(unclocked)", maxf(page - billed, 0.0), page])
	rows.append("")
	for line in _the_worst_frame():
		rows.append(line)
	rows.append(_worst_seated())
	rows.append("%d%% of frames over the line, %d stalls ignored"
		% [int(Quality.share_over() * 100.0), Quality.stalls_ignored()])
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


## What a clocked thing was in the middle of, from the tag it opened with.
func _doing(who: String, tag: Variant) -> String:
	# A word is its own name: which part of the work it was (see Ledger.swap).
	if typeof(tag) == TYPE_STRING:
		return " (%s)" % tag
	if tag == null or typeof(tag) != TYPE_INT:
		return ""
	var names: Array = []
	if who == "Villager":
		names = Villager.State.keys()
	elif who.begins_with("Creature"):
		names = Creature.State.keys()
	var i := int(tag)
	return " (%s)" % names[i] if i >= 0 and i < names.size() else ""
