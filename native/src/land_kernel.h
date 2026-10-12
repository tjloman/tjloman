// THE LAND KERNEL — the questions every walker, beast and builder asks of the
// ground, answered in C++.
//
// Each one is asked thousands of times a second: how high is the land here (the
// seed's noise, blended by country, and every crater and mound on top), what
// does a chunk's grid of heights look like, how high is the ground as it is
// DRAWN, and which way should a body step to go round the trees and rocks in
// its way. In GDScript each answer cost a few microseconds of interpreter, and a
// town of three hundred asks several each a turn.
//
// EVERY FUNCTION HERE IS A TWIN. Its GDScript original stays where it was and
// is what runs when this library is not built (scripts/kernel.gd decides), and
// tools/live/kernel_live.gd holds the two to the same answers. Change one,
// change the other: that test fails the build the day they disagree.
#pragma once

#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>
#include <unordered_map>
#include <vector>

namespace godot {

class LandKernel : public RefCounted {
	GDCLASS(LandKernel, RefCounted)

	// The seed's five noises, as WorldGen made them (WorldGen._seeded_height,
	// _rugged). Held, not copied: they are the same objects.
	Ref<FastNoiseLite> height_noise;
	Ref<FastNoiseLite> detail_noise;
	Ref<FastNoiseLite> temp_noise;
	Ref<FastNoiseLite> wet_noise;
	Ref<FastNoiseLite> jungle_noise;

	// THE SCARS (TerrainScars), flat: one row of six per scar, filed by bucket
	// as TerrainScars._index files them — under every bucket the footprint
	// touches, so a point reads the one bucket it is in.
	struct Scar {
		int kind;
		double x, z, radius, amount, rings;
	};
	std::vector<Scar> scars;
	std::unordered_map<int64_t, std::vector<int>> scar_buckets;
	double scar_min_x = 0.0, scar_min_z = 0.0, scar_max_x = 0.0, scar_max_z = 0.0;

	// THE OBSTACLES (NavField._grid): a tree or a rock, by the cell it is in.
	struct Obstacle {
		Vector2 at;
		real_t radius;
		bool tree;
	};
	std::unordered_map<int64_t, std::vector<Obstacle>> obstacles;

	static int64_t key(int64_t p_x, int64_t p_z) { return (p_x << 32) ^ (p_z & 0xffffffffLL); }
	double rugged(double p_x, double p_z) const;
	double contribution(const Scar &p_scar, double p_x, double p_z) const;

protected:
	static void _bind_methods();

public:
	// The land's numbers, from WorldGen — kept in one place on that side so
	// the two can never be told different ones.
	static constexpr double RUGGED_BLEND = 0.2;
	static constexpr double RAINFOREST_WET = 0.30;
	static constexpr double TUNDRA_COLD = -0.52;
	static constexpr double DESERT_HEAT = 0.52;
	static constexpr double DESERT_DRY = 0.0;
	static constexpr double SHARED_PER_METRE = 2.0;
	static constexpr double SCAR_BUCKET = 32.0;
	static constexpr double NAV_CELL = 8.0;
	static constexpr double AVOID_RANGE = 2.2;
	static constexpr double CHUNK_SIZE = 48.0;

	void set_noises(const Ref<FastNoiseLite> &p_height, const Ref<FastNoiseLite> &p_detail,
			const Ref<FastNoiseLite> &p_temp, const Ref<FastNoiseLite> &p_wet,
			const Ref<FastNoiseLite> &p_jungle);
	// WorldGen._seeded_height: the land as the seed made it, at exactly (x, z).
	double seeded_height(double p_x, double p_z) const;
	// WorldGen.seeded_height_at's question: snapped to the shared grid first.
	double seeded_height_at(double p_x, double p_z) const;
	// WorldGen.height_at: the snapped seed, and the scars at the true point.
	double height_at(double p_x, double p_z) const;

	// TerrainScars: the scars as rows of [kind, x, z, radius, amount, rings].
	void set_scars(const PackedFloat64Array &p_rows);
	double offset_at(double p_x, double p_z) const;

	// Chunk._build_terrain's grid, whole: { heights, lowest, lowest_seeded, deepest }.
	Dictionary height_grid(double p_x0, double p_z0, double p_step, int p_wide) const;
	// Chunk._drawn_local: the drawn surface of a grid of heights.
	double drawn_local(const PackedFloat32Array &p_heights, int p_cells, double p_lx, double p_lz) const;

	// NavField: obstacles as rows of [x, z, radius, tree], and the steer.
	void set_obstacles(const PackedFloat64Array &p_rows);
	Vector3 steer(const Vector3 &p_pos, const Vector3 &p_desired, double p_self_radius,
			const Vector3 &p_ignore, bool p_skip_trees) const;
};

} // namespace godot
