class_name CreatureLook
extends RefCounted
## How the creature LOOKS, split out from how it thinks.
##
## Its hide and eyes reflect its soul: a gentle beast is pale and calm-eyed; a
## monster darkens, reddens, and its pupils burn. Its face carries whatever it
## is feeling. On a custom model both ride on instance shader params
## ("alignment" -1..+1 and "expression"), plus a "menace" blend shape if the
## mesh has one — so custom art picks all of this up for free.

## Eye shapes (scale x,y) for the procedural face, one per emotion.
const EXPR_EYE := {
	"neutral": Vector2(1.0, 1.0), "happy": Vector2(1.1, 0.5), "sad": Vector2(0.9, 0.7),
	"angry": Vector2(1.25, 0.55), "scared": Vector2(1.35, 1.4), "curious": Vector2(1.1, 1.2),
	"love": Vector2(1.2, 1.15), "hurt": Vector2(0.8, 0.55),
}
## A numeric code per emotion, handed to a model shader as the "expression"
## instance param so custom art can switch faces.
const EXPR_CODE := {
	"neutral": 0.0, "happy": 1.0, "sad": 2.0, "angry": 3.0,
	"scared": 4.0, "curious": 5.0, "love": 6.0, "hurt": 7.0,
}

## How bright the creature's own light burns at night, how far it reaches at
## its smallest and largest, and how fast it eases. See `radiance`.
const RADIANCE := 2.4
const RADIANCE_REACH_MIN := 7.0
const RADIANCE_REACH_MAX := 34.0
const RADIANCE_EASE := 0.9



## WORDS FOR A STATE ------------------------------------------------------------
##
## Keyed by the STATE'S NAME rather than the enum, so this file never has to
## name Creature and the two can stay independent of one another.

## The semantic clip a rigged model plays. Missing clips are ignored, so a model
## with only walk/idle still animates sensibly.
const ANIM := {
	"SLEEPING": "sleep", "EATING": "eat",
	"GO_TEND": "work", "TENDING": "work", "FISHING": "work", "CAST": "work",
	"WATCH": "idle", "SULK": "idle", "LOUNGE": "idle", "PRAY": "idle",
	"CARRYING": "carry", "PLAY": "play", "DANCE": "play",
	"GUARD": "guard", "COMMUNE": "guard", "SOOTHE": "idle", "HEED": "idle",
	"CATCH": "run", "FLEE": "run", "RUN": "run", "SHUN": "run", "DEPART": "run",
	"SMASH": "attack", "LEASHED": "walk", "MIMIC": "walk",
}

## A plain-language phrase for the creature dashboard.
const DOING := {
	"IDLE": "pondering",
	"WANDER": "exploring",
	"SEEK_FOOD": "hunting for a snack",
	"EATING": "eating happily",
	"GO_TEND": "helping on the farm",
	"TENDING": "helping on the farm",
	"SLEEPING": "sleeping",
	"WATCH": "watching the villagers, learning",
	"CATCH": "chasing something down",
	"GO_FISH": "fishing",
	"FISHING": "fishing",
	"GO_STORE": "raiding the granary",
	"SMASH": "smashing something",
	"FLEE": "fleeing, frightened",
	"CAST": "working a miracle",
	"LEASHED": "going where you sent it",
	"PLAY": "playing",
	"GUARD": "standing guard",
	"SULK": "sulking",
	"LOUNGE": "lounging, watching the world",
	"DANCE": "dancing for the village",
	"PRAY": "leading the prayers",
	"COMMUNE": "holding court before the people",
	"MIMIC": "shadowing your hand, copying you",
	"SHUN": "keeping away from you",
	"DEPART": "walking away from you, for good",
	"SOOTHE": "sitting with someone who is frightened",
	"HEED": "stopped, looking up at you",
}

