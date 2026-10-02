// THE DOOR GODOT COMES IN BY. `shade_library_init` is the entry_symbol named in
// bin/shade/shade.gdextension; it registers the two classes, and from then on
// GDScript can make them with ClassDB.instantiate (see scripts/shade.gd, which
// never names them directly so the game still parses without this library).
#include "register_types.h"

#include <gdextension_interface.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "shadow_baker.h"
#include "shadow_sky.h"

using namespace godot;

void initialize_shade_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(ShadowBaker);
	GDREGISTER_CLASS(ShadowSky);
}

void uninitialize_shade_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT shade_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	::godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_shade_module);
	init_obj.register_terminator(uninitialize_shade_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
