class_name CreatureFeeding
extends RefCounted
## WHAT YOUR HAND SAYS WHILE THE CREATURE IS HOLDING SOMETHING.
##
## THERE WAS NO WAY TO TELL A CREATURE TO EAT. `_intent_for` decided the moment
## the thing touched its hands — food goes to the granary unless it happens to
## be hungrier than FEEDS_ITSELF_ABOVE — and nothing afterwards could change its
## mind. Not praise, not a scolding, not a gesture. So a player holding a meal
## out to a creature they wanted to FEED watched it carry the meal off to the
## store, and had no word at all for "no, that, now".
##
## It was worse than that underneath: `Creature._eat_carried` knew how to eat a
## villager, a corpse and a beast, and a loaf of bread fell straight through it
## to `_release_carried` and got PUT DOWN. There was no path anywhere in the
## game by which a creature ate food out of its own hands.
##
## A HAND ON THE FLANK IS THE WORD. Stroke it while it is holding something and
## it eats the thing; scold it and it sets the thing down. That is the plainest
## teaching moment there is — what is in its hands, what your hand said, and the
## consequence, all inside one second — which is why Black & White taught diet
## this way and why nothing else does it as well.
##
## AND IT IS A LESSON, NOT A COMMAND. `_eat_carried` books the verb and the
## KIND of thing eaten, so what the mind learns is a diet rather than the
## abstract act of eating. Stroke it over a haunch and you have taught it to
## take meat from your hand. Stroke it over a villager and you have taught it
## something else, and it will not need asking twice.

## What a stroke and a scolding are worth as teaching, against the deed they
## land on. A scolding is lighter than praise on purpose: it is a correction,
## and a creature that is put off a whole food group by one telling-off is a
## creature you cannot raise.
const TAUGHT_YES := 3.0
const TAUGHT_NO := -2.5


## Praised with its hands full. Returns true when that was the whole meaning of
## the praise, so the caller stops there rather than also crediting whatever it
## happened to have finished doing beforehand.
static func stroked(who: Creature) -> bool:
	if not who.is_laden():
		return false
	who._carry_intent = "eat"
	who._eat_carried()
	who.feel("affection", 0.85)
	who.mind.experience("praised", 2.0)
	if who._deed_verb != "":
		who.mind.teach(who._deed_verb, who._deed_type, TAUGHT_YES)
		who.mind.judge(who._deed_verb, 0.25, false)
		who.morality = who.mind.temperament
	return true


## Scolded with its hands full: put it down, and learn that it was not food.
## The point of it is that a player can head a habit off BEFORE it forms rather
## than punish it after — which is the only kind of correction that teaches
## anything.
static func scolded(who: Creature) -> bool:
	if not who.is_laden():
		return false
	who.mind.teach("eat", CreatureEyes.kind_of(who._carried), TAUGHT_NO)
	who._release_carried(true)
	who.mind.experience("scolded", -2.0)
	GameState.announce("Your creature sets it down, and looks at you.")
	who._decide()
	return true