## The little word that floats over its head.
const SAYS := {
	"SLEEPING": "zzz", "EATING": "nom nom", "SEEK_FOOD": "food?",
	"TENDING": "help!", "WATCH": "hmm...", "CATCH": "!!", "FISHING": "...",
	"GO_GATHER": "for you!", "PLAY": "wheee!", "GUARD": "grrr", "SULK": ":(",
	"SMASH": "RAAWR", "FLEE": "!!!", "CAST": "***", "LEASHED": "yes?",
	"LOUNGE": "~", "DANCE": "la la", "PRAY": "ommm", "COMMUNE": "behold",
	"RUN": "whoosh", "MIMIC": "like this?", "SHUN": "...", "DEPART": "goodbye",
	"SOOTHE": "there, there", "HEED": "...?",
}


## Recolour hide, pupils and shader params for a soul at `align` (-1..+1).
static func apply_alignment(align: float, fur_mat: StandardMaterial3D,
		pupils: Array, model_meshes: Array) -> void:
	var menace := maxf(-align, 0.0)
	var grace := maxf(align, 0.0)
	if fur_mat != null:
		var fur := Color(0.55, 0.42, 0.3)
		fur = fur.lerp(Color(0.78, 0.7, 0.52), grace * 0.6)     # good: pale, warm
		fur = fur.lerp(Color(0.26, 0.12, 0.11), menace * 0.85)  # evil: dark, blood-dark
		fur_mat.albedo_color = fur
		fur_mat.emission_enabled = menace > 0.45
		fur_mat.emission = Color(0.45, 0.05, 0.04)
		fur_mat.emission_energy_multiplier = menace * 0.7
	var pupil := Color.BLACK.lerp(Color(0.95, 0.12, 0.05), menace)  # eyes burn when wicked
	for p in pupils:
		if is_instance_valid(p) and (p as MeshInstance3D).material_override != null:
			(p as MeshInstance3D).material_override.albedo_color = pupil
	for m in model_meshes:
		if is_instance_valid(m):
			(m as GeometryInstance3D).set_instance_shader_parameter("alignment", align)
			set_blend_shape(m as GeometryInstance3D, "menace", menace)


## GODLY RADIANCE ---------------------------------------------------------------
##
## The creature's own light: the one light in the world that is always where
## the player is looking, and so the one worth spending unconditionally. Night
## used to be unreadable on a phone; now, whatever else you cannot make out,
## you can always find your creature.
##
## Reach is in metres of world, at the smallest and the largest the beast gets
## (the four numbers themselves are up with the other constants).


## Ease the halo toward what the hour, the size and the working ask for, and
## hand back its new steady energy. Eased rather than switched, so dusk brings
## it up the way an ember comes up and dawn takes it away without a blink.
##
## `body_scale` is the creature's own scale: Godot scales a light's reach along
## with its parent, and the beast grows to fifteen times its own size, so the
## reach meant here is divided back out.
static func radiance(halo: OmniLight3D, energy: float, delta: float,
		elevation: float, grown: float, align: float,
		working: bool, body_scale: float) -> float:
	var darkness := clampf(-elevation * 2.2, 0.0, 1.0)
	var grand := lerpf(0.5, 1.0, grown)
	var want := RADIANCE * darkness * grand * (1.7 if working else 1.0)
	var lit := move_toward(energy, want, RADIANCE_EASE * delta)
	halo.light_energy = lit
	halo.visible = lit > 0.01
	if halo.visible:
		halo.light_color = radiance_color(align)
		halo.omni_range = lerpf(RADIANCE_REACH_MIN, RADIANCE_REACH_MAX, grown) \
			/ maxf(body_scale, 0.01)
	return lit


## WHAT COLOUR A CREATURE BURNS IN THE DARK, for a soul at `align` (-1..+1).
##
## Its own light is the last thing left when night falls, so it says what the
## beast has become without a word: a saint is warm gold, a monster burns low
## and red, and a creature that has settled on neither gives off the plain cold
## moon-white of something that has not made up its mind.
##
## The palette itself lives in GameState, because the god's hand burns by the
## same rules — and the whole point of the colour is being able to see at a
## glance that a gold hand has raised a red creature.
static func radiance_color(align: float) -> Color:
	return GameState.divine_light(align)


