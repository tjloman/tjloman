// SHADOW SKY — where every baked shadow points, and what overrules the sun.
//
// One node, made once by Shade (scripts/shade.gd). Each frame it is told the
// time of day; it moves the sun only on a beat (shade::SunStepper), follows the
// miracle lights it was handed (any Light3D: its place, energy and range are
// read live, so a tweened flash fades as it was always going to), runs down the
// timed flashes, and writes the few global shader values every baked shadow
// reads — only on the frames something actually changed.
//
// The globals, declared in project.godot under [shader_globals]:
//   shade_sun           xyz: the way sunlight travels; w: how dark, 0..1
//   shade_light_0..3    xyz: a light's place; w: how far it throws shadows
//   shade_light_power   one 0..1 per slot: how much it overrules the sun
#pragma once

#include "shade_core.hpp"

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector4.hpp>

#include <vector>

namespace godot {

class ShadowSky : public Node {
	GDCLASS(ShadowSky, Node)

	struct Flash {
		shade::Light light;
		double energy = 0.0;
		double left = 0.0;
		double total = 0.0;
	};

	shade::SunStepper sun;
	double day = 0.5;
	double sight = 120.0;
	std::vector<uint64_t> followed;
	std::vector<Flash> flashes;
	Vector4 sent_sun;
	Vector4 sent_light[shade::SLOTS];
	Vector4 sent_power;
	bool sent = false;
	int burning = 0;

	void _send(const char *p_name, const Vector4 &p_value, Vector4 &r_sent, bool p_force);

protected:
	static void _bind_methods();

public:
	void _ready() override;
	void _process(double p_delta) override;

	// The time of day, 0..1, as GameState.day_fraction gives it.
	void set_day(double p_day) { day = p_day; }
	// Any Light3D (an omni, usually) from now until it is freed.
	void follow(Node *p_light);
	// A light that is only a moment: full at once, gone after `seconds`.
	void flash(const Vector3 &p_at, double p_range, double p_energy, double p_seconds);
	// How many lights threw shadows last frame, of how many alive.
	int get_burning() const { return burning; }
	int get_alive() const { return int(followed.size() + flashes.size()); }
	// What was last written to the shader, for the meter and for tests (the
	// headless renderer keeps no global values to read back).
	Vector4 get_sent_sun() const { return sent_sun; }
	Vector4 get_sent_power() const { return sent_power; }
	Vector4 get_sent_light(int p_slot) const {
		return p_slot >= 0 && p_slot < shade::SLOTS ? sent_light[p_slot] : Vector4();
	}

	void set_step_seconds(double p_v) { sun.step_seconds = p_v; }
	double get_step_seconds() const { return sun.step_seconds; }
	void set_ease_seconds(double p_v) { sun.ease_seconds = p_v; }
	double get_ease_seconds() const { return sun.ease_seconds; }
	void set_day_seconds(double p_v) { sun.day_seconds = p_v; }
	double get_day_seconds() const { return sun.day_seconds; }
	void set_sun_yaw(double p_v) { sun.yaw_degrees = p_v; }
	double get_sun_yaw() const { return sun.yaw_degrees; }
	void set_darkest(double p_v) { sun.darkest = p_v; }
	double get_darkest() const { return sun.darkest; }
	void set_sight(double p_v) { sight = p_v; }
	double get_sight() const { return sight; }
};

} // namespace godot
