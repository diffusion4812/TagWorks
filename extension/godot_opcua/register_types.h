// =============================================================================
// register_types.h  (v3 — registers OpcUaNodeId in addition to GodotOpcUa)
// =============================================================================

#pragma once

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void initialize_opcua_module(ModuleInitializationLevel p_level);
void uninitialize_opcua_module(ModuleInitializationLevel p_level);
