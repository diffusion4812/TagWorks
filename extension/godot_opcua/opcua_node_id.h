// =============================================================================
// opcua_node_id.h
//
// OpcUaNodeId — a Godot Resource wrapping an OPC UA NodeId.
//
// Supports numeric (ns=1;i=1001) and string (ns=2;s=MyNode) identifiers,
// matching the two identifier types most common in real PLC/SCADA deployments.
//
// GDScript usage:
//   var n = OpcUaNodeId.numeric(1, 1001)
//   var s = OpcUaNodeId.from_string_id(2, "Axis1.Speed")
//   var p = OpcUaNodeId.parse("ns1|i=1001")
//   print(n.to_tag_name())  # "ns1|i=1001"
//
// C++ usage:
//   UA_NodeId nid = node->to_ua_node_id();
//   // ... use nid ...
//   UA_NodeId_clear(&nid);   // ALWAYS clear — allocates for STRING type
// =============================================================================

#pragma once

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/string.hpp>

extern "C" {
#include "open62541.h"
}

namespace godot {

class OpcUaNodeId : public Resource {
    GDCLASS(OpcUaNodeId, Resource)

public:
    enum IdentifierType {
        NUMERIC   = 0,
        STRING_ID = 1,
    };

private:
    int            _namespace_index = 0;
    IdentifierType _type            = NUMERIC;
    int64_t        _numeric_id      = 0;
    String         _string_id;

protected:
    static void _bind_methods();

public:
    OpcUaNodeId() = default;
    ~OpcUaNodeId() override = default;

    // ── Factory methods (GDScript-callable static constructors) ──────────────

    /// Create a numeric NodeId.  e.g. OpcUaNodeId.numeric(1, 1001)
    static Ref<OpcUaNodeId> numeric(int namespace_index, int64_t node_id);

    /// Create a string NodeId.  e.g. OpcUaNodeId.from_string_id(2, "Axis1.Speed")
    static Ref<OpcUaNodeId> from_string_id(int namespace_index, String node_id);

    /// Parse a canonical tag-name string into a NodeId.
    ///   "ns1|i=1001"       → numeric ns=1, id=1001
    ///   "ns2|s=Axis1.Speed" → string  ns=2, id="Axis1.Speed"
    /// Returns null Ref on parse failure.
    static Ref<OpcUaNodeId> parse(String tag_name);

    // ── Properties ────────────────────────────────────────────────────────────

    void           set_namespace_index(int ns);
    int            get_namespace_index() const;

    void           set_identifier_type(IdentifierType t);
    IdentifierType get_identifier_type() const;

    void           set_numeric_id(int64_t id);
    int64_t        get_numeric_id() const;

    void           set_string_id(String id);
    String         get_string_id() const;

    // ── Utility ───────────────────────────────────────────────────────────────

    /// Return the canonical tag-name string: "ns<N>|i=<ID>" or "ns<N>|s=<str>".
    String to_tag_name() const;

    /// True if this NodeId represents the same node as other.
    bool equals(Ref<OpcUaNodeId> other) const;

    // ── Internal C++ helpers (not exposed to GDScript) ────────────────────────

    /// Build a UA_NodeId.
    /// IMPORTANT: the caller MUST call UA_NodeId_clear() on the returned value.
    /// For NUMERIC this is a safe no-op; for STRING_ID it frees the allocated bytes.
    UA_NodeId to_ua_node_id() const;

    /// Wrap a UA_NodeId in an OpcUaNodeId Ref (deep-copies the identifier).
    static Ref<OpcUaNodeId> from_ua_node_id(const UA_NodeId &id);

    /// Wrap the inner NodeId of a UA_ExpandedNodeId.
    static Ref<OpcUaNodeId> from_ua_expanded_node_id(const UA_ExpandedNodeId &id);
};

} // namespace godot

VARIANT_ENUM_CAST(godot::OpcUaNodeId::IdentifierType)
