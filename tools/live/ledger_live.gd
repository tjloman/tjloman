extends SceneTree
## THE METER'S CLOCK DOES NOT RUN WHILE THE METER IS SHUT — checked headless:
##
##     godot --headless --path . --script tools/live/ledger_live.gd
##
## A clock open in the frame F7 shuts the meter must not be billed for the time
## it stays shut. The ledger is driven by hand here the way FrameMeter drives it
## (switch, then turn the page), with a real wait while it is off.
## Exits non-zero on failure. Names no class of the game's (see look.gd).

var fails := 0


func check(ok: bool, what: String) -> void:
	print("  %-62s %s" % [what, "yes" if ok else "NO"])
	if not ok:
		fails += 1


func page(ledger: Script, reading: bool) -> void:
	ledger.on = reading
	ledger.turn_the_page()


func _initialize() -> void:
	var ledger: Script = load("res://scripts/ledger.gd")
	page(ledger, true)
	ledger.open(&"Early")
	page(ledger, true)
	# The last clock of the frame the meter shuts in, and a shut meter.
	ledger.open(&"LeadRope")
	page(ledger, false)
	OS.delay_msec(400)
	page(ledger, false)
	OS.delay_msec(400)
	# Opened again: one ordinary frame.
	page(ledger, true)
	ledger.open(&"Villager")
	OS.delay_msec(2)
	page(ledger, true)
	var ever: Array = ledger.slowest_call(true)
	print("  slowest ever: %s" % [ever])
	check(not ever.is_empty() and float(ever[2]) < 100.0,
		"nothing is billed for the 800 ms the meter was shut")
	var rope := 0.0
	for row: Array in ledger.rows():
		if row[0] == "LeadRope":
			rope = float(row[1])
	check(rope < 100.0, "the clock open when it shut is not on the next page")
	# A real stall while it IS open is still caught.
	ledger.open(&"Stall")
	OS.delay_msec(150)
	page(ledger, true)
	ever = ledger.slowest_call(true)
	check(not ever.is_empty() and ever[0] == "Stall" and float(ever[2]) >= 140.0,
		"a real 150 ms call while it is open is still the slowest")
	ledger.forget_worst()
	check(ledger.slowest_call(true).is_empty(), "a fresh sitting forgets the slowest call")
	print("LEDGER LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)
