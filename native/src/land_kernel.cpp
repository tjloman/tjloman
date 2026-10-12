#include "land_kernel.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <cmath>
#include <limits>

using namespace godot;

// GDScript's PI, to the digit.
static constexpr double LAND_PI = 3.1415926535897932384626433833;

void LandKernel::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_noises", "height", "detail", "temp", "wet", "jungle"),
			&LandKernel::set_noises);
	ClassDB::bind_method(D_METHOD("seeded_height", "x", "z"), &LandKernel::seeded_height);
	ClassDB::bind_method(D_METHOD("seeded_height_at", "x", "z"), &LandKernel::seeded_height_at);
	ClassDB::bind_method(D_METHOD("height_at", "x", "z"), &LandKernel::height_at);
	ClassDB::bind_method(D_METHOD("set_scars", "rows"), &LandKernel::set_scars);
	ClassDB::bind_method(D_METHOD("offset_at", "x", "z"), &LandKernel::offset_at);
	ClassDB::bind_method(D_METHOD("height_grid", "x0", "z0", "step", "wide"), &LandKernel::height_grid);
	ClassDB::bind_method(D_METHOD("drawn_local", "heights", "cells", "lx", "lz"), &LandKernel::drawn_local);
	ClassDB::bind_method(D_METHOD("set_obstacles", "rows"), &LandKernel::set_obstacles);
	ClassDB::bind_method(D_METHOD("steer", "pos", "desired", "self_radius", "ignore", "skip_trees"),
			&LandKernel::steer);
}

void LandKernel::set_noises(const Ref<FastNoiseLite> &p_height, const Ref<FastNoiseLite> &p_detail,
		const Ref<FastNoiseLite> &p_temp, const Ref<FastNoiseLite> &p_wet,
		const Ref<FastNoiseLite> &p_jungle) {
	height_noise = p_height;
	detail_noise = p_detail;
	temp_noise = p_temp;
	wet_noise = p_wet;
	jungle_noise = p_jungle;
}

// Nothing below a threshold, all of it above, and a smooth ramp across the band
// (WorldGen._soft).
static inline double soft(double p_past) {
	return Math::smoothstep(-LandKernel::RUGGED_BLEND, LandKernel::RUGGED_BLEND, p_past);
}

static inline double lerpd(double p_from, double p_to, double p_weight) {
	return p_from + (p_to - p_from) * p_weight;
}

// WorldGen._rugged, line for line.
double LandKernel::rugged(double p_x, double p_z) const {
	const double t = temp_noise->get_noise_2d(real_t(p_x), real_t(p_z));
	const double w = wet_noise->get_noise_2d(real_t(p_x), real_t(p_z));
	double amp = 11.0;
	amp = lerpd(amp, 24.0, soft(-0.4 - t));
	amp = lerpd(amp, 11.0, soft(w - 0.15));
	amp = lerpd(amp, 4.0, soft(w - 0.45));
	const double jungle = w > RAINFOREST_WET - RUGGED_BLEND
			? soft(jungle_noise->get_noise_2d(real_t(p_x), real_t(p_z)))
			: 0.0;
	amp = lerpd(amp, 10.0, soft(w - RAINFOREST_WET) * jungle);
	amp = lerpd(amp, 5.0, soft(TUNDRA_COLD - t));
	amp = lerpd(amp, 7.0, soft(t - 0.4));
	return lerpd(amp, 9.0, soft(t - DESERT_HEAT) * soft(DESERT_DRY - w));
}

// WorldGen._seeded_height, line for line. The distance from the cradle is taken
// as GDScript takes it: a Vector2 of single floats.
double LandKernel::seeded_height(double p_x, double p_z) const {
	if (height_noise.is_null() || detail_noise.is_null() || temp_noise.is_null() ||
			wet_noise.is_null() || jungle_noise.is_null()) {
		return 0.0;
	}
	double h = double(height_noise->get_noise_2d(real_t(p_x), real_t(p_z))) * rugged(p_x, p_z) + 2.2;
	h += double(detail_noise->get_noise_2d(real_t(p_x), real_t(p_z))) * 0.7;
	const double d = Vector2(real_t(p_x), real_t(p_z)).length();
	return lerpd(2.0, h, Math::smoothstep(28.0, 80.0, d));
}

double LandKernel::seeded_height_at(double p_x, double p_z) const {
	const int64_t kx = int64_t(std::round(p_x * SHARED_PER_METRE));
	const int64_t kz = int64_t(std::round(p_z * SHARED_PER_METRE));
	return seeded_height(double(kx) / SHARED_PER_METRE, double(kz) / SHARED_PER_METRE);
}