## Ease the eyes toward the shape of the current feeling.
static func apply_expression(emotion: String, delta: float,
		eyes: Array, model_meshes: Array) -> void:
	var target: Vector2 = EXPR_EYE.get(emotion, Vector2.ONE)
	var t := minf(delta * 10.0, 1.0)
	for e in eyes:
		if is_instance_valid(e):
			var eye := e as MeshInstance3D
			eye.scale.x = lerpf(eye.scale.x, target.x, t)
			eye.scale.y = lerpf(eye.scale.y, target.y, t)
	for m in model_meshes:
		if is_instance_valid(m):
			(m as GeometryInstance3D).set_instance_shader_parameter(
				"expression", EXPR_CODE.get(emotion, 0.0))


## Set a named blend shape on a model mesh if it has one (else a no-op).
static func set_blend_shape(mesh: GeometryInstance3D, sh_name: String, value: float) -> void:
	if not (mesh is MeshInstance3D):
		return
	var mi := mesh as MeshInstance3D
	var idx := mi.find_blend_shape_by_name(sh_name)
	if idx >= 0:
		mi.set_blend_shape_value(idx, value)


## Plain-word scales for the dashboard and hover. Pure presentation, kept with
## the rest of how the creature READS rather than how it thinks.
static func morality_word(morality: float) -> String:
	if morality > 60.0:
		return "angelic"
	if morality > 20.0:
		return "gentle"
	if morality > -20.0:
		return "wild"
	if morality > -60.0:
		return "vicious"
	return "monstrous"


static func mood_word(mood: float) -> String:
	if mood > 80.0:
		return "delighted"
	if mood > 55.0:
		return "cheerful"
	if mood > 35.0:
		return "content"
	if mood > 15.0:
		return "glum"
	return "wretched"


## What it is doing, in words. The few states whose phrasing depends on WHAT it
## is carrying take that as `cargo`; everything else ignores it.
static func doing_word(state_name: String, carry_intent: String, cargo: String) -> String:
	match state_name:
		"GO_GATHER":
			return "fetching %s for the store" % cargo
		"RUN":
			return "running with %s on its back" % cargo if cargo != "" \
				else "running, just to run"
		"CARRYING":
			match carry_intent:
				"deliver": return "carrying %s to the store" % cargo
				"eat": return "about to eat what it caught"
				"gift": return "bringing a gift to the pen"
				"snatch": return "making off with someone"
				"hurl": return "winding up to throw something"
			return "carrying something"
	return DOING.get(state_name, "?")


## What to call the thing it's hauling — honest about lumber and stone, not
## "food" for everything.
## Variant (not Node3D): the carried/targeted item may have been freed between
## the creature's physics tick and a HUD read, and passing a freed object to a
## typed parameter crashes. Guard it here instead.
static func carriable_word(item: Variant) -> String:
	if not is_instance_valid(item):
		return "food"
	if item is ResourceItem:
		return (item as ResourceItem).kind
	if item is WildTree:
		return "timber"
	return "food"


static func says_word(state_name: String, carry_intent: String) -> String:
	if state_name == "CARRYING":
		return "nom?" if carry_intent == "eat" else "for you!"
	return SAYS.get(state_name, "")


## The tooltip over the beast. Presentation, so it lives here with the rest of
## how the creature READS — `doing` comes in because only the creature knows
## what it is carrying.
static func hover_text(who: Creature, doing: String) -> String:
	return ("%s — %s (%s, %s)\n" +
		"bond %d · trusts you %d · attention %d\n" +
		"hunger %d · energy %d · %s\n" +
		"[P — pet   ·   L — scold   ·   C — lock camera]") % [
		who.called(), doing, who.morality_word(), mood_word(who.mood),
		int(who.bond), int(who.trust), int(who.attention),
		int(who.hunger), int(who.energy), who.favorite_deed()]


static func anim_for(state_name: String, moving: bool) -> String:
	if ANIM.has(state_name):
		return ANIM[state_name]
	return "walk" if moving else "idle"
