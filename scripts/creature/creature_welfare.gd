class_name CreatureWelfare
extends RefCounted
## HOW IT HAS BEEN TREATED, and what that does to the mind it is trying to think
## with.
##
## Everything else about the creature answers "what did it learn". This answers
## something underneath that: WHAT IS IT ABLE TO LEARN WITH. A beast that is fed,
## rested and safe has spare attention — it watches the world over its own
## shoulder while its hands are busy, it takes other creatures' feelings in, it
## sleeps like a stone, and it picks things up quickly. A beast that is worked to
## exhaustion, starved, and struck by the thing it depends on has none of that.
## It is watchful in the bad sense — it sleeps badly because sleeping is
## dangerous — and almost nothing gets in, because everything it has is spent on
## the next blow.
##
## SO CRUELTY IS NOT A FASTER PATH TO AN OBEDIENT CREATURE. It is a slower path
## to a stupider one. That is the design claim this file exists to make true, and
## it is made in the arithmetic rather than in a rule that forbids anything: a
## cruel player CAN raise a creature and it will do as it is told, and it will
## also be bad at everything, unable to feel much, and prone to rage.
##
## THE TETHER IS THE DARK PART and it is deliberate. Pain from your own god does
## not simply drive a creature away. Intermittent pain followed by relief is the
## most binding schedule there is, and a creature that has nowhere else to go
## forms an attachment out of it that looks like devotion and is not. A tethered
## creature obeys closely, startles constantly, and cannot be taught — which is
## the honest shape of the thing, and it is why obedience is not scored as
## success anywhere in this file.

## HOW FAST THE SLOW NUMBERS MOVE, per second of being fed, rested, struck or
## ignored. All of them are slow on purpose: welfare is a life, not a mood, and
## nothing here should be repairable or ruinable inside a minute.
const CARE_GAIN := 0.9
const CARE_FADE := 0.35
const HARM_GAIN := 1.0
const HARM_FADE := 0.22

## Acute pain: what a blow feels like now, and how fast that ebbs. Separate from
## the lasting harm, because a creature can be in agony and unharmed in the long
## run, or crippled and comfortable at this moment.
const PAIN_FADE := 5.5

## What counts as going without. Below these the body is being neglected, and it
## accrues — one missed meal is nothing, a life of them is the whole story.
const HUNGRY_AT := 70.0
const SPENT_AT := 25.0

## THE TETHER. Pain from the god builds it; kindness with no pain lets it go
## slack, very slowly. It decays far more slowly than it forms, which is the
## cruel and accurate part.
##
## GAIN IS DELIBERATELY LOW so that RELIEF is what does the binding. Measured
## over twenty-five minutes of a fed, rested creature struck once a minute: with
## no comfort afterwards the tether reaches 48, and with a kindness a few seconds
## after each blow it reaches 98. At the first value tried, both saturated and
## the difference was invisible — which would have made the comment below a
## claim the arithmetic did not support. Intermittent relief is the thing that
## binds, and now it measurably is.
const TETHER_GAIN := 0.22
const TETHER_FADE := 0.04
const TETHER_RELIEF := 1.7   # relief after pain binds harder than either alone

## WHERE A BODY STOPS GROWING AND STARTS COMING OFF. Below STUNT_AT food buys
## nothing; below SHRINK_AT the creature wastes, and what a player has done to it
## becomes visible from across the valley. THRIVE_BONUS is the other end: a
## cherished creature outgrows what its meals alone would explain.
const STUNT_AT := -0.30
const SHRINK_AT := -0.62
const THRIVE_BONUS := 0.55
const SHRINK_RATE := 0.45

## Nothing here may swing a faculty further than this either way, so a wretched
## creature is hampered rather than inert and a cherished one is quick rather
## than omniscient.
const SWING := 0.6

var pain := 0.0        # 0..100, acute, right now
var care := 0.0        # 0..100, a life of being fed, rested and praised
var harm := 0.0        # 0..100, a life of being starved, worked and struck
var tether := 0.0      # 0..100, attachment built out of pain and relief
## HOW MANY TIMES ITS OWN GOD HAS STRUCK IT. A plain count that never decays,
## kept because the nest wall sets it beside how much the creature trusts you,
## and that pairing only says anything if the number is the whole truth rather
## than a fading impression.
var struck := 0
var _since_hurt := 999.0