double LandKernel::height_at(double p_x, double p_z) const {
	return seeded_height_at(p_x, p_z) + offset_at(p_x, p_z);
}

void LandKernel::set_scars(const PackedFloat64Array &p_rows) {
	scars.clear();
	scar_buckets.clear();
	const int64_t many = p_rows.size() / 6;
	for (int64_t i = 0; i < many; i++) {
		Scar scar;
		scar.kind = int(p_rows[i * 6]);
		scar.x = p_rows[i * 6 + 1];
		scar.z = p_rows[i * 6 + 2];
		scar.radius = p_rows[i * 6 + 3];
		scar.amount = p_rows[i * 6 + 4];
		scar.rings = p_rows[i * 6 + 5];
		const int index = int(scars.size());
		scars.push_back(scar);
		// TerrainScars._index: every bucket the footprint's square touches.
		const int64_t x0 = int64_t(Math::floor((scar.x - scar.radius) / SCAR_BUCKET));
		const int64_t x1 = int64_t(Math::floor((scar.x + scar.radius) / SCAR_BUCKET));
		const int64_t z0 = int64_t(Math::floor((scar.z - scar.radius) / SCAR_BUCKET));
		const int64_t z1 = int64_t(Math::floor((scar.z + scar.radius) / SCAR_BUCKET));
		for (int64_t bz = z0; bz <= z1; bz++) {
			for (int64_t bx = x0; bx <= x1; bx++) {
				scar_buckets[key(bx, bz)].push_back(index);
			}
		}
		// TerrainScars._grow_bounds.
		if (index == 0) {
			scar_min_x = scar.x - scar.radius;
			scar_min_z = scar.z - scar.radius;
			scar_max_x = scar.x + scar.radius;
			scar_max_z = scar.z + scar.radius;
		} else {
			scar_min_x = MIN(scar_min_x, scar.x - scar.radius);
			scar_min_z = MIN(scar_min_z, scar.z - scar.radius);
			scar_max_x = MAX(scar_max_x, scar.x + scar.radius);
			scar_max_z = MAX(scar_max_z, scar.z + scar.radius);
		}
	}
}

// TerrainScars._contribution, line for line.
double LandKernel::contribution(const Scar &p_scar, double p_x, double p_z) const {
	const double radius = p_scar.radius;
	const double dx = p_x - p_scar.x;
	const double dz = p_z - p_scar.z;
	const double d2 = dx * dx + dz * dz;
	if (d2 >= radius * radius) {
		return 0.0;
	}
	const double d = std::sqrt(d2);
	const double t = d / radius;
	const double amount = p_scar.amount;
	switch (p_scar.kind) {
		case 0: { // CRATER
			const double bowl = std::cos(t * LAND_PI) * 0.5 + 0.5;
			const double lip = std::sin(CLAMP((t - 0.55) / 0.45, 0.0, 1.0) * LAND_PI) * 0.35;
			return amount * (bowl - lip);
		}
		case 1: { // CONE
			const double flank = std::pow(1.0 - t, 1.7);
			const double mouth = MAX(0.0, 1.0 - t / 0.22);
			return amount * (flank - mouth * mouth * 0.55);
		}
		case 2: // RIPPLE
			return amount * std::cos(t * LAND_PI * p_scar.rings) * std::pow(1.0 - t, 1.6);
		default: // BASIN
			return amount * std::pow(std::cos(t * LAND_PI * 0.5), 2.0);
	}
}

// TerrainScars.offset_at: the one bucket the point is in.
double LandKernel::offset_at(double p_x, double p_z) const {
	if (scars.empty()) {
		return 0.0;
	}
	if (p_x < scar_min_x || p_x > scar_max_x || p_z < scar_min_z || p_z > scar_max_z) {
		return 0.0;
	}
	const auto found = scar_buckets.find(key(int64_t(Math::floor(p_x / SCAR_BUCKET)),
			int64_t(Math::floor(p_z / SCAR_BUCKET))));
	if (found == scar_buckets.end()) {
		return 0.0;
	}
	double total = 0.0;
	for (const int index : found->second) {
		total += contribution(scars[index], p_x, p_z);
	}
	return total;
}

