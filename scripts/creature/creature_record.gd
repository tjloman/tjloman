class_name CreatureRecord
extends RefCounted
## WRITING A CREATURE DOWN, AND GIVING IT BACK.
##
## Everything else about the creature is behaviour; this is bookkeeping, and it
## grows a line every time the mind grows a faculty — a compass, a heart, a
## forward model, a memory of ground, a ledger of people. Keeping it beside the
## state machine meant the state machine grew every time the mind did, for no
## reason at all.
##
## Nothing here decides anything. Each module writes and reads its own
## dictionary (see CreatureMind, CreatureHeart, CreatureBody, CreatureSteering);
## this only says which of them there are, and what a newborn's defaults look
## like — so a save written before a faculty existed loads without a murmur.


## Everything a creature IS, in one dictionary.
static func of(who: Creature) -> Dictionary:
	return {
		"name": who.creature_name,
		"pos": [who.global_position.x, who.global_position.y, who.global_position.z],
		"stature": who.stature,
		"hunger": who.hunger,
		"energy": who.energy,
		"mood": who.mood,
		"bond": who.bond,
		"trust": who.trust,
		"exiled": who.exiled,
		"grievance": who.grievance,
		"grievance_time": who.grievance_time,
		"catch_skill": who.catch_skill,
		"boredom": who.boredom,
		"fear": who.fear,
		"attention": who.attention,
		"walks_on_water": who.walks_on_water,
		"flight": who.flight_time,
		"inedible": who.distastes().duplicate(),
		"mind": who.mind.to_dict(),
		"body": who.body.to_dict(),
		"heart": who.heart.to_dict(),
		"trouble": who.steering.to_dict(),
	}


## And back again.
static func into(who: Creature, data: Dictionary) -> void:
	var p: Array = data.get("pos", [])
	if p.size() == 3:
		who.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	who.name_it(String(data.get("name", who.creature_name)))
	# A save from before the arc was widened carries a 0..1 fraction of the way
	# to full size; the growth setter puts that at the same place on the new
	# sixty-five-thousand-step scale.
	if data.has("stature"):
		who.stature = clampf(float(data["stature"]), 1.0, Creature.FULL_STATURE)
	else:
		who.growth = float(data.get("growth", 0.01))
	who.hunger = float(data.get("hunger", 40.0))
	who.energy = float(data.get("energy", 90.0))
	who.mood = float(data.get("mood", 60.0))
	who.bond = float(data.get("bond", 20.0))
	who.trust = float(data.get("trust", 55.0))
	who.exiled = bool(data.get("exiled", false))
	who.grievance = String(data.get("grievance", ""))
	who.grievance_time = float(data.get("grievance_time", 0.0))
	who.catch_skill = float(data.get("catch_skill", 0.3))
	who.boredom = float(data.get("boredom", 20.0))
	who.fear = float(data.get("fear", 0.0))
	who.attention = float(data.get("attention", 20.0))
	who.walks_on_water = bool(data.get("walks_on_water", false))
	who.flight_time = float(data.get("flight", 0.0))
	who.set_distastes(data.get("inedible", {}) as Dictionary)
	who.mind.from_dict(data.get("mind", {}))
	who.body.from_dict(data.get("body", {}))
	who.heart.from_dict(data.get("heart", {}))
	who.steering.from_dict(data.get("trouble", {}))
	# Its size and the colour of its hide follow from the soul just restored.
	who.refresh_appearance()