## The slow turn of a life. Fed and rested raises care; hungry and spent raises
## harm; both fade, so a creature is always mostly what it has been LATELY.
func tick(delta: float, hunger: float, energy: float, mood: float) -> void:
	pain = maxf(pain - PAIN_FADE * delta, 0.0)
	_since_hurt += delta
	var wanting := hunger > HUNGRY_AT
	var spent := energy < SPENT_AT
	if wanting or spent:
		harm = minf(harm + HARM_GAIN * delta * (2.0 if wanting and spent else 1.0), 100.0)
	else:
		harm = maxf(harm - HARM_FADE * delta, 0.0)
	if not wanting and not spent and mood > 55.0:
		care = minf(care + CARE_GAIN * delta, 100.0)
	else:
		care = maxf(care - CARE_FADE * delta, 0.0)
	# A tether left alone goes slack, very slowly. A creature does not forget
	# being beaten because a week went by, but it does stop bracing for it.
	tether = maxf(tether - TETHER_FADE * delta, 0.0)


## STRUCK. By the god, or by anything else — but by the god is a different wound,
## and it is the one that builds the tether.
func hurt(amount: float, by_god: bool) -> void:
	pain = minf(pain + amount, 100.0)
	harm = minf(harm + amount * 0.35, 100.0)
	care = maxf(care - amount * 0.5, 0.0)
	if by_god:
		tether = minf(tether + amount * TETHER_GAIN, 100.0)
		struck += 1
		_since_hurt = 0.0


## KINDNESS. Praise, food from your hand, a healing — the ordinary good of being
## looked after. Soon after a blow it binds instead of mending, which is the
## whole mechanism of the thing and the reason cruelty followed by comfort makes
## the most devoted and least capable creature in the game.
func comfort(amount: float) -> void:
	care = minf(care + amount, 100.0)
	if _since_hurt < 12.0:
		tether = minf(tether + amount * TETHER_RELIEF, 100.0)
	else:
		harm = maxf(harm - amount * 0.3, 0.0)


## THE NET OF A LIFE, -1 (wretched) .. +1 (cherished). Everything below reads
## this rather than the parts, so there is one place to argue with.
func standing() -> float:
	return clampf((care - harm) / 100.0, -1.0, 1.0)


## HOW MUCH OF THE WORLD GETS IN. A well-kept creature has attention to spare and
## uses it on everything around it; a wretched one is spending all of it on
## itself. The tether counts AGAINST this — a creature braced for the next blow
## is not taking in the village, it is watching one thing very hard.
func watchfulness() -> float:
	var spare := standing() - tether / 100.0 * 0.5
	return clampf(1.0 + spare * SWING, 1.0 - SWING, 1.0 + SWING)


## HOW DEEPLY IT SLEEPS. Content and cared-for, it sleeps like a stone and is
## slow to rouse. Hungry, exhausted, or expecting to be hurt, it sleeps thin and
## wakes at everything — which is not restfulness, it is vigilance, and it is
## why a mistreated creature never quite catches up on rest.
func sleep_depth() -> float:
	return clampf(0.5 + standing() * 0.45 - tether / 100.0 * 0.35, 0.08, 1.0)


## HOW FAST ANYTHING SINKS IN. The claim of the whole file: misery does not make
## a creature biddable, it makes it slow. A tethered creature is the worst
## learner in the game — it is not attending to the lesson, it is attending to
## you.
func learning() -> float:
	var t := tether / 100.0
	return clampf(1.0 + standing() * SWING - t * 0.55, 0.25, 1.0 + SWING)


## HOW MUCH OTHER CREATURES' FEELINGS REACH IT. Emotional availability is the
## first thing hardship takes and the last thing it gives back, so this swings
## harder than the rest.
func openness() -> float:
	return clampf(1.0 + standing() * (SWING * 1.3) - tether / 100.0 * 0.6, 0.1, 2.0)


