class_name Yields
extends RefCounted
## WHAT A LIVE TOWN BRINGS IN, BY WHERE IT CAME FROM — counted only while
## somebody is measuring (tools/live/calibrate_live.gd), so the chessboard's
## rates for a town out of sight are held to what a town in sight actually
## does. Switched off, it is one boolean test a delivery.

static var on := false
## Meals by source: the job a haul came from (Villager._carry_job — "farm",
## "fish", "hunt", "skin"), "berries" eaten at the bush, "boat" for a fishing
## boat's catch, "butcher" for a carcass cut up at the store.
static var meals := {}
## AND WHAT IS EATEN, meal by meal, where it is eaten — not worked out from the
## store, which also feeds the beasts, the workshops and the builders.
static var eaten := 0.0
## AND WHOSE: with a town set, only what it brings in and eats is counted — two
## towns side by side would otherwise be measured as one.
static var town: Node = null


static func note(source: String, amount: float, by: Node) -> void:
	if on and (town == null or by == town):
		meals[source] = float(meals.get(source, 0.0)) + amount


static func ate(many: float, by: Node) -> void:
	if on and (town == null or by == town):
		eaten += many


static func clear() -> void:
	meals.clear()
	eaten = 0.0
