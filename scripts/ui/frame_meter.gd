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
## How long the worst frame is remembered, so a hitch can be read off a phone
## that is being held rather than watched.
const WORST_HOLD := 3.0
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


## WHAT THE FRAME IS MADE OF, most recently measured. Public so a smoke test can
## assert on the same numbers the player is looking at.
var frame_ms := 0.0
var process_ms := 0.0
var physics_ms := 0.0
var steps := 0.0

var _label: Label
var _next := 0.0
var _worst := 0.0
var _worst_left := 0.0
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
	_worst_left -= delta
	if whole > _worst or _worst_left <= 0.0:
		_worst = whole
		_worst_left = WORST_HOLD
	if not visible:
		return
	_next -= delta
	if _next > 0.0:
		return
	_next = EVERY
	_label.text = _readout()


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
	rows.append("script  %6.1f ms  %3d%%   %s"
		% [scripted, int(_share(scripted)), _bar(_share(scripted))])
	rows.append("   _process   %6.1f" % process_ms)
	rows.append("   _physics   %6.1f  x%.1f steps/frame%s"
		% [physics_ms, steps, "  <-- PINNED" if _spiralling() else ""])
	rows.append("draw    %6.1f ms  %3d%%   %s"
		% [elsewhere, int(_share(elsewhere)), _bar(_share(elsewhere))])
	rows.append("")
	rows.append("%d draw calls, %s primitives"
		% [int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			_thousands(int(Performance.get_monitor(
				Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))])
	rows.append("%d nodes, %d bodies, %d ORPHANS" % [
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))])
	rows.append(_what_is_here())
	rows.append("")
	# THE BILL. What each numerous class cost this frame and how many of them
	# ran — the second number matters as much as the first, because a game that
	# starts at twenty frames and decays to ten is a game where something is
	# GROWING, and a count climbing while its cost climbs with it says which.
	rows.append("WHERE THE SCRIPT WENT        ms    x")
	for row: Array in Ledger.rows():
		if float(row[1]) < 0.05:
			continue
		rows.append("   %-22s %6.1f %5d" % [row[0], row[1], row[2]])
	# WHAT THE BILL COMES TO, against what Godot says the scripts cost. A row is
	# an UPPER BOUND — see Ledger — and when the total passes the engine's own
	# figure the rows are absorbing the solver and each other, so it says so
	# rather than letting the biggest row be read as a culprit.
	var billed := Ledger.counted()
	if billed > scripted * 1.05:
		rows.append("   %-22s %6.1f  of %.1f  <-- OVER-BILLED"
			% ["(counted)", billed, scripted])
		rows.append("   rows include the solver and each other; read them as")
		rows.append("   an order, not as milliseconds.")
	else:
		rows.append("   %-22s %6.1f" % ["(everything else)",
			maxf(scripted - billed, 0.0)])
	rows.append("")
	rows.append("tier %s (%s)   3D at %d%%   physics %d Hz" % [
		Quality.Tier.keys()[Quality.effective_tier()], Quality.heat_word(),
		int(Quality.render_scale() * 100.0), Engine.physics_ticks_per_second])
	rows.append("%d thinking a frame, %d in the line"
		% [Spool.served(), Spool.waiting()])
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
