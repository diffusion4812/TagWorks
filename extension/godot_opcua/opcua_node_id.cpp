// =============================================================================
// opcua_node_id.cpp
// =============================================================================

#include "opcua_node_id.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

// ============================================================================
// ClassDB
// ============================================================================

void OpcUaNodeId::_bind_methods() {

    // ── Enum ──────────────────────────────────────────────────────────────────
    BIND_ENUM_CONSTANT(NUMERIC);
    BIND_ENUM_CONSTANT(STRING_ID);

    // ── Factories ─────────────────────────────────────────────────────────────
    ClassDB::bind_static_method("OpcUaNodeId",
        D_METHOD("numeric", "namespace_index", "node_id"),
        &OpcUaNodeId::numeric);
    ClassDB::bind_static_method("OpcUaNodeId",
        D_METHOD("from_string_id", "namespace_index", "node_id"),
        &OpcUaNodeId::from_string_id);
    ClassDB::bind_static_method("OpcUaNodeId",
        D_METHOD("parse", "tag_name"),
        &OpcUaNodeId::parse);

    // ── Properties ────────────────────────────────────────────────────────────
    ClassDB::bind_method(D_METHOD("set_namespace_index", "ns"),
                         &OpcUaNodeId::set_namespace_index);
    ClassDB::bind_method(D_METHOD("get_namespace_index"),
                         &OpcUaNodeId::get_namespace_index);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "namespace_index"),
                 "set_namespace_index", "get_namespace_index");

    ClassDB::bind_method(D_METHOD("set_identifier_type", "type"),
                         &OpcUaNodeId::set_identifier_type);
    ClassDB::bind_method(D_METHOD("get_identifier_type"),
                         &OpcUaNodeId::get_identifier_type);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "identifier_type",
                     PROPERTY_HINT_ENUM, "Numeric,StringID"),
                 "set_identifier_type", "get_identifier_type");

    ClassDB::bind_method(D_METHOD("set_numeric_id", "id"),
                         &OpcUaNodeId::set_numeric_id);
    ClassDB::bind_method(D_METHOD("get_numeric_id"),
                         &OpcUaNodeId::get_numeric_id);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "numeric_id"),
                 "set_numeric_id", "get_numeric_id");

    ClassDB::bind_method(D_METHOD("set_string_id", "id"),
                         &OpcUaNodeId::set_string_id);
    ClassDB::bind_method(D_METHOD("get_string_id"),
                         &OpcUaNodeId::get_string_id);
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "string_id"),
                 "set_string_id", "get_string_id");

    // ── Utility ───────────────────────────────────────────────────────────────
    ClassDB::bind_method(D_METHOD("to_tag_name"), &OpcUaNodeId::to_tag_name);
    ClassDB::bind_method(D_METHOD("equals", "other"), &OpcUaNodeId::equals);
}

// ============================================================================
// Factories
// ============================================================================

Ref<OpcUaNodeId> OpcUaNodeId::numeric(int namespace_index, int64_t node_id) {
    Ref<OpcUaNodeId> n;
    n.instantiate();
    n->_namespace_index = namespace_index;
    n->_type            = NUMERIC;
    n->_numeric_id      = node_id;
    return n;
}

Ref<OpcUaNodeId> OpcUaNodeId::from_string_id(int namespace_index, String node_id) {
    Ref<OpcUaNodeId> n;
    n.instantiate();
    n->_namespace_index = namespace_index;
    n->_type            = STRING_ID;
    n->_string_id       = node_id;
    return n;
}

Ref<OpcUaNodeId> OpcUaNodeId::parse(String tag_name) {
    // Expected formats: "ns1|i=1001"  or  "ns2|s=Axis1.Speed"
    // Namespace prefix: "ns<N>|"
    const int pipe_pos = tag_name.find("|");
    if (pipe_pos < 2) {
        UtilityFunctions::push_warning(
            String("OpcUaNodeId::parse: missing '|' in '") + tag_name + "'");
        return Ref<OpcUaNodeId>();
    }

    const String ns_part = tag_name.substr(0, pipe_pos);          // "ns1"
    const String id_part = tag_name.substr(pipe_pos + 1);         // "i=1001"

    if (!ns_part.begins_with("ns")) {
        UtilityFunctions::push_warning(
            String("OpcUaNodeId::parse: namespace prefix must start with 'ns', got '") +
            ns_part + "'");
        return Ref<OpcUaNodeId>();
    }

    const int ns_index = static_cast<int>(ns_part.substr(2).to_int());

    if (id_part.begins_with("i=")) {
        return numeric(ns_index, id_part.substr(2).to_int());
    } else if (id_part.begins_with("s=")) {
        return from_string_id(ns_index, id_part.substr(2));
    }

    UtilityFunctions::push_warning(
        String("OpcUaNodeId::parse: unknown identifier type in '") + id_part + "'");
    return Ref<OpcUaNodeId>();
}

