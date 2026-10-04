// THE BAKED SHADOW — a model's hull, flattened onto the ground on the GPU.
//
// Real-time shadows drew the whole scene a second time, from the sun, every
// frame, into a shadow map: the single most expensive thing a phone GPU did for
// this game. This is the other way round. Every shadow-casting model carries its
// own hull (baked once, in C++, by ShadowBaker), and this shader squashes it
// flat along the light: one small, dark, see-through draw per model, no shadow
// map, no second pass, and no CPU work at all after the bake. Where the sun is
// comes from one global value the C++ ShadowSky sets a few times a minute.
//
// A CONVEX hull, flattened, covers its shadow exactly twice — once with its
// sun-facing faces, once with the rest, wound opposite ways — so culling one
// winding leaves it covered exactly once: no overlap, no darker patches.
//
// MIRACLE LIGHTS OVERRULE THE SUN near them: a model within a light's range
// throws its shadow away from the light instead, as hard as the light is
// bright. ShadowSky hands over the four that matter most to the camera.
shader_type spatial;
render_mode unshaded, skip_vertex_transform, cull_back, depth_draw_never, shadows_disabled, blend_mix;

global uniform vec4 shade_sun;          // xyz: the way the light travels; w: how dark
global uniform vec4 shade_light_0;      // xyz: where; w: how far it throws shadows
global uniform vec4 shade_light_1;
global uniform vec4 shade_light_2;
global uniform vec4 shade_light_3;
global uniform vec4 shade_light_power;  // one 0..1 per light
// THE GROUND UNDER THE SHADOWS: heights round the camera, read a few rows a
// frame by ShadeGround. Area: xy the world x,z of its corner, z its span in
// metres, w 1 once there is a map at all.
global uniform sampler2D shade_ground : filter_linear, repeat_disable;
global uniform vec4 shade_ground_area;

// No shadow longer than this many times the height of what casts it: a low
// sun would otherwise lay a house's shadow across half the valley.
const float LONGEST = 3.0;
// Just above the ground, so it is not lost in it: the map is the drawn land
// sampled every two metres and blended, which can sit a few centimetres under
// the triangles it was read from.
const float LIFT = 0.08;

varying float v_dark;

// The ground under a point, or `otherwise` off the edge of the map (or before
// there is one): the plane through the caster's foot, as before.
float ground_at(vec2 xz, float otherwise) {
	if (shade_ground_area.w <= 0.0) {
		return otherwise;
	}
	vec2 uv = (xz - shade_ground_area.xy) / shade_ground_area.z;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return otherwise;
	}
	return textureLod(shade_ground, uv, 0.0).r;
}

// Where the ray from a light through a point `h` above the ground lands.
vec2 thrown_from(vec4 light, vec3 w, float h) {
	float above = max(light.y - w.y, 0.25);
	return (w.xz - light.xz) * min(h / above, LONGEST);
}

// How much a light near `origin` takes over from the sun: all of it well
// inside its range, fading to none at the edge — and none for the thing the
// light is IN (a burning tree, the creature's own glow, an orb in the hand),
// which would otherwise splay its own shadow out from its middle.
float hold(vec4 light, float power, vec3 origin) {
	if (light.w <= 0.0 || power <= 0.0) {
		return 0.0;
	}
	float beside = smoothstep(0.8, 2.5, distance(light.xz, origin.xz));
	return power * beside * (1.0 - smoothstep(light.w * 0.6, light.w, distance(light.xyz, origin)));
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;     // the foot of the model (see Shade.cast)
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = max(w.y - origin.y, 0.0);

	vec3 sun = shade_sun.xyz;
	vec2 offset = sun.xz / max(-sun.y, 1.0 / LONGEST) * h;
	float dark = shade_sun.w;

	float k = hold(shade_light_0, shade_light_power.x, origin);
	offset = mix(offset, thrown_from(shade_light_0, w, h), k);
	dark = max(dark, k * 0.5);
	k = hold(shade_light_1, shade_light_power.y, origin);
	offset = mix(offset, thrown_from(shade_light_1, w, h), k);
	dark = max(dark, k * 0.5);
	k = hold(shade_light_2, shade_light_power.z, origin);
	offset = mix(offset, thrown_from(shade_light_2, w, h), k);
	dark = max(dark, k * 0.5);
	k = hold(shade_light_3, shade_light_power.w, origin);
	offset = mix(offset, thrown_from(shade_light_3, w, h), k);
	dark = max(dark, k * 0.5);

	w.xz += offset;
	// ON THE GROUND IT FALLS ON, vertex by vertex: down the slope, up the
	// bank, across the dip — and under a villager held aloft, on the ground
	// below rather than at its dangling feet.
	w.y = ground_at(w.xz, origin.y) + LIFT;
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	v_dark = dark;
}

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = v_dark;
}