## WHAT IT REACHES FOR WHEN IT IS NOT BUSY. A cherished creature drifts toward
## the quiet, companionable things — praying, dancing, sitting with people. A
## wretched one drifts toward rage and wreckage. This is returned as a nudge to
## be added to a deed's value, NOT as a rule about which deed to pick: it tilts
## the ballot, and a lifetime of teaching can tilt it back.
func leaning(verb: String) -> float:
	var s := standing()
	if verb in ["pray", "dance", "commune", "soothe", "watch", "tend"]:
		return s * 0.9
	if verb in ["smash", "throw", "eat_kin"]:
		return -s * 0.7 + tether / 100.0 * 0.3
	return 0.0


## WHAT A LIFE DOES TO A BODY, as a multiplier on everything food would
## otherwise buy. This is the plainest statement the system makes: a creature
## that is starved, worked and struck does not put on size even when it is fed,
## and one taken past the far end of that does not merely stop growing — it
## starts coming off. A cherished creature outgrows what its meals alone would
## explain, because thriving is not the same as eating.
##
## Below STUNT_AT growth stops. Below SHRINK_AT it reverses, and what a player
## has done to it becomes something they can SEE from across the valley, because
## the beast is smaller than it was last week.
func growth_factor() -> float:
	var s := standing()
	if s >= 0.0:
		return 1.0 + s * THRIVE_BONUS
	# Tapering to nothing as it approaches the stunting line, rather than
	# falling off it: there is no single meal that stops a creature growing.
	return maxf(1.0 - s / STUNT_AT, 0.0)


## HOW FAST IT WASTES, in stature-steps a second, once it is past bearing. Zero
## for anything short of that — a hungry week should not shrink a creature, only
## a life of being tortured should.
func wasting() -> float:
	var s := standing()
	if s > SHRINK_AT:
		return 0.0
	return (SHRINK_AT - s) / (1.0 + SHRINK_AT) * SHRINK_RATE


## WHAT IT SHEDS ON THE WORLD AROUND IT, 0..1. A creature raised well does not
## merely behave well — it is good to be near. Fields it walks past come on,
## herds settle, trees put out. This is the visible other end of the same axis
## that shrinks a tortured one, and both are meant to be legible from a distance
## without reading a single number.
func radiance() -> float:
	var s := standing() - tether / 100.0 * 0.4
	return clampf(s, 0.0, 1.0)


## In plain words, for the dashboard. A player should be able to see what they
## have made without reading a number.
func account() -> String:
	if tether > 45.0:
		return "bound to you by fear"
	var s := standing()
	if s > 0.45:
		return "cherished"
	if s > 0.15:
		return "well looked after"
	if s < -0.45:
		return "wretched"
	if s < -0.15:
		return "going without"
	return "getting by"


## RADIATING IT. A creature that has been raised well is good to be near, and
## the world should show that without anybody being told: fields it passes come
## on, trees put out, herds settle. It goes through the same door rain does, so
## there is one notion of a thing being nourished rather than a parallel one for
## divine wellbeing.
##
## Nothing happens at all below a real threshold. A merely contented creature
## should not be quietly fertilising the county.
static func shed(who: Creature, seconds: float) -> void:
	var glow := who.welfare.radiance()
	if glow < 0.35:
		return
	var reach := 8.0 + glow * 10.0
	var worth := seconds * glow
	for group: String in ["trees", "farms"]:
		for n in who.get_tree().get_nodes_in_group(group):
			var thing := n as Node3D
			if not is_instance_valid(thing):
				continue
			if thing.global_position.distance_to(who.global_position) > reach:
				continue
			if thing.has_method("rain"):
				thing.call("rain", worth)
			elif thing.has_method("water"):
				thing.call("water", worth)
	for h in who.get_tree().get_nodes_in_group("herds"):
		var herd := h as Herd
		if is_instance_valid(herd) and herd.global_position.distance_to(
				who.global_position) < reach + herd.spread():
			herd.calmed(worth * 0.02)


func to_dict() -> Dictionary:
	return {"pain": pain, "care": care, "harm": harm, "tether": tether, "struck": struck}


func from_dict(data: Dictionary) -> void:
	pain = float(data.get("pain", 0.0))
	care = float(data.get("care", 0.0))
	harm = float(data.get("harm", 0.0))
	tether = float(data.get("tether", 0.0))
	struck = int(data.get("struck", 0))
