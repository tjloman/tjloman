// TESTS FOR THE SHADE CORE, with no engine: build and run with
//
//     g++ -std=c++17 -O2 -Wall -Wextra -I native/src native/tests/test_core.cpp -o /tmp/shade_test && /tmp/shade_test
//
// (tools/shade.py does exactly this whenever a C++ compiler is on the path.)
// Every check prints what it asked; the process exits non-zero on any failure.

#include "shade_core.hpp"

#include <cstdio>
#include <random>

using shade::V3;

static int failures = 0;

static void check(bool ok, const char *what) {
	std::printf("  %-62s %s\n", what, ok ? "yes" : "NO");
	if (!ok) {
		failures++;
	}
}

// A HULL IS A HULL: every input point on or inside every face, every face
// facing away from the middle, and every edge shared by exactly two faces.
static bool sound(const shade::Hull &h, const std::vector<V3> &input) {
	if (h.empty()) {
		return false;
	}
	V3 mid;
	for (const V3 &p : h.points) {
		mid = mid + p;
	}
	mid = mid * (1.0 / double(h.points.size()));
	std::vector<std::pair<int, int>> edges;
	for (size_t t = 0; t < h.triangles.size(); t += 3) {
		const V3 &a = h.points[h.triangles[t]];
		const V3 &b = h.points[h.triangles[t + 1]];
		const V3 &c = h.points[h.triangles[t + 2]];
		const V3 n = (b - a).cross(c - a).normalized();
		if (n.dot(mid - a) > 1e-9) {
			return false; // facing in
		}
		for (const V3 &p : input) {
			if (n.dot(p - a) > 1e-6) {
				return false; // a point outside
			}
		}
		for (int e = 0; e < 3; e++) {
			edges.emplace_back(h.triangles[t + e], h.triangles[t + (e + 1) % 3]);
		}
	}
	for (const auto &e : edges) {
		int forward = 0, back = 0;
		for (const auto &f : edges) {
			forward += (f == e);
			back += (f.first == e.second && f.second == e.first);
		}
		if (forward != 1 || back != 1) {
			return false; // not closed, or wound inconsistently
		}
	}
	return true;
}

