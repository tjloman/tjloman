// SHADE CORE — the arithmetic of the baked shadows, with no Godot in it.
//
// Everything here is plain C++17 so it can be compiled and tested on its own
// (native/tests/test_core.cpp) without an engine, a device or an editor. The
// Godot classes in shadow_baker.cpp and shadow_sky.cpp are thin wrappers that
// move data in and out of this file.
//
// Three things live here:
//
//   hull()        THE SHAPE A MODEL CASTS. The convex hull of its vertices,
//                 baked once per model. Projected flat onto the ground along the
//                 light, a convex hull covers the shadow exactly once from either
//                 side, which is what lets the shader draw it in one pass with no
//                 stencil and no double-darkening where parts overlap.
//   SunStepper    WHERE THE SUN IS, in steps. The light only moves every few
//                 seconds and eases between steps, so the world's shadows change
//                 a handful of times a minute instead of every frame.
//   LightBoard    WHICH MIRACLE LIGHTS THROW SHADOWS. Any number may be alive;
//                 the few that matter most to the camera are handed to the
//                 shader.

#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace shade {

constexpr double PI = 3.14159265358979323846;

struct V3 {
	double x = 0.0, y = 0.0, z = 0.0;
	V3() = default;
	V3(double p_x, double p_y, double p_z) : x(p_x), y(p_y), z(p_z) {}
	V3 operator+(const V3 &o) const { return { x + o.x, y + o.y, z + o.z }; }
	V3 operator-(const V3 &o) const { return { x - o.x, y - o.y, z - o.z }; }
	V3 operator*(double s) const { return { x * s, y * s, z * s }; }
	double dot(const V3 &o) const { return x * o.x + y * o.y + z * o.z; }
	V3 cross(const V3 &o) const {
		return { y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x };
	}
	double length() const { return std::sqrt(dot(*this)); }
	V3 normalized() const {
		const double l = length();
		return l > 0.0 ? *this * (1.0 / l) : V3();
	}
};

// A baked hull: the points it uses and its triangles, three indices each,
// wound so their normals face out.
struct Hull {
	std::vector<V3> points;
	std::vector<int> triangles;
	bool empty() const { return triangles.empty(); }
};

// ---------------------------------------------------------------------------
// THE HULL
// ---------------------------------------------------------------------------

// MERGE POINTS CLOSER THAN `cell`. A primitive capsule is five hundred vertices
// and its shadow does not need one of them past the first few dozen; snapping
// to a grid first keeps a baked hull to a few hundred triangles at most, which
// is the whole draw cost of the shadow. Returns the survivors, first seen kept.
inline std::vector<V3> merge(const std::vector<V3> &in, double cell) {
	if (cell <= 0.0) {
		return in;
	}
	struct Key {
		int64_t x, y, z;
		bool operator==(const Key &o) const { return x == o.x && y == o.y && z == o.z; }
	};
	struct KeyHash {
		size_t operator()(const Key &k) const {
			return size_t(k.x * 73856093) ^ size_t(k.y * 19349663) ^ size_t(k.z * 83492791);
		}
	};
	std::unordered_set<Key, KeyHash> seen;
	std::vector<V3> out;
	out.reserve(in.size());
	for (const V3 &p : in) {
		const Key k{ int64_t(std::llround(p.x / cell)), int64_t(std::llround(p.y / cell)),
			int64_t(std::llround(p.z / cell)) };
		if (seen.insert(k).second) {
			out.push_back(p);
		}
	}
	return out;
}

// THE FEW POINTS THAT DECIDE THE SHAPE. For each of a fixed set of directions
// round a sphere (`around` bearings on each of `rings` latitudes, and the two
// poles), the point that reaches furthest that way — its support point. The
// hull of those is the shape to within the gap between two neighbouring
// directions, and there are never more than around * rings + 2 of them, so a
// shadow costs the same few hundred triangles whether the model it came from
// had fifty vertices or fifty thousand. Order kept, duplicates dropped.
inline std::vector<V3> supports(const std::vector<V3> &in, int around, int rings) {
	std::vector<V3> dirs = { { 0, 1, 0 }, { 0, -1, 0 } };
	for (int r = 1; r <= rings; r++) {
		const double lat = PI * (double(r) / double(rings + 1) - 0.5);
		for (int a = 0; a < around; a++) {
			const double lon = 2.0 * PI * (double(a) + 0.5 * (r % 2)) / double(around);
			dirs.emplace_back(std::cos(lat) * std::cos(lon), std::sin(lat), std::cos(lat) * std::sin(lon));
		}
	}
	std::vector<int> picked;
	for (const V3 &d : dirs) {
		int best = 0;
		for (int i = 1; i < int(in.size()); i++) {
			if (in[i].dot(d) > in[best].dot(d)) {
				best = i;
			}
		}
		picked.push_back(best);
	}
	std::sort(picked.begin(), picked.end());
	picked.erase(std::unique(picked.begin(), picked.end()), picked.end());
	std::vector<V3> out;
	for (int i : picked) {
		out.push_back(in[i]);
	}
	return out;
}

