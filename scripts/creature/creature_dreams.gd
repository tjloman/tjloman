class_name CreatureDreams
extends RefCounted
## WHAT HE DREAMT, and what the dreaming was for.
##
## Sleep was a place energy came back. He lay down, a number went up, he stood
## up again, and nothing about the day he had just had was any different for his
## having slept on it. Meanwhile the one thing in his mind that ran on a clock
## was FORGETTING — so sleep was, very precisely, the least useful thing he
## could be doing with his time.
##
##     "Sleeping should sort of save a dream file within the creature's mind. It
##      remembers its favorite things, or what made it scared... new places it
##      went to that day, and how the world was."
##
## So a night's sleep now does two things, and they are the same thing.
##
## IT REHEARSES. The episodes of the day that mattered most are gone over again
## while he is under, and going over a thing does not change what he thinks of
## it — it makes what he thinks STICK. Rehearsal deepens the floor (see
## CreatureKeeping) and touches the value not at all, which is the honest shape
## of consolidation and also the safe one: no amount of sleeping can talk a
## creature into anything.
##
## AND HOW MUCH OF IT HAPPENS IS HOW WELL HE HAS BEEN KEPT. A cherished creature
## sleeps like a stone and goes over two dozen memories a night. A wretched one
## sleeps thin, at a twelfth of that, because it is not resting, it is keeping
## watch — so mistreatment does not merely make him slow to learn, it stops what
## he did learn from ever setting. That is the same claim CreatureWelfare makes
## everywhere else, finally made about memory itself.
##
## THE DREAM IS THE RECEIPT. Eight nights are kept, in his own terms: the thing
## he loved, the thing that frightened him, ground he had never walked before,
## and how the world was while he was out in it. It goes on the nest wall, and
## it is the only readout in the game that says what a day was LIKE rather than
## what it changed.

## Nights kept. Eight is a week and a bit: long enough that a player who leaves
## and comes back can see what he has been doing, short enough to read at a
## glance on a wall.
const KEEPS := 8
## Seconds of deep sleep per memory gone over, and the most any one night can
## set.
##
## IN THE GAME'S OWN TIME, not in ours. A day here is 320 seconds and a night's
## sleep is about ten of them: he lies down under 55 energy and gets up at
## between 55 and 92 of it, gaining two a second plus five more for how deeply
## he is under. Written at a plausible-sounding twelve seconds a memory, a
## cherished creature would have rehearsed NOTHING on any night of its life,
## because no night is twelve seconds long. At this rate a deep sleeper sets
## about thirteen a night.
##
## AND A THIN SLEEPER STILL SETS SOMETHING. Dividing the interval by the depth
## outright had a tormented creature setting exactly nothing, ever — measured,
## not feared — and a creature that cannot keep ANY of its day is one the player
## can put beyond reach of their own teaching by neglecting it for a week. Loss
## is bounded everywhere else in this game and it is bounded here: the worst
## sleep in the world still runs at a quarter of the best, which is about two
## memories a night against thirteen.
const THIN_SETS := 0.25
const REHEARSE_EVERY := 0.45
const MOST_A_NIGHT := 16
## How much of a full step of forgetting a night costs. The rest of it is spent
## at decisions — between them they come to roughly what the old wall clock
## charged in a quarter of an hour, and they are only ever spent while living.
const PER_NIGHT := 4.0
## A place walked fewer times than this is still new country to him.
const STILL_NEW := 3

var nights: Array = []
var _slept := 0.0
var _rehearsed := {}
var _began := 0.0


## ASLEEP. Count the night, and go over another memory whenever enough of it has
## passed — sooner the more deeply he is sleeping.
func drift(who: Creature, delta: float) -> void:
	if _slept <= 0.0:
		_began = GameState.clock
		_rehearsed.clear()
	_slept += delta
	var depth: float = maxf(who.welfare.sleep_depth(), 0.08)
	if _rehearsed.size() >= MOST_A_NIGHT:
		return
	var pace := REHEARSE_EVERY / (THIN_SETS + (1.0 - THIN_SETS) * depth)
	if _slept < pace * float(_rehearsed.size() + 1):
		return
	var went: String = who.mind.consolidate(_rehearsed)
	if went != "":
		_rehearsed[went] = true


