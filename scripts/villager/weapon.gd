class_name Weapon
extends RefCounted
## Arms for the militia. A village that keeps timber and stone can equip its
## people; what they can afford decides what they carry. Better arms hit
## harder, and a bow lets a villager fight from outside a wolf's jaws.
##
## Pure data plus a visual builder — the fighting itself lives in Villager.

## kind -> stats. `reach` is how far it can strike from; `cost` is what the
## storehouse pays to make one (lumber, stone).
const SPECS := {
	"club": {
		"damage": 14.0, "reach": 2.2, "cooldown": 1.1,
		"lumber": 1, "stone": 0, "label": "a stout club",
	},
	"spear": {
		"damage": 20.0, "reach": 3.2, "cooldown": 1.2,
		"lumber": 1, "stone": 1, "label": "a flint spear",
	},
	"bow": {
		"damage": 17.0, "reach": 11.0, "cooldown": 1.6,
		"lumber": 2, "stone": 1, "label": "a hunting bow",
	},
	"sword": {
		"damage": 30.0, "reach": 2.6, "cooldown": 0.9,
		"lumber": 1, "stone": 3, "label": "a bronze sword",
	},
}

## Tried in order — a village spends what it has on the best arms it can make.
const BY_PREFERENCE := ["sword", "bow", "spear", "club"]


static func damage(kind: String) -> float:
	return SPECS.get(kind, {}).get("damage", 6.0)   # bare hands, if unarmed


static func reach(kind: String) -> float:
	return SPECS.get(kind, {}).get("reach", 1.8)


static func cooldown(kind: String) -> float:
	return SPECS.get(kind, {}).get("cooldown", 1.4)


static func label(kind: String) -> String:
	return SPECS.get(kind, {}).get("label", "bare hands")


static func is_ranged(kind: String) -> bool:
	return kind == "bow"


## The best arms this storehouse can pay for right now, or "" if it can't
## afford even a club. Does NOT spend — see `forge`.
static func affordable(store: FoodStore) -> String:
	if store == null or not is_instance_valid(store):
		return ""
	for kind: String in BY_PREFERENCE:
		var spec: Dictionary = SPECS[kind]
		if store.lumber >= spec["lumber"] and store.stone >= spec["stone"]:
			return kind
	return ""


## Spend the materials and hand back the weapon made, or "" if the stores
## fell short in the meantime.
static func forge(store: FoodStore) -> String:
	var kind := affordable(store)
	if kind == "":
		return ""
	var spec: Dictionary = SPECS[kind]
	if not store.try_spend_materials(spec["lumber"], spec["stone"]):
		return ""
	return kind


## A small piece of kit held at the villager's side, so an armed crowd reads
## at a glance. Pooled primitives — a militia costs the renderer almost nothing.
static func build_visual(kind: String) -> Node3D:
	var held := Node3D.new()
	match kind:
		"club":
			held.add_child(Util.lite_box(
				Vector3(0.09, 0.5, 0.09), Color(0.45, 0.33, 0.2), Vector3(0.3, 0.75, 0.1)))
		"spear":
			held.add_child(Util.lite_box(
				Vector3(0.06, 1.1, 0.06), Color(0.5, 0.38, 0.24), Vector3(0.3, 0.95, 0.1)))
			held.add_child(Util.lite_box(
				Vector3(0.1, 0.2, 0.02), Color(0.72, 0.72, 0.75), Vector3(0.3, 1.55, 0.1)))
		"bow":
			var stave := Util.lite_box(
				Vector3(0.06, 0.85, 0.06), Color(0.46, 0.32, 0.18), Vector3(0.32, 0.9, 0.08))
			stave.rotation_degrees.z = 12.0
			held.add_child(stave)
		"sword":
			held.add_child(Util.lite_box(
				Vector3(0.07, 0.62, 0.03), Color(0.78, 0.66, 0.32), Vector3(0.3, 0.85, 0.1)))
			held.add_child(Util.lite_box(
				Vector3(0.22, 0.06, 0.05), Color(0.4, 0.3, 0.18), Vector3(0.3, 0.56, 0.1)))
	return held