// ============================================================================
// Properties
// ============================================================================

void OpcUaNodeId::set_namespace_index(int ns)          { _namespace_index = ns; }
int  OpcUaNodeId::get_namespace_index() const          { return _namespace_index; }

void OpcUaNodeId::set_identifier_type(IdentifierType t){ _type = t; }
OpcUaNodeId::IdentifierType OpcUaNodeId::get_identifier_type() const { return _type; }

void    OpcUaNodeId::set_numeric_id(int64_t id)   { _numeric_id = id; }
int64_t OpcUaNodeId::get_numeric_id() const        { return _numeric_id; }

void   OpcUaNodeId::set_string_id(String id)  { _string_id = id; }
String OpcUaNodeId::get_string_id() const     { return _string_id; }

// ============================================================================
// Utility
// ============================================================================

String OpcUaNodeId::to_tag_name() const {
    String prefix = "ns" + String::num_int64(_namespace_index) + "|";
    switch (_type) {
        case NUMERIC:   return prefix + "i=" + String::num_int64(_numeric_id);
        case STRING_ID: return prefix + "s=" + _string_id;
        default:        return prefix + "?";
    }
}

bool OpcUaNodeId::equals(Ref<OpcUaNodeId> other) const {
    if (other.is_null()) return false;
    if (_namespace_index != other->_namespace_index) return false;
    if (_type != other->_type) return false;
    if (_type == NUMERIC)   return _numeric_id == other->_numeric_id;
    if (_type == STRING_ID) return _string_id  == other->_string_id;
    return false;
}

// ============================================================================
// Internal C++ helpers
// ============================================================================

UA_NodeId OpcUaNodeId::to_ua_node_id() const {
    switch (_type) {
        case NUMERIC: {
            // Numeric NodeIds carry no heap allocation; UA_NodeId_clear is a no-op.
            UA_NodeId nid;
            UA_NodeId_init(&nid);
            nid.namespaceIndex        = static_cast<UA_UInt16>(_namespace_index);
            nid.identifierType        = UA_NODEIDTYPE_NUMERIC;
            nid.identifier.numeric    = static_cast<UA_UInt32>(_numeric_id);
            return nid;
        }
        case STRING_ID: {
            // UA_STRING_ALLOC copies the bytes onto the open62541 heap.
            // The caller MUST call UA_NodeId_clear() to free them.
            const CharString utf8 = _string_id.utf8();
            UA_NodeId nid;
            UA_NodeId_init(&nid);
            nid.namespaceIndex     = static_cast<UA_UInt16>(_namespace_index);
            nid.identifierType     = UA_NODEIDTYPE_STRING;
            nid.identifier.string  = UA_STRING_ALLOC(utf8.get_data());
            return nid;
        }
        default:
            return UA_NODEID_NUMERIC(0, 0);
    }
}

Ref<OpcUaNodeId> OpcUaNodeId::from_ua_node_id(const UA_NodeId &id) {
    Ref<OpcUaNodeId> n;
    n.instantiate();
    n->_namespace_index = id.namespaceIndex;
    switch (id.identifierType) {
        case UA_NODEIDTYPE_NUMERIC:
            n->_type       = NUMERIC;
            n->_numeric_id = static_cast<int64_t>(id.identifier.numeric);
            break;
        case UA_NODEIDTYPE_STRING:
            n->_type = STRING_ID;
            if (id.identifier.string.data && id.identifier.string.length > 0)
                n->_string_id = String::utf8(
                    reinterpret_cast<const char *>(id.identifier.string.data),
                    static_cast<int>(id.identifier.string.length));
            break;
        default:
            // GUID and ByteString are represented as their string form.
            n->_type      = STRING_ID;
            n->_string_id = "<unsupported-id-type>";
            break;
    }
    return n;
}

Ref<OpcUaNodeId> OpcUaNodeId::from_ua_expanded_node_id(const UA_ExpandedNodeId &id) {
    return from_ua_node_id(id.nodeId);
}
