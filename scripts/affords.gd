class_name Affords
extends RefCounted
## WHAT CAN BE DONE TO A THING — the game's adverbs, in one place.
##
## Godot groups are one flat namespace and this codebase had thirty-one of
## them, of which twenty-nine are NOUNS: "trees", "houses", "stores",
## "camera_rig". Those are registries — "where do I find the X" — and they are
## fine as they are, one class each, looked up by whoever needs that class.
##
## Exactly TWO were adverbs: "pickable" and "burnable". Those are the ones
## spoken across many classes by code that must not care which class it is
## holding, and two is not enough vocabulary to describe a world. The symptom
## is easy to spot once you know it: every time the answer to "what can I do
## with this?" is missing an adverb, somebody writes `if thing is SomeClass`
## instead, and now that file knows about that class forever.
##
## THIS IS THE LIST, and the rule for adding to it: an adverb earns its place
## when at least two unrelated classes can be spoken to the same way, and the
## code doing the speaking has no business knowing which is which. A verb only
## one class answers is a method, not an adverb.
##
## WHY IT MATTERS FOR ROCKS. A flint outcrop, a chalk face and a granite tor
## are three meshes and three yields and ONE adverb: you take a piece off them.
## With `QUARRIED` the hand and the creature never learn any of their names —
## they ask the group and call the verb. Without it, each new kind of rock is
## another `is RockDeposit` beside the last one, in two files that have nothing
## to do with geology.

## THE HAND CAN CLOSE ON IT AND CARRY IT AWAY, whole. The thing itself moves.
## Asked by the divine hand, the creature, the earthquake and the gust.
const PICKABLE := "pickable"

## IT CATCHES FIRE, and fire can destroy it. Owes `ignite`, `extinguish`,
## `damage`, `full_health` and `burn_down` — see tools/check_calls.py, which
## fails the build on a member that cannot answer all five.
const BURNABLE := "burnable"

## YOU TAKE A PIECE OFF IT AND LEAVE THE REST. The thing itself never moves:
## a rock face gives up a boulder, and what you are holding is the boulder.
##
## The distinction from PICKABLE is the whole point and is not a nicety — a
## hand that tries to lift a hillside gets a StaticBody3D dragged through the
## terrain, and a hand that refuses the hillside gets no stone at all. Owes
## `prise`, which returns the piece or null when the seam is spent.
const QUARRIED := "quarried"

## THE NEXT ONE IS `banked` — a storehouse takes it in and counts it — and it
## is deliberately NOT here yet. FoodStore still has to know food from stone to
## bank either, so the adverb would not remove a single `is FoodItem`; it would
## need `bank_into(store)` on both sides first. An adverb declared before it
## can carry its own weight is a constant with no members, which is worse than
## the branch it was meant to replace.

## EVERY ADVERB THERE IS, so a checker can walk them and a person can read them
## without grepping. Order is the order they were needed in.
const ALL: Array[String] = [PICKABLE, BURNABLE, QUARRIED]

## What a member of each group must be able to answer. An adverb with no verbs
## behind it is a label; one with verbs nobody implements is a crash waiting
## for the frame that line finally runs.
const OWES := {
	BURNABLE: ["ignite", "extinguish", "damage", "full_health", "burn_down"],
	QUARRIED: ["prise"],
}
