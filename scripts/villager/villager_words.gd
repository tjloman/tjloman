class_name VillagerWords
extends RefCounted
## EVERYTHING A VILLAGER IS CALLED, AND EVERYTHING THEY ARE SAID TO BE DOING.
##
## Two long match blocks and a ladder of adjectives: the card the god reads when
## the pointer rests on somebody, the word that floats over their head, and the
## name for their morals. A hundred lines of pure naming, and it was a hundred
## lines of villager.gd — a file that has to keep room in it for a villager to
## do something NEW, which is the only reason any of this moved.
##
## NOTHING HERE DECIDES ANYTHING. Every function is a pure reading of a villager
## as they stand, which is what lets it live over here at all — and it is why a
## new State wants a line in both blocks below and nowhere else in this file.

static func hover(who: Villager) -> String:
	var stage: String
	if who.age < Villager.ADULT_AGE:
		stage = "girl" if who.is_female else "boy"
	elif who.age >= Villager.ELDER_AGE:
		stage = "elder"
	else:
		stage = "woman" if who.is_female else "man"
	var extra := ", pregnant" if who.pregnant else ""
	if who.weapon != "":
		extra += ", armed with %s" % Weapon.label(who.weapon)
	if who.home == null:
		extra += ", HOMELESS"
	return "%s of %s — %s %s, age %d%s — %s\n(health %d · hunger %d · energy %d · happy %d · %s)" % [
		who.villager_name, who.village.village_name, morality_word(who), stage,
		int(who.age), extra, status_word(who), int(who.health), int(who.hunger),
		int(who.energy), int(who.happiness), "she" if who.is_female else "he"]


static func morality_word(who: Villager) -> String:
	if who.morality > 60.0:
		return "saintly"
	if who.morality > 20.0:
		return "decent"
	if who.morality > -20.0:
		return "coarse"
	# Drawn at the line a soul stops being shamed by mourners — see
	# VillagerFeeding.MONSTROUS. The word and the deed are one number.
	if who.morality >= VillagerFeeding.MONSTROUS:
		return "wicked"
	return "monstrous"


static func status_word(who: Villager) -> String:
	match who.state:
		Villager.State.WANDER: return "strolling"
		Villager.State.PLAY: return "playing"
		Villager.State.GO_EAT, Villager.State.EATING: return "eating"
		Villager.State.GO_SLEEP, Villager.State.SLEEPING:
			return "sleeping" if who.home != null else "sleeping rough"
		Villager.State.GO_FARM, Villager.State.FARMING: return "working the farm"
		Villager.State.GO_HUNT, Villager.State.HUNTING: return "hunting"
		Villager.State.MUSTERING: return "waiting on the party"
		Villager.State.GO_BUTCHER, Villager.State.BUTCHERING: return "butchering the dead"
		Villager.State.GO_SKIN, Villager.State.SKINNING: return "butchering a beast"
		Villager.State.GO_BEAT: return "running to the fire"
		Villager.State.BEATING: return "beating out a fire"
		Villager.State.GO_MOURN, Villager.State.MOURNING: return "weeping over the dead"
		Villager.State.GO_CHOP, Villager.State.CHOPPING: return "felling timber"
		Villager.State.GO_QUARRY, Villager.State.QUARRYING: return "quarrying stone"
		Villager.State.GO_BUILD, Villager.State.BUILDING: return "building"
		Villager.State.GO_TAME, Villager.State.TAMING: return "taming a beast"
		Villager.State.GO_WORSHIP, Villager.State.WORSHIPPING: return "worshipping"
		Villager.State.GO_PREACH, Villager.State.PREACHING: return "on a mission"
		Villager.State.GO_FEED: return "feeding the animals"
		Villager.State.GO_BUILD_FARM, Villager.State.BUILDING_FARM: return "breaking new ground"
		Villager.State.GO_BUILD_EDUBBA, Villager.State.BUILDING_EDUBBA: return "raising the Edubba"
		Villager.State.GO_FISH, Villager.State.FISHING: return "fishing"
		Villager.State.HAULING: return "hauling to the storehouse"
		Villager.State.GO_BUILD_NEST, Villager.State.BUILDING_NEST:
			return "raising the creature's nest"
		Villager.State.GO_CIRCLE, Villager.State.CIRCLING: return "dancing the circle"
		Villager.State.GO_BUILD_SHOP, Villager.State.BUILDING_SHOP: return "raising a workshop"
		Villager.State.GO_WORK, Villager.State.WORKING: return "at work"
		Villager.State.PINNED: return "DOWN — they have hold of them"
		Villager.State.GO_ARM: return "running for a weapon"
		Villager.State.FIGHT: return "FIGHTING for their life"
		Villager.State.COURT: return "courting at the totem"
		Villager.State.FOLLOW_MOM: return "following mother"
		Villager.State.AT_SCHOOL: return "at school"
		Villager.State.TEACH: return "teaching the children"
		Villager.State.HIDE: return "hiding"
		Villager.State.LEAVING: return "going home"
		Villager.State.HIDDEN: return "indoors"
		Villager.State.FLEE: return "fleeing in terror"
		Villager.State.HELD: return "in the grip of a god"
		Villager.State.FALLING: return "airborne"
	return "?"


static func status_text(who: Villager) -> String:
	match who.state:
		Villager.State.DYING: return "SAVE ME!"
		Villager.State.SLEEPING: return "zzz"
		Villager.State.EATING: return "nom"
		Villager.State.FARMING: return "farm"
		Villager.State.HUNTING: return "hunt"
		Villager.State.CHOPPING: return "chop"
		Villager.State.QUARRYING: return "mine"
		Villager.State.BUILDING: return "build"
		Villager.State.TAMING: return "shhh"
		Villager.State.BUTCHERING: return "..."
		Villager.State.SKINNING: return "cut"
		Villager.State.GO_BEAT: return "fire!"
		Villager.State.BEATING: return "beat!"
		Villager.State.GO_MOURN: return "..."
		Villager.State.MOURNING: return "*sob*"
		Villager.State.WORSHIPPING: return "pray"
		Villager.State.PREACHING: return "hear me!"
		Villager.State.FISHING: return "fish?"
		Villager.State.HAULING: return "haul"
		Villager.State.GO_BUILD_NEST, Villager.State.BUILDING_NEST: return "nest"
		Villager.State.GO_CIRCLE, Villager.State.CIRCLING: return "dance"
		Villager.State.GO_ARM: return "arms!"
		Villager.State.FIGHT: return "FIGHT!"
		Villager.State.COURT: return "♥"
		Villager.State.FOLLOW_MOM: return "mama"
		Villager.State.AT_SCHOOL: return "abc"
		Villager.State.TEACH: return "teach"
		Villager.State.BUILDING_EDUBBA, Villager.State.GO_BUILD_EDUBBA: return "build"
		Villager.State.BUILDING_SHOP, Villager.State.GO_BUILD_SHOP: return "build"
		Villager.State.GO_WORK, Villager.State.WORKING: return "work"
		Villager.State.PLAY: return "wheee"
		Villager.State.HIDE: return "shh"
		Villager.State.LEAVING, Villager.State.HIDDEN: return ""   # see ChildSafety
		Villager.State.FLEE, Villager.State.FALLING: return "!!!"
		Villager.State.HELD: return "?!"
	if who.pregnant:
		return "+"
	return ""
