// =============================================================================
// register_types.cpp  (v3)
// =============================================================================

#include "register_types.h"
#include "opcua_node_id.h"
#include "godot_opcua.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_opcua_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) return;

    // OpcUaNodeId must be registered before GodotOpcUa because GodotOpcUa
    // exposes methods whose parameter types reference OpcUaNodeId.
    GDREGISTER_CLASS(OpcUaNodeId);
    GDREGISTER_CLASS(GodotOpcUa);
}

void uninitialize_opcua_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
}

extern "C" {

GDExtensionBool GDE_EXPORT opcua_library_init(
        GDExtensionInterfaceGetProcAddress p_get_proc_address,
        const GDExtensionClassLibraryPtr   p_library,
        GDExtensionInitialization         *r_initialization) {

    godot::GDExtensionBinding::InitObject init_obj(
        p_get_proc_address, p_library, r_initialization);

    init_obj.register_initializer(initialize_opcua_module);
    init_obj.register_terminator(uninitialize_opcua_module);
    init_obj.set_minimum_library_initialization_level(
        MODULE_INITIALIZATION_LEVEL_SCENE);

    return init_obj.init();
}

} // extern "C"