// THE CONVEX HULL, incrementally: start from the widest tetrahedron the points
// allow, then add every point outside it, replacing the faces it can see with a
// fan from the horizon. O(n * faces), and n is small after `merge` — this runs
// once per model, never per frame.
//
// Empty when the points are flat or fewer than four (a flat thing seen from a
// sun that is never quite overhead casts a sliver nobody would miss).
//
// A cloud of more than `most` points is cut to its support points first (see
// `supports`): `most` 0 never cuts, which the tests use to check the hull alone.
inline Hull hull(const std::vector<V3> &raw, double cell = 0.0, int most = 0) {
	Hull out;
	std::vector<V3> pts = merge(raw, cell);
	if (most > 0 && int(pts.size()) > most) {
		pts = supports(pts, 24, 5);
	}
	const int n = int(pts.size());
	if (n < 4) {
		return out;
	}
	double span = 0.0;
	for (const V3 &p : pts) {
		span = std::max({ span, std::fabs(p.x), std::fabs(p.y), std::fabs(p.z) });
	}
	const double eps = std::max(span, 1.0) * 1e-9;

	// The first four: the extreme in x, the point farthest from it, the point
	// farthest from that line, and the point farthest from that plane.
	int a = 0;
	for (int i = 1; i < n; i++) {
		if (pts[i].x < pts[a].x) {
			a = i;
		}
	}
	int b = -1;
	double best = 0.0;
	for (int i = 0; i < n; i++) {
		const double d = (pts[i] - pts[a]).length();
		if (d > best) {
			best = d;
			b = i;
		}
	}
	if (b < 0 || best <= eps) {
		return out;
	}
	int c = -1;
	best = 0.0;
	const V3 ab = pts[b] - pts[a];
	for (int i = 0; i < n; i++) {
		const double d = ab.cross(pts[i] - pts[a]).length();
		if (d > best) {
			best = d;
			c = i;
		}
	}
	if (c < 0 || best <= eps) {
		return out;
	}
	int d4 = -1;
	best = 0.0;
	const V3 plane = ab.cross(pts[c] - pts[a]).normalized();
	for (int i = 0; i < n; i++) {
		const double d = std::fabs(plane.dot(pts[i] - pts[a]));
		if (d > best) {
			best = d;
			d4 = i;
		}
	}
	if (d4 < 0 || best <= eps * 10.0) {
		return out;
	}

	struct Face {
		int v[3];
		V3 normal;
		double offset; // normal . p for any p on the face
		bool alive;
	};
	std::vector<Face> faces;
	const V3 inside = (pts[a] + pts[b] + pts[c] + pts[d4]) * 0.25;
	auto add_face = [&](int i, int j, int k) {
		V3 nrm = (pts[j] - pts[i]).cross(pts[k] - pts[i]).normalized();
		// Outward: away from a point known to be inside.
		if (nrm.dot(inside - pts[i]) > 0.0) {
			std::swap(j, k);
			nrm = nrm * -1.0;
		}
		faces.push_back({ { i, j, k }, nrm, nrm.dot(pts[i]), true });
	};
	add_face(a, b, c);
	add_face(a, b, d4);
	add_face(a, c, d4);
	add_face(b, c, d4);

	std::vector<int> visible;
	for (int p = 0; p < n; p++) {
		if (p == a || p == b || p == c || p == d4) {
			continue;
		}
		visible.clear();
		for (int f = 0; f < int(faces.size()); f++) {
			if (faces[f].alive && faces[f].normal.dot(pts[p]) - faces[f].offset > eps) {
				visible.push_back(f);
			}
		}
		if (visible.empty()) {
			continue; // inside: nothing to do
		}
		// THE HORIZON: an edge of a seen face whose other side is not seen. Kept
		// in the seen face's winding, so the new face (edge, p) faces out too.
		std::unordered_map<int64_t, int> edges; // directed edge -> count
		auto key = [&](int i, int j) { return int64_t(i) * n + j; };
		for (int f : visible) {
			const int *v = faces[f].v;
			for (int e = 0; e < 3; e++) {
				edges[key(v[e], v[(e + 1) % 3])]++;
			}
		}
		std::vector<std::pair<int, int>> horizon;
		for (int f : visible) {
			const int *v = faces[f].v;
			for (int e = 0; e < 3; e++) {
				const int i = v[e], j = v[(e + 1) % 3];
				if (edges.find(key(j, i)) == edges.end()) {
					horizon.emplace_back(i, j);
				}
			}
			faces[f].alive = false;
		}
		for (const auto &e : horizon) {
			V3 nrm = (pts[e.second] - pts[e.first]).cross(pts[p] - pts[e.first]).normalized();
			faces.push_back({ { e.first, e.second, p }, nrm, nrm.dot(pts[e.first]), true });
		}
	}

	// Compact: only the points a live face uses, renumbered.
	std::unordered_map<int, int> remap;
	for (const Face &f : faces) {
		if (!f.alive) {
			continue;
		}
		for (int e = 0; e < 3; e++) {
			auto it = remap.find(f.v[e]);
			int idx;
			if (it == remap.end()) {
				idx = int(out.points.size());
				remap[f.v[e]] = idx;
				out.points.push_back(pts[f.v[e]]);
			} else {
				idx = it->second;
			}
			out.triangles.push_back(idx);
		}
	}
	return out;
}

