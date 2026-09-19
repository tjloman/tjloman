class_name CreatureKeeping
extends RefCounted
## WHAT REPETITION MAKES PERMANENT — the floor under everything the creature
## knows.
##
## Forgetting used to run to zero. Every value in the mind drifted toward
## nothing at a fixed rate, so a thing learned a hundred times and a thing
## learned once were both on their way out at the same speed, and the only
## question was how recently it had happened. A creature could not accumulate
## anything: it could only be recently reminded.
##
##     "There's no forgetting a concept once it has been learned... there's no
##      point to having to relearn things at a rate slower than it forgets
##      things. Retention is key to growth and progression."
##
## So a thing fades toward a FLOOR its own history earned, and never past it.
## The floor is the deepest that value ever reached, times what repetition has
## made of it: once is nothing, a dozen times is a third, fifty times is most of
## what can ever be kept. A creature that has fished four hundred times may go
## off fishing, and it does not forget how to want to.
##
## THE SAME SHAPE AS THE SHRINK LIMITER, deliberately. A high-water mark, a
## share of it that may never be lost, and a fade that stops dead when it gets
## there. Everything the player can lose in this game is now bounded: a fifth of
## his size in a sitting, a quarter of what he knows, and none of his nest.
##
## AND FORGETTING IS SLOWER THAN LEARNING, everywhere, which is the other half
## of the same sentence. tools/keeping.py holds every pair of rates to it — a
## store that forgets faster than it learns is a store the creature has to keep
## relearning, and a creature with nothing left over to learn anything NEW.

## The most of a thing repetition can make permanent. Not all of it: a creature
## that could never lose a quarter of what it once knew would be a database.
const KEPT_MOST := 0.75
## Repetitions at which half of that much is held. A dozen is a morning's worth
## of doing something, and it buys a third of it forever.
const HALF_KEPT := 12.0


## How much of its deepest self a value keeps, having been learned this often.
static func kept(times: int) -> float:
	return KEPT_MOST * float(times) / (float(times) + HALF_KEPT)


## IT HAS BEEN LEARNED AGAIN. Deepen the mark and count the repetition — the two
## facts the floor is made of, kept beside the store rather than inside it so
## nothing that reads the store has to know this file exists.
static func learned(held: Dictionary, key: String, value: float) -> void:
	var was: Array = held.get(key, [0.0, 0])
	held[key] = [maxf(float(was[0]), absf(value)), int(was[1]) + 1]


## Fade it, down to what it has earned the right to keep and no further.
static func fade(held: Dictionary, key: String, value: float, step: float) -> float:
	var was: Array = held.get(key, [0.0, 0])
	var least: float = float(was[0]) * kept(int(was[1]))
	if absf(value) <= least:
		return value
	return move_toward(value, signf(value) * least, step)


## What a floor is worth in plain words, for anything that wants to say how
## firmly a thing is known rather than how strongly it is felt.
static func rooted(held: Dictionary, key: String) -> float:
	var was: Array = held.get(key, [0.0, 0])
	return kept(int(was[1]))


## Drop what was never really learned. A store with a floor under every key it
## ever touched grows forever; a key with one repetition and nothing left of its
## value is not a memory, it is a row.
static func prune(held: Dictionary, store: Dictionary) -> void:
	var gone: Array[String] = []
	for key: String in held:
		if not store.has(key):
			gone.append(key)
	for key in gone:
		held.erase(key)
