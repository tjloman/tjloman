// SHADOW BAKER — a model's shadow shape, baked once.
//
// Hands back the model's convex hull as an ArrayMesh, in the model's own
// space. Hung under the model on a MeshInstance3D with the baked-shadow
// material (shaders/baked_shadow.gdshader), it is flattened onto the ground
// along the sun every frame on the GPU: no shadow map, no second pass of the
// scene, nothing on the CPU after this call. See shade_core.hpp for why a
// convex hull, and Shade (scripts/shade.gd) for who calls this.
#pragma once

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

namespace godot {

class ShadowBaker : public RefCounted {
	GDCLASS(ShadowBaker, RefCounted)

	// Past this many distinct points a cloud is cut to its support points
	// first; see shade::supports. Every hull is then a few hundred triangles.
	int most = 64;

protected:
	static void _bind_methods();

public:
	// Every surface of `mesh`, in its own space. Null if it casts nothing.
	Ref<ArrayMesh> bake(const Ref<Mesh> &p_mesh) const;
	// A model made of several parts: their vertices, gathered by the caller
	// into one space. Null if they cast nothing.
	Ref<ArrayMesh> bake_points(const PackedVector3Array &p_points) const;

	void set_most(int p_most) { most = p_most; }
	int get_most() const { return most; }
};

} // namespace godot
