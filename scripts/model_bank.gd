extends Node
## Autoload `ModelBank`: lets custom art replace the procedural primitives.
##
## Drop a file named after the thing into res://models/ and it takes over;
## when the file is absent, the game builds its primitive version as before.
## So the game ships and runs with nothing in res://models/, and every model
## you add is picked up automatically — no code changes.
##
## Recognised names (any of the extensions below):
##   villager · creature · tree · tree_forest/grassland/savanna/wetland ·
##   bush · flower · rock · house · school · store · hand ·
##   and one per animal SPECIES: sheep, wolf, deer, horse, ox, pig, chicken,
##   dog, llama, giraffe, bear, lion, tiger, frog
##
## Modelling rules (see the triangle budgets): keep each model ONE mesh with
## ONE material, pivot at the feet, +Z forward, scaled to match the current
## silhouette. LOD culling and the throw/animation systems then just work.

const DIR := "res://models/"
## .glb/.gltf are the usual Blender exports; .obj a single mesh; .scn/.tscn a
## Godot scene; .tres/.res a saved Mesh resource.
## EVERY NAME THIS BANK IS EVER ASKED FOR that is not an animal species (those
## come from Animal.SPECIES). Kept so the opening screen can look each one up
## once while the player is still reading — every miss is a walk over the
## filesystem, and on a phone a dozen of those landing on the first frame a
## village is drawn is a hitch you can see. See StartScreen._fill_warm_jobs.
const KNOWN: Array[String] = [
	"villager", "villager_female", "villager_male", "creature", "tree",
	"tree_forest", "tree_grassland", "tree_savanna", "tree_wetland",
	"bush", "flower", "rock", "house", "school", "store", "hand", "nest",
]

const EXTS: Array[String] = [".glb", ".gltf", ".obj", ".scn", ".tscn", ".tres", ".res"]

# name -> loaded Resource, or null when we've checked and found nothing. Both
# outcomes are cached so a spawn storm never re-hits the filesystem.
var _cache := {}
# name -> extracted Mesh (for MultiMesh clutter), cached the same way.
var _mesh_cache := {}
# name -> how big it actually is, in metres at scale one. See `bounds`.
var _size_cache := {}


## True if a custom model exists for this name.
func has(model_name: String) -> bool:
	return _resolve(model_name) != null


## A fresh Node3D instance of the custom model, or null if there is none.
## The caller adds it to its visuals and skips the procedural build.
func instantiate(model_name: String) -> Node3D:
	var res := _resolve(model_name)
	if res == null:
		return null
	if res is PackedScene:
		return (res as PackedScene).instantiate() as Node3D
	if res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res as Mesh
		return mi
	return null


## First existing model for name, else for any fallback name in order.
## e.g. instantiate_any(["tree_forest", "tree"]) tries the styled model first.
func instantiate_any(names: Array) -> Node3D:
	for n: String in names:
		var node := instantiate(n)
		if node != null:
			return node
	return null


## The first Mesh inside a custom model — for clutter that draws through a
## MultiMesh (flowers) and needs the raw mesh, not a node. Null if there is no
## custom model, or it holds no mesh. Cached like everything else here.
func mesh_for(model_name: String) -> Mesh:
	if _mesh_cache.has(model_name):
		return _mesh_cache[model_name]
	var mesh: Mesh = null
	var res := _resolve(model_name)
	if res is Mesh:
		mesh = res as Mesh
	elif res is PackedScene:
		var inst := (res as PackedScene).instantiate()
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			mesh = (mi as MeshInstance3D).mesh
			if mesh != null:
				break
		inst.free()  # the Mesh is ref-counted and outlives the throwaway node
	_mesh_cache[model_name] = mesh
	return mesh


func _resolve(model_name: String) -> Resource:
	if _cache.has(model_name):
		return _cache[model_name]
	var found: Resource = null
	for ext: String in EXTS:
		var path := DIR + model_name + ext
		if ResourceLoader.exists(path):
			found = ResourceLoader.load(path)
			if found != null:
				break
	_cache[model_name] = found
	return found


## HOW BIG A MODEL ACTUALLY IS, in metres at scale one.
##
## THE FAR RING'S BILLBOARD TREES WERE SIZED OFF THE PRIMITIVE. WildTree.crown
## knows the fallback is a 1.6m cone on a 3.5m bole, because that is what the
## fallback IS — and the moment a tree_forest.glb landed beside it that figure
## became fiction, so the wood on the horizon stood at whatever size the
## primitive would have been rather than the size of the trees it stands in for.
##
## Measured, not declared, because a model's dimensions are the modeller's
## business and nobody should have to come back here and retype them. Measured
## ONCE per name and kept: this instantiates the scene to read it, which is far
## too expensive to do per tree, and exactly cheap enough to do per style.
##
## Returns a zero-size AABB when there is no model — which is the caller's cue
## to use whatever the primitive would have been.
func bounds(model_name: String) -> AABB:
	if _size_cache.has(model_name):
		return _size_cache[model_name]
	var box := AABB()
	var node := instantiate(model_name)
	if node != null:
		box = _measure(node)
		node.queue_free()
	_size_cache[model_name] = box
	return box


## The first of these names that has a model, measured. Mirrors
## `instantiate_any`, so a caller asks the same question the same way.
func bounds_any(names: Array) -> AABB:
	for n: String in names:
		var box := bounds(n)
		if box.size.y > 0.0:
			return box
	return AABB()


## Every renderable in the model, merged, in the model's own space.
##
## Walked by hand rather than read off `mesh_for().get_aabb()`, because that
## would miss a mesh the artist parented under a scaled or offset node — which
## is most of what comes out of Blender. The root's own transform is skipped:
## the root IS the model's origin.
func _measure(root: Node3D) -> AABB:
	var boxes: Array[AABB] = []
	if root is VisualInstance3D:
		boxes.append((root as VisualInstance3D).get_aabb())
	for kid in root.get_children():
		_gather(kid, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return AABB()
	var box: AABB = boxes[0]
	for i in range(1, boxes.size()):
		box = box.merge(boxes[i])
	return box


func _gather(node: Node, at: Transform3D, out: Array[AABB]) -> void:
	var here := at
	if node is Node3D:
		here = at * (node as Node3D).transform
	if node is VisualInstance3D:
		out.append(here * (node as VisualInstance3D).get_aabb())
	for kid in node.get_children():
		_gather(kid, here, out)
