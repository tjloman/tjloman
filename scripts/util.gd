class_name Util
## Static helpers for building ugly-but-honest placeholder visuals from primitives.


static func mat(color: Color, emission := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission:
		m.emission_enabled = true
		m.emission = Color(color.r, color.g, color.b)
		m.emission_energy_multiplier = 1.5
	return m


static func mesh_node(mesh: Mesh, color: Color, pos := Vector3.ZERO, emission := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color, emission)
	mi.position = pos
	return mi


static func box(size: Vector3, color: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return mesh_node(m, color, pos)


static func sphere(radius: float, color: Color, pos := Vector3.ZERO, emission := false) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	return mesh_node(m, color, pos, emission)


static func capsule(radius: float, height: float, color: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	return mesh_node(m, color, pos)


static func cylinder(
		radius: float, height: float, color: Color,
		pos := Vector3.ZERO, emission := false) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	return mesh_node(m, color, pos, emission)


static func prism(size: Vector3, color: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var m := PrismMesh.new()
	m.size = size
	return mesh_node(m, color, pos)


## Simple billboard status label used above villagers/creature heads.
static func status_label(text := "", pixel_size := 0.01) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = pixel_size
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 48
	l.outline_size = 12
	l.modulate = Color(1, 1, 1, 0.95)
	return l
