#include "shadow_baker.h"

#include "shade_core.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

using namespace godot;

void ShadowBaker::_bind_methods() {
	ClassDB::bind_method(D_METHOD("bake", "mesh"), &ShadowBaker::bake);
	ClassDB::bind_method(D_METHOD("bake_points", "points"), &ShadowBaker::bake_points);
	ClassDB::bind_method(D_METHOD("set_most", "most"), &ShadowBaker::set_most);
	ClassDB::bind_method(D_METHOD("get_most"), &ShadowBaker::get_most);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "most"), "set_most", "get_most");
}

Ref<ArrayMesh> ShadowBaker::bake(const Ref<Mesh> &p_mesh) const {
	if (p_mesh.is_null()) {
		return Ref<ArrayMesh>();
	}
	PackedVector3Array all;
	for (int s = 0; s < p_mesh->get_surface_count(); s++) {
		const Array arrays = p_mesh->surface_get_arrays(s);
		if (arrays.size() <= Mesh::ARRAY_VERTEX) {
			continue;
		}
		all.append_array(PackedVector3Array(arrays[Mesh::ARRAY_VERTEX]));
	}
	return bake_points(all);
}

Ref<ArrayMesh> ShadowBaker::bake_points(const PackedVector3Array &p_points) const {
	std::vector<shade::V3> cloud;
	cloud.reserve(p_points.size());
	for (int i = 0; i < p_points.size(); i++) {
		const Vector3 &p = p_points[i];
		cloud.emplace_back(p.x, p.y, p.z);
	}
	const shade::Hull hull = shade::hull(cloud, 0.0, most);
	if (hull.empty()) {
		return Ref<ArrayMesh>();
	}
	// IN THE MODEL'S OWN SPACE, unmoved. The shader lays the shadow on the
	// plane through the origin of the node it hangs from — a villager's feet,
	// a house's floor, a tree's root — which is where every model in this game
	// meets the ground. Not the hull's lowest point: a house's foundation runs
	// a metre into the earth, and its shadow would be buried with it.
	PackedVector3Array verts;
	verts.resize(int64_t(hull.points.size()));
	for (size_t i = 0; i < hull.points.size(); i++) {
		const shade::V3 &p = hull.points[i];
		verts.set(int64_t(i), Vector3(real_t(p.x), real_t(p.y), real_t(p.z)));
	}
	PackedInt32Array index;
	index.resize(int64_t(hull.triangles.size()));
	for (size_t i = 0; i < hull.triangles.size(); i++) {
		index.set(int64_t(i), hull.triangles[i]);
	}
	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = verts;
	arrays[Mesh::ARRAY_INDEX] = index;
	Ref<ArrayMesh> mesh;
	mesh.instantiate();
	mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
	return mesh;
}
