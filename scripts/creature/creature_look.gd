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