int main() {
	std::printf("THE HULL\n");
	std::vector<V3> cube;
	for (int i = 0; i < 8; i++) {
		cube.emplace_back(i & 1 ? 1 : -1, i & 2 ? 1 : -1, i & 4 ? 1 : -1);
	}
	cube.emplace_back(0, 0, 0);       // inside: must not survive
	cube.emplace_back(0.2, 0.9, -0.3); // inside
	shade::Hull h = shade::hull(cube);
	check(sound(h, cube), "a cube is closed, outward, and holds every point");
	check(h.points.size() == 8, "and uses its eight corners and nothing inside");
	check(h.triangles.size() == 12 * 3, "in twelve triangles");

	std::vector<V3> flat = { { 0, 0, 0 }, { 1, 0, 0 }, { 0, 0, 1 }, { 1, 0, 1 }, { 0.5, 0, 0.5 } };
	check(shade::hull(flat).empty(), "a flat thing casts nothing (and does not crash)");
	check(shade::hull({ { 0, 0, 0 }, { 1, 1, 1 } }).empty(), "two points cast nothing");

	// A villager: a capsule and a head, as Util builds them, densely sampled.
	std::vector<V3> villager;
	for (int i = 0; i < 40; i++) {
		for (int j = 0; j <= 20; j++) {
			const double a = 2.0 * shade::PI * i / 40.0, y = 0.05 + 1.0 * j / 20.0;
			villager.emplace_back(0.28 * std::cos(a), y, 0.28 * std::sin(a));
			villager.emplace_back(0.18 * std::cos(a), 1.25 + 0.18 * std::sin(shade::PI * (j - 10) / 20.0),
					0.18 * std::sin(a));
		}
	}
	shade::Hull vh = shade::hull(villager, 0.0, 64);
	const std::vector<V3> kept = shade::supports(villager, 24, 5);
	check(sound(vh, kept), "a villager's support points give a sound hull");
	std::printf("    %zu points in, %zu kept, %zu triangles out\n", villager.size(), kept.size(),
			vh.triangles.size() / 3);
	check(vh.triangles.size() / 3 <= 2 * (24 * 5 + 2), "and never more than twice the support points");
	// AND THE SHAPE IS KEPT: the cut hull reaches within 4% of the true one in
	// every direction it was not cut along.
	shade::Hull whole = shade::hull(villager);
	double worst = 0.0;
	for (int i = 0; i < 360; i += 7) {
		for (int j = -80; j <= 80; j += 20) {
			const double a = i * shade::PI / 180.0, b = j * shade::PI / 180.0;
			const V3 d(std::cos(b) * std::cos(a), std::sin(b), std::cos(b) * std::sin(a));
			double cut = -1e9, full = -1e9;
			for (const V3 &p : vh.points) cut = std::max(cut, p.dot(d));
			for (const V3 &p : whole.points) full = std::max(full, p.dot(d));
			worst = std::max(worst, (full - cut) / full);
		}
	}
	std::printf("    the cut hull falls short of the whole by at most %.1f%%\n", worst * 100.0);
	check(worst < 0.04, "and loses under 4% of the shape anywhere");

	std::mt19937 rng(7);
	std::uniform_real_distribution<double> u(-3.0, 3.0);
	bool all = true;
	for (int round = 0; round < 50; round++) {
		std::vector<V3> cloud;
		for (int i = 0; i < 200; i++) {
			cloud.emplace_back(u(rng), u(rng) * 0.5, u(rng));
		}
		all = all && sound(shade::hull(cloud), cloud);
	}
	check(all, "fifty random clouds of two hundred: every hull sound");

	std::printf("THE SUN\n");
	const V3 noon = shade::sun_direction(0.5, 20.0);
	check(std::fabs(noon.y + 1.0) < 1e-9, "straight down at noon");
	check(shade::sun_direction(0.0, 20.0).y > 0.99, "under the world at midnight");
	const V3 morning = shade::sun_direction(0.3, 20.0);
	check(morning.y < 0.0 && morning.z < 0.0, "low and slanting in the morning");

	shade::SunStepper sun;
	check(sun.update(0.5, 0.016), "the first frame is taken at once");
	check(std::fabs(sun.strength() - sun.darkest) < 1e-9, "full shadow at noon");
	int changed = 0;
	const double dt = 1.0 / 30.0;
	double day = 0.5;
	for (int f = 0; f < 30 * 60; f++) { // a minute of play
		day += dt / sun.day_seconds;
		changed += sun.update(day, dt) ? 1 : 0;
	}
	const int steps = int(60.0 / sun.step_seconds);
	std::printf("    a minute: %d steps, %d frames told the shader (of %d)\n", steps, changed, 30 * 60);
	check(changed <= steps * int(std::ceil(sun.ease_seconds * 30.0) + 1),
			"the shader is told only while a step eases");
	check(changed >= steps, "and it is told every step");
	sun.update(0.0, dt);
	check(sun.strength() == 0.0, "no shadow at night (a jump is taken at once)");

	std::printf("THE LIGHTS\n");
	std::vector<shade::Light> lights = {
		{ { 0, 2, 0 }, 22.0, 1.0 },    // a blast at the eye
		{ { 400, 2, 0 }, 22.0, 1.0 },  // a blast across the map
		{ { 5, 1, 5 }, 5.0, 0.4 },     // a lantern nearby
		{ { 8, 1, 0 }, 9.0, 0.0 },     // dark: a flash already spent
		{ { -6, 3, 2 }, 9.0, 0.6 },
		{ { 10, 3, 10 }, 9.0, 0.6 },
		{ { 12, 3, 12 }, 7.0, 0.5 },
	};
	std::vector<int> got = shade::pick(lights, { 0, 0, 0 }, 120.0);
	check(int(got.size()) == shade::SLOTS, "four slots filled when more than four burn");
	check(!got.empty() && got[0] == 0, "the blast at the eye comes first");
	bool far = false, dark = false;
	for (int i : got) {
		far = far || i == 1;
		dark = dark || i == 3;
	}
	check(!far, "a blast out of sight takes no slot");
	check(!dark, "a spent flash takes no slot");
	check(shade::power_of(7.0) == 1.0 && shade::power_of(1.6) < 0.5, "energy reads as 0..1");

	std::printf("\n%s\n", failures ? "FAIL" : "Success: no problems found");
	return failures ? 1 : 0;
}
