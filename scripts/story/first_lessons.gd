class_name FirstLessons
extends RefCounted
## THE FIRST QUEST, AS A STORYBOARD — and as a worked example of the format.
##
## This is your sequence, written out in the eight words Storyboard understands,
## so you can see what a beat looks like and rewrite it. Every line of it is
## data: change the words, reorder the beats, cut one, add three. Nothing below
## is machinery.
##
##   1  The creature is staked at its nest. Look at it.
##   2  FEED IT. Pick something up and give it to it.
##   3  TEACH IT TO FETCH by tying the lead to a thing instead of to the ground.
##   4  PRAISE or SCOLD what it did with what it fetched.
##   5  The stake comes out. The lead is yours now, and it knows the shape of
##      being led.
##
## WHAT I HAVE GUESSED AT, and what I would rather you told me:
##
##   * The wording of every line. Mine are placeholders in the game's voice.
##   * Whether beat 2 should hand it food or let it find the food itself.
##   * Whether beat 4 should FORCE a scold (the creature does something it
##     should not, on cue) or take whichever the player gives.
##   * Whether there is a shot at the top — the camera flying in over the
##     village to the nest before anything is asked. A beat with `look` and
##     `wait` and no `until` is exactly that, and there is none here yet.

## How long the opening shot holds before the first thing is asked of anybody.
const OPENING := 3.5


## BUILD THE BOARD. `who` is the creature, `stake` the post it is tied to.
static func board(who: Creature, tree: SceneTree) -> Array:
	var fed_at := [0]          # how much it had eaten when the beat opened
	var fetched := [false]
	var taught := [0]
	return [
		# 1. THE SHOT. No `until`, so it simply plays: the camera settles on the
		#    creature and the line sits there for a few seconds.
		{
			"say": "This is yours. It knows nothing, and it is tied here until "
				+ "you can lead it.",
			"look": who,
			"wait": OPENING,
		},
		# 2. FEED IT.
		{
			"say": "It is hungry and it cannot reach anything. Bring it something "
				+ "to eat.",
			"hint": "Drag a sheep, a fish or an armful of grain to it and let go "
				+ "gently at its feet.",
			"hold": who,
			"do": func() -> void: fed_at[0] = int(who.body.fat),
			"until": func() -> bool: return int(who.body.fat) > fed_at[0],
		},
		# 3. THE LEAD, TIED TO A THING. This is the lesson the whole quest is
		#    for: the gesture that means FETCH is the gesture that means GO,
		#    pointed at something instead of at the grass.
		{
			"say": "Now show it the lead. Point it at a THING, not at the "
				+ "ground, and it will go and fetch it.",
			"hint": "Put your hand over a sheep or a tree and press Lead.",
			"hold": who,
			"until": func() -> bool:
				if who.leash_thing != null:
					fetched[0] = true
				return fetched[0] and who.is_laden(),
		},
		# 4. PRAISE OR SCOLD. Either answer finishes it: the lesson is that the
		#    two buttons exist and that they land on what it just did.
		{
			"say": "Tell it what you think of that. Praise it, or scold it — "
				+ "it learns from you and from nothing else.",
			"hint": "Praise [P] or Scold [L], with your hand near it.",
			"hold": who,
			"do": func() -> void: taught[0] = who.lessons,
			"until": func() -> bool: return who.lessons > taught[0],
		},
		# 5. THE STAKE COMES OUT.
		{
			"say": "That is the whole of it. The rope is off — it is yours to "
				+ "lead now, and it will remember everything you do.",
			"look": func() -> Variant:
				var stake := CreatureStake.of(tree)
				return stake if stake != null else who,
			"wait": 4.0,
			"then": func() -> void: CreatureStake.pull_up(tree),
		},
	]
