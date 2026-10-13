// FRESH LAVA, CHURNING. Laid over the ground a lavaball or a volcano's glob has
// just poured (LavaSkin, scripts/miracles/lava_skin.gd), on the ground's own
// triangles, and drawn as the molten rock it is: deep orange and bulbous red,
// mixing and swelling, never still. `heat` is the lava's own age, from the
// scar's clock — full while it is molten, falling to nothing as it crusts
// over (TerrainScars.EMBER_SECONDS, then COOLING) — and the skin is freed when
// it reaches nothing. Unshaded: it is the light, it does not take it.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float heat : hint_range(0.0, 1.0) = 1.0;
uniform vec2 centre = vec2(0.0);
uniform float radius = 3.0;
uniform vec3 deep_orange : source_color = vec3(1.0, 0.36, 0.03);
uniform vec3 bulbous_red : source_color = vec3(0.72, 0.05, 0.02);
uniform vec3 white_hot : source_color = vec3(1.0, 0.78, 0.32);

varying vec2 ground;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Smooth value noise: soft blobs, which is what a skin of lava breaks into.
float blobs(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	ground = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	// Two drifts of blobs crossing each other, so the pattern never repeats
	// and never simply slides.
	float slow = blobs(ground * 0.85 + vec2(TIME * 0.13, -TIME * 0.09));
	float quick = blobs(ground * 2.1 - vec2(TIME * 0.31, TIME * 0.23));
	// The SWELL: each blob breathes on its own beat, so the red bulges up
	// through the orange and sinks back.
	float swell = 0.5 + 0.5 * sin(TIME * 1.6 + slow * 6.2831);
	float mixed = clamp(slow * 0.65 + quick * 0.35 + (swell - 0.5) * 0.6, 0.0, 1.0);
	vec3 colour = mix(bulbous_red, deep_orange, smoothstep(0.25, 0.75, mixed));
	// A bubble's skin, thin and bright, where the quick blobs crest.
	float bulb = smoothstep(0.72, 0.92, quick) * swell;
	colour = mix(colour, white_hot, bulb * 0.45 * heat);
	// Gone at the rim, and dimming as it crusts over.
	float out_to = length(ground - centre) / max(radius, 0.01);
	float edge = 1.0 - smoothstep(0.55, 1.0, out_to);
	ALBEDO = colour;
	ALPHA = clamp(edge * heat * 0.92, 0.0, 1.0);
}
