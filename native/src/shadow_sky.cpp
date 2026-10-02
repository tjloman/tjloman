#include "shadow_sky.h"

#include <godot_cpp/classes/camera3d.hpp>
#include <godot_cpp/classes/light3d.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>

using namespace godot;

void ShadowSky::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_day", "day"), &ShadowSky::set_day);
	ClassDB::bind_method(D_METHOD("follow", "light"), &ShadowSky::follow);
	ClassDB::bind_method(D_METHOD("flash", "at", "range", "energy", "seconds"), &ShadowSky::flash);
	ClassDB::bind_method(D_METHOD("get_burning"), &ShadowSky::get_burning);
	ClassDB::bind_method(D_METHOD("get_alive"), &ShadowSky::get_alive);
	ClassDB::bind_method(D_METHOD("get_sent_sun"), &ShadowSky::get_sent_sun);
	ClassDB::bind_method(D_METHOD("get_sent_power"), &ShadowSky::get_sent_power);
	ClassDB::bind_method(D_METHOD("get_sent_light", "slot"), &ShadowSky::get_sent_light);

	ClassDB::bind_method(D_METHOD("set_step_seconds", "seconds"), &ShadowSky::set_step_seconds);
	ClassDB::bind_method(D_METHOD("get_step_seconds"), &ShadowSky::get_step_seconds);
	ClassDB::bind_method(D_METHOD("set_ease_seconds", "seconds"), &ShadowSky::set_ease_seconds);
	ClassDB::bind_method(D_METHOD("get_ease_seconds"), &ShadowSky::get_ease_seconds);
	ClassDB::bind_method(D_METHOD("set_day_seconds", "seconds"), &ShadowSky::set_day_seconds);
	ClassDB::bind_method(D_METHOD("get_day_seconds"), &ShadowSky::get_day_seconds);
	ClassDB::bind_method(D_METHOD("set_sun_yaw", "degrees"), &ShadowSky::set_sun_yaw);
	ClassDB::bind_method(D_METHOD("get_sun_yaw"), &ShadowSky::get_sun_yaw);
	ClassDB::bind_method(D_METHOD("set_darkest", "darkest"), &ShadowSky::set_darkest);
	ClassDB::bind_method(D_METHOD("get_darkest"), &ShadowSky::get_darkest);
	ClassDB::bind_method(D_METHOD("set_sight", "metres"), &ShadowSky::set_sight);
	ClassDB::bind_method(D_METHOD("get_sight"), &ShadowSky::get_sight);

	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "step_seconds"), "set_step_seconds", "get_step_seconds");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "ease_seconds"), "set_ease_seconds", "get_ease_seconds");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "day_seconds"), "set_day_seconds", "get_day_seconds");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "sun_yaw"), "set_sun_yaw", "get_sun_yaw");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "darkest"), "set_darkest", "get_darkest");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "sight"), "set_sight", "get_sight");
}

void ShadowSky::_ready() {
	set_process(true);
}

void ShadowSky::follow(Node *p_light) {
	if (p_light != nullptr) {
		followed.push_back(p_light->get_instance_id());
	}
}

void ShadowSky::flash(const Vector3 &p_at, double p_range, double p_energy, double p_seconds) {
	if (p_seconds <= 0.0 || p_range <= 0.0) {
		return;
	}
	Flash f;
	f.light.at = shade::V3(p_at.x, p_at.y, p_at.z);
	f.light.range = p_range;
	f.energy = p_energy;
	f.left = f.total = p_seconds;
	flashes.push_back(f);
}

// WRITTEN ONLY WHEN IT CHANGED. A global shader value is cheap to set but not
// free, and most frames nothing has: the sun is between steps and no miracle
// is burning.
void ShadowSky::_send(const char *p_name, const Vector4 &p_value, Vector4 &r_sent, bool p_force) {
	if (!p_force && p_value == r_sent) {
		return;
	}
	r_sent = p_value;
	RenderingServer::get_singleton()->global_shader_parameter_set(StringName(p_name), p_value);
}

void ShadowSky::_process(double p_delta) {
	const bool force = !sent;
	sent = true;

	if (sun.update(day, p_delta) || force) {
		const shade::V3 &d = sun.now;
		_send("shade_sun", Vector4(real_t(d.x), real_t(d.y), real_t(d.z), real_t(sun.strength())), sent_sun, force);
	}

	// THE LIGHTS, read live: a freed one is dropped, a hidden one throws
	// nothing this frame. Most frames there are none and this is a few
	// comparisons.
	std::vector<shade::Light> lights;
	for (size_t i = 0; i < followed.size();) {
		Object *o = ObjectDB::get_instance(followed[i]);
		Node3D *node = Object::cast_to<Node3D>(o);
		if (node == nullptr) {
			followed[i] = followed.back();
			followed.pop_back();
			continue;
		}
		i++;
		Light3D *light = Object::cast_to<Light3D>(o);
		if (!node->is_inside_tree() || !node->is_visible_in_tree() || light == nullptr) {
			continue;
		}
		const Vector3 at = node->get_global_position();
		shade::Light l;
		l.at = shade::V3(at.x, at.y, at.z);
		l.range = light->get_param(Light3D::PARAM_RANGE);
		l.power = shade::power_of(light->get_param(Light3D::PARAM_ENERGY));
		lights.push_back(l);
	}
	for (size_t i = 0; i < flashes.size();) {
		Flash &f = flashes[i];
		f.left -= p_delta;
		if (f.left <= 0.0) {
			flashes[i] = flashes.back();
			flashes.pop_back();
			continue;
		}
		f.light.power = shade::power_of(f.energy) * (f.left / f.total);
		lights.push_back(f.light);
		i++;
	}

	shade::V3 eye;
	Viewport *view = get_viewport();
	Camera3D *camera = view != nullptr ? view->get_camera_3d() : nullptr;
	if (camera != nullptr) {
		const Vector3 c = camera->get_global_position();
		eye = shade::V3(c.x, c.y, c.z);
	}
	const std::vector<int> chosen = shade::pick(lights, eye, sight);
	burning = int(chosen.size());
	real_t power[shade::SLOTS] = { 0, 0, 0, 0 };
	static const char *names[shade::SLOTS] = { "shade_light_0", "shade_light_1", "shade_light_2", "shade_light_3" };
	for (int s = 0; s < shade::SLOTS; s++) {
		Vector4 slot;
		if (s < int(chosen.size())) {
			const shade::Light &l = lights[chosen[s]];
			slot = Vector4(real_t(l.at.x), real_t(l.at.y), real_t(l.at.z), real_t(l.range));
			power[s] = real_t(l.power);
		}
		_send(names[s], slot, sent_light[s], force);
	}
	_send("shade_light_power", Vector4(power[0], power[1], power[2], power[3]), sent_power, force);
}
