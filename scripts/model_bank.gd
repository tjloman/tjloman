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