// ---------------------------------------------------------------------------
// THE SUN
// ---------------------------------------------------------------------------

// THE DIRECTION SUNLIGHT TRAVELS at a point in the day — the same sun Main
// turns: rotation_degrees = (-(day * 360 - 90), yaw, 0), Euler YXZ, light along
// its -Z. Straight down at noon (day 0.5); pointing up, under the world, at
// night.
inline V3 sun_direction(double day_fraction, double yaw_degrees) {
	const double pitch = -(day_fraction * 360.0 - 90.0) * PI / 180.0;
	const double yaw = yaw_degrees * PI / 180.0;
	return V3(-std::sin(yaw) * std::cos(pitch), std::sin(pitch), -std::cos(yaw) * std::cos(pitch));
}

// WHERE THE SHADOWS POINT, moved in steps. The shadow of everything in the
// world is one value in the shader, so a step costs nothing — but a light that
// slides every frame is a world whose every shadow crawls, which is the thing
// that reads as cheap. So the sun is read on a fixed beat (`step_seconds` of
// the day) and eased to its new place over `ease_seconds`, then left alone.
struct SunStepper {
	double day_seconds = 320.0;
	double step_seconds = 4.0;
	double ease_seconds = 0.5;
	double yaw_degrees = 20.0;
	double darkest = 0.45; // how dark a shadow is at full sun, 0..1

	int64_t step = -1;
	V3 from, to, now;
	double eased = 1.0;

	// Advance to `day_fraction` (0..1) after `dt` seconds. True when the
	// direction or strength changed and the shader needs telling.
	bool update(double day_fraction, double dt) {
		const double steps_a_day = std::max(1.0, std::floor(day_seconds / step_seconds));
		const double wrapped = day_fraction - std::floor(day_fraction);
		const int64_t at = int64_t(std::floor(wrapped * steps_a_day));
		if (at != step) {
			const V3 next = sun_direction((double(at) + 0.5) / steps_a_day, yaw_degrees);
			// A JUMP — a load, a skip, the first frame — is taken at once;
			// only the next step along is eased.
			const bool neighbour = step >= 0 && (at == step + 1 || (step == int64_t(steps_a_day) - 1 && at == 0));
			step = at;
			if (neighbour && ease_seconds > 0.0) {
				from = now;
				to = next;
				eased = 0.0;
			} else {
				from = to = now = next;
				eased = 1.0;
				return true;
			}
		}
		if (eased >= 1.0) {
			return false;
		}
		eased = std::min(1.0, eased + dt / ease_seconds);
		const double s = eased * eased * (3.0 - 2.0 * eased);
		now = (from * (1.0 - s) + to * s).normalized();
		return true;
	}

	// HOW DARK, from how high the sun is: full at a third of the way up, gone
	// as it reaches the horizon, nothing at night.
	double strength() const {
		const double up = -now.y;
		return darkest * std::clamp(up * 3.0, 0.0, 1.0);
	}
};

// ---------------------------------------------------------------------------
// THE MIRACLE LIGHTS
// ---------------------------------------------------------------------------

constexpr int SLOTS = 4; // how many lights the shader is handed at once

struct Light {
	V3 at;
	double range = 0.0;  // how far its shadows are thrown, in metres
	double power = 0.0;  // 0..1, how strongly it overrules the sun
};

// THE FEW THAT COUNT. Any number of lights may be burning; the shader is given
// the SLOTS that matter most to the camera — bright, wide, near — and the rest
// throw no shadow. Ties keep their order, so a light does not flicker in and out
// of a slot between two equal claims.
inline std::vector<int> pick(const std::vector<Light> &lights, const V3 &eye, double sight) {
	std::vector<std::pair<double, int>> scored;
	for (int i = 0; i < int(lights.size()); i++) {
		const Light &l = lights[i];
		if (l.power <= 0.0 || l.range <= 0.0) {
			continue;
		}
		const double gap = (l.at - eye).length();
		if (gap > sight + l.range) {
			continue;
		}
		scored.emplace_back(l.power * l.range / (1.0 + gap), i);
	}
	std::stable_sort(scored.begin(), scored.end(),
			[](const auto &x, const auto &y) { return x.first > y.first; });
	std::vector<int> out;
	for (int i = 0; i < int(scored.size()) && i < SLOTS; i++) {
		out.push_back(scored[i].second);
	}
	return out;
}

// A light's energy as the shader's 0..1. A lantern is about 1.5, a fireball's
// blast 7: past 4 everything is "the brightest thing here".
inline double power_of(double energy) {
	return std::clamp(energy / 4.0, 0.0, 1.0);
}

} // namespace shade