// Chunk._build_terrain's loop over its grid, whole.
Dictionary LandKernel::height_grid(double p_x0, double p_z0, double p_step, int p_wide) const {
	PackedFloat32Array heights;
	heights.resize(int64_t(p_wide) * p_wide);
	double lowest = std::numeric_limits<double>::infinity();
	double lowest_seeded = std::numeric_limits<double>::infinity();
	Vector2 deepest;
	for (int z = 0; z < p_wide; z++) {
		for (int x = 0; x < p_wide; x++) {
			const double wx = p_x0 + x * p_step;
			const double wz = p_z0 + z * p_step;
			const double seeded = seeded_height_at(wx, wz);
			const double h = seeded + offset_at(wx, wz);
			heights.set(int64_t(z) * p_wide + x, float(h));
			lowest_seeded = MIN(lowest_seeded, seeded);
			if (h < lowest) {
				lowest = h;
				deepest = Vector2(real_t(wx), real_t(wz));
			}
		}
	}
	Dictionary out;
	out["heights"] = heights;
	out["lowest"] = lowest;
	out["lowest_seeded"] = lowest_seeded;
	out["deepest"] = deepest;
	return out;
}

// Chunk._drawn_local, line for line.
double LandKernel::drawn_local(const PackedFloat32Array &p_heights, int p_cells, double p_lx,
		double p_lz) const {
	if (p_cells <= 0 || p_heights.is_empty()) {
		return std::numeric_limits<double>::quiet_NaN();
	}
	const int wide = p_cells + 1;
	const double step = CHUNK_SIZE / p_cells;
	const double u = p_lx / step;
	const double v = p_lz / step;
	const int cx = CLAMP(int(Math::floor(u)), 0, p_cells - 1);
	const int cz = CLAMP(int(Math::floor(v)), 0, p_cells - 1);
	const double fu = CLAMP(u - cx, 0.0, 1.0);
	const double fv = CLAMP(v - cz, 0.0, 1.0);
	const double h0 = p_heights[cz * wide + cx];
	const double h1 = p_heights[cz * wide + cx + 1];
	const double h2 = p_heights[(cz + 1) * wide + cx + 1];
	const double h3 = p_heights[(cz + 1) * wide + cx];
	if (fu >= fv) {
		return h0 + (h1 - h0) * fu + (h2 - h1) * fv;
	}
	return h0 + (h2 - h3) * fu + (h3 - h0) * fv;
}

void LandKernel::set_obstacles(const PackedFloat64Array &p_rows) {
	obstacles.clear();
	const int64_t many = p_rows.size() / 4;
	for (int64_t i = 0; i < many; i++) {
		Obstacle o;
		const double x = p_rows[i * 4];
		const double z = p_rows[i * 4 + 1];
		o.at = Vector2(real_t(x), real_t(z));
		o.radius = real_t(p_rows[i * 4 + 2]);
		o.tree = p_rows[i * 4 + 3] != 0.0;
		obstacles[key(int64_t(Math::floor(x / NAV_CELL)), int64_t(Math::floor(z / NAV_CELL)))].push_back(o);
	}
}

// NavField.steer, line for line — in single floats where GDScript's Vector2
// works in them, and in doubles where its plain floats do.
Vector3 LandKernel::steer(const Vector3 &p_pos, const Vector3 &p_desired, double p_self_radius,
		const Vector3 &p_ignore, bool p_skip_trees) const {
	const Vector2 here(p_pos.x, p_pos.z);
	const Vector2 des2(p_desired.x, p_desired.z);
	if (des2 == Vector2()) {
		return p_desired;
	}
	const Vector2 ignore2(p_ignore.x, p_ignore.z);
	const real_t inf = std::numeric_limits<real_t>::infinity();
	const bool has_ignore = p_ignore != Vector3(inf, inf, inf);
	Vector2 push;
	const int64_t cx = int64_t(Math::floor(double(p_pos.x) / NAV_CELL));
	const int64_t cz = int64_t(Math::floor(double(p_pos.z) / NAV_CELL));
	for (int dz = -1; dz <= 1; dz++) {
		for (int dx = -1; dx <= 1; dx++) {
			const auto found = obstacles.find(key(cx + dx, cz + dz));
			if (found == obstacles.end()) {
				continue;
			}
			for (const Obstacle &o : found->second) {
				if (p_skip_trees && o.tree) {
					continue;
				}
				const Vector2 op = o.at;
				if (has_ignore && double(op.distance_to(ignore2)) < 2.0) {
					continue;
				}
				const Vector2 off = here - op;
				const double d = off.length();
				const double reach = double(o.radius) + p_self_radius + AVOID_RANGE;
				if (d >= reach || d < 0.001) {
					continue;
				}
				if (double(des2.dot((op - here).normalized())) < -0.3) {
					continue;
				}
				push += off.normalized() * real_t((reach - d) / reach);
			}
		}
	}
	if (push == Vector2()) {
		return p_desired;
	}
	const Vector2 steered = (des2 + push * real_t(1.4)).normalized();
	return Vector3(steered.x, 0, steered.y);
}
