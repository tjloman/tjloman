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


static func note(source: String, amount: float) -> void:
	if on:
		meals[source] = float(meals.get(source, 0.0)) + amount


static func clear() -> void:
	meals.clear()