## AWAKE, and the night is written down. This is also where the night's share of
## forgetting is spent: what was gone over is held, and everything else thins a
## little, which is as good a definition of a night's sleep as the game needs.
func wake(who: Creature) -> void:
	if _slept <= 0.0:
		return
	var dreamt := {
		"at": _began, "slept": _slept, "held": _rehearsed.size(),
		"loved": _loved(who), "feared": _feared(who),
		"new": _new_ground(who), "world": _how_it_was(who),
	}
	nights.append(dreamt)
	while nights.size() > KEEPS:
		nights.pop_front()
	who.mind.decay(PER_NIGHT)
	_slept = 0.0


## THE BEST THING IN HIS DAY, by what he thinks of it rather than by what it did
## for him — a creature dreams of what it loves, not of what paid.
func _loved(who: Creature) -> String:
	var best := ""
	var most := 0.4
	for k: String in who.mind.q:
		if float(who.mind.q[k]) > most:
			most = float(who.mind.q[k])
			best = k
	return best


## And the worst of it. The deed it has come to dread, if it has one.
func _feared(who: Creature) -> String:
	var worst := ""
	var least := -0.4
	for k: String in who.mind.q:
		if float(who.mind.q[k]) < least:
			least = float(who.mind.q[k])
			worst = k
	return worst


## GROUND HE HAD NOT WALKED BEFORE. Taken from where he actually was today
## rather than from the whole map, so a creature that spent the day in its own
## field dreams of nothing new — which is the point of saying it at all.
func _new_ground(who: Creature) -> int:
	var fresh := {}
	for e: Dictionary in who.mind.beliefs.episodes:
		if float(e.get("at", 0.0)) < _began - GameState.DAY_SECONDS:
			continue
		var where := String(e.get("place", ""))
		var known: Dictionary = who.mind.beliefs.places.get(where, {})
		if where != "" and int(known.get("visits", 0)) <= STILL_NEW:
			fresh[where] = true
	return fresh.size()


## HOW THE WORLD WAS: whichever circumstance was true of most of his day. It is
## read off the episodes he actually lived rather than off the world now,
## because a dream is about the day that was.
func _how_it_was(who: Creature) -> String:
	var tally := {}
	for e: Dictionary in who.mind.beliefs.episodes:
		if float(e.get("at", 0.0)) < _began - GameState.DAY_SECONDS:
			continue
		var ctx: Dictionary = e.get("ctx", {})
		for f: String in ctx:
			if float(ctx[f]) > 0.5:
				tally[f] = int(tally.get(f, 0)) + 1
	var most := ""
	var top := 1
	for f: String in tally:
		if int(tally[f]) > top:
			top = int(tally[f])
			most = f
	return most


## A NIGHT IN PLAIN WORDS, for the nest wall. Nothing here is a number: a player
## should be able to read what their creature's week has been like the way they
## would read somebody's face.
func told(limit := 3) -> Array:
	var said := []
	for night: Dictionary in _newest(limit):
		var parts := []
		if String(night["loved"]) != "":
			parts.append("dreamt of " + _doing(String(night["loved"])))
		if String(night["feared"]) != "":
			parts.append("and shied from " + _doing(String(night["feared"])))
		if int(night["new"]) > 0:
			parts.append("having walked ground it had never seen")
		var when := String(night["world"])
		if when != "":
			parts.append("all of it " + String(
				CreatureBeliefs.WHEN_PHRASE.get(when, when)))
		if parts.is_empty():
			parts.append("slept without dreaming")
		said.append(" ".join(parts) + _setting(int(night["held"])))
	return said


## What a night set, said as a quality of the sleep rather than as a count —
## because that is what it is, and because "held 2 memories" is a spreadsheet.
func _setting(held: int) -> String:
	if held >= MOST_A_NIGHT - 4:
		return ", and woke with the whole of it."
	if float(held) >= float(MOST_A_NIGHT) / 3.0:
		return ", and kept most of it."
	if held > 0:
		return ", and kept a little of it."
	return ", and kept none of it."


func _doing(key: String) -> String:
	var parts := key.split("|")
	var doing: String = CreatureBeliefs.VERB_PHRASE.get(parts[0], String(parts[0]) + " %s")
	if doing.contains("%s"):
		doing = doing % (parts[1] if parts.size() > 1 else "things")
	return doing


func _newest(limit: int) -> Array:
	var out := nights.duplicate()
	out.reverse()
	return out.slice(0, limit)


func to_dict() -> Dictionary:
	return {"nights": nights.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	nights = (data.get("nights", []) as Array).duplicate(true)
