// =============================================================================
// godot_opcua.h  (v4)
//
// Architecture change from v3
// ────────────────────────────
// The internal poll thread has been removed entirely.  The GDScript manager
// now calls iterate() from _process(), which drives UA_Client_run_iterate()
// on the main thread.  This eliminates all cross-thread Godot API calls,
// all mutexes, and all atomics.  _on_data_change() fires synchronously on
// the main thread inside iterate(), so registered Callables can be invoked
// directly without any deferred queuing.
//
// Breaking changes from v3
// ─────────────────────────
// • start_polling / stop_polling / set_reconnect_interval /
//   set_max_reconnect_attempts removed — reconnection logic moves to GDScript.
// • is_server_connected / has_connection_failed removed.
// • create_subscription no longer takes a node_specs Array — it only creates
//   the OPC UA subscription and returns a handle.  Use subscribe() to add tags.
// • add_monitored_item / remove_monitored_item replaced by subscribe() /
//   unsubscribe() which accept a Callable and support multiple subscribers
//   per tag with automatic fan-out.
// • All signals removed — the C++ layer emits nothing.  GDScript owns state.
// • disconnect_server() resets server-side IDs but preserves all subscription
//   configs and Callables so replay_subscriptions() can restore them cleanly.
// =============================================================================

#pragma once

#include <godot_cpp/classes/global_constants.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

#include "opcua_node_id.h"

extern "C" {
#include "open62541.h"
}

namespace godot {

// ── Internal types (not exposed to GDScript) ──────────────────────────────────

/// Heap-allocated context for one monitored node.
/// A raw pointer to this struct is passed to open62541 as monitoredItemContext.
/// GodotOpcUa owns all instances via unique_ptr in _item_registry, which
/// guarantees a stable address even when the registry map rehashes.
struct MonitoredItemContext {
    String                tag_name;
    Ref<OpcUaNodeId>      node_id;
    UA_UInt32             mon_id      = 0;   ///< Server-assigned; 0 when not active
    int                   sub_handle  = -1;  ///< Which subscription this belongs to
    float                 sampling_ms = 250.0f;
    float                 deadband    = 0.0f;
    std::vector<Callable> callbacks;         ///< Fan-out list; called in order on change
};

/// Lightweight subscription record — just enough to recreate the server-side
/// subscription after a reconnect.
struct SubscriptionEntry {
    UA_UInt32 sub_id      = 0;       ///< Server-assigned; 0 when not active
    float     interval_ms = 1000.0f;
};

// =============================================================================
// GodotOpcUa
// =============================================================================
class GodotOpcUa : public RefCounted {
    GDCLASS(GodotOpcUa, RefCounted)

private:
    // ── Authentication ────────────────────────────────────────────────────────
    enum class AuthMode { Anonymous, Username };
    AuthMode _auth_mode = AuthMode::Anonymous;
    String   _auth_username;
    String   _auth_password;

    // ── OPC UA client ─────────────────────────────────────────────────────────
    UA_Client *_client   = nullptr;
    String     _last_url;

    // ── Subscriptions: handle → entry ─────────────────────────────────────────
    std::unordered_map<int, SubscriptionEntry> _subscriptions;
    int _next_sub_handle = 1;

    // ── Item registry: tag_name (utf8) → context (owned) ─────────────────────
    // unique_ptr gives stable heap addresses for the open62541 context pointer.
    std::unordered_map<std::string, std::unique_ptr<MonitoredItemContext>> _item_registry;

    // ── Value cache: tag_name → entry Dictionary ──────────────────────────────
    // {value, timestamp_ms, quality, quality_good, tick}
    // Written from _on_data_change (main thread only — no mutex needed).
    Dictionary _latest_values;

    // ── Browse ────────────────────────────────────────────────────────────────
    int _max_browse_depth = 5;

    // ── Type conversion ───────────────────────────────────────────────────────
    Variant    _ua_variant_to_godot(const UA_Variant &ua_var) const;
    bool       _godot_to_ua_variant(const Variant &gd_var, UA_Variant &out) const;
    Dictionary _make_tag_entry(const UA_DataValue &dv) const;
    static Error _map_ua_status_to_error(UA_StatusCode rs);
    String _ua_builtin_type_name(UA_UInt32 numeric_id) const;

    // ── Node ID helpers ───────────────────────────────────────────────────────
    static String      _node_id_to_string(const UA_NodeId &id);
    static const char *_node_class_to_string(UA_NodeClass nc);

    // ── Connection ────────────────────────────────────────────────────────────
    UA_StatusCode _do_connect(UA_Client *client, const String &url);

    // ── Subscription internals ────────────────────────────────────────────────

    /// Create a new UA_Client with default config; does not connect.
    bool _init_client();

    /// Create/recreate the server-side OPC UA Subscription for one entry.
    bool _create_subscription_server_side(int handle, SubscriptionEntry &entry);

    /// Create/recreate one server-side MonitoredItem for a context.
    void _create_monitored_item(MonitoredItemContext &ctx, UA_UInt32 sub_id);

    // ── Browse helpers ────────────────────────────────────────────────────────
    bool _browse_with_continuation(const UA_NodeId &nodeId,
                                   Array           &out_children,
                                   int              depth);
    void _process_browse_result(Array                &out_children,
                                const UA_BrowseResult &result,
                                int                    depth);

    // ── Data-change callback (fires on main thread inside iterate()) ──────────
    static void _on_data_change(UA_Client    *client,
                                UA_UInt32     subId,  void *subContext,
                                UA_UInt32     monId,  void *monContext,
                                UA_DataValue *value);

protected:
    static void _bind_methods();

public:
    GodotOpcUa();
    ~GodotOpcUa() override;

    // ── Connection ────────────────────────────────────────────────────────────

    Error connect_to_server(String url);
    Error connect_with_credentials(String url, String username, String password);

    /// Reset server-side IDs and disconnect.  Subscription configs and all
    /// registered Callables are preserved so replay_subscriptions() works.
    void disconnect_server();

    // ── OPC UA network driver ─────────────────────────────────────────────────

    /// Call from GDScript _process().  Drives UA_Client_run_iterate(), which
    /// processes incoming publish responses and fires _on_data_change for each
    /// changed tag.  Everything runs synchronously on the calling (main) thread.
    /// timeout_ms = 0 → non-blocking poll; 1 is a good default.
    Error GodotOpcUa::iterate(int timeout_ms);

    /// Re-create all server-side subscriptions and monitored items after a
    /// reconnect.  Call this from GDScript immediately after a successful
    /// connect_to_server() / connect_with_credentials() following a drop.
    void replay_subscriptions();

    // ── Synchronous read / write ──────────────────────────────────────────────

    Variant    read_node(Ref<OpcUaNodeId> node_id);
    Dictionary read_node_data_type(const String &node_id_string);
    Dictionary read_nodes(Array node_ids);
    bool       write_node(Ref<OpcUaNodeId> node_id, const Variant &value);
    Dictionary call_ua_method(Ref<OpcUaNodeId> object_id,
                              Ref<OpcUaNodeId> method_id,
                              Array            input_args);

    // ── Subscription management ───────────────────────────────────────────────

    /// Create a new OPC UA subscription with the given publishing interval.
    /// Returns a handle (> 0) used by subscribe() / delete_subscription().
    /// Safe to call before connect_to_server() — the server-side subscription
    /// is created lazily on the next replay_subscriptions() call.
    int  create_subscription(float interval_ms);
    void delete_subscription(int handle);

    /// Register a Callable to be invoked whenever node_id's value or quality
    /// changes.  If node_id is already subscribed, the callable is simply
    /// appended to the existing fan-out list — no extra MonitoredItem is
    /// created on the server.  Safe to call before connect_to_server().
    ///
    /// Callable signature: func(entry: Dictionary) -> void
    ///   entry keys: value, timestamp_ms, quality, quality_good, tick
    bool subscribe(int              handle,
                   Ref<OpcUaNodeId> node_id,
                   Callable         callable,
                   float            sampling_ms,
                   float            deadband);

    /// Remove one Callable from a tag's fan-out list.  Deletes the server-side
    /// MonitoredItem when the last Callable is removed.
    void unsubscribe(Ref<OpcUaNodeId> node_id, Callable callable);

    /// Remove all subscriptions, monitored items, and registered Callables.
    void clear_subscriptions();

    // ── Value cache ───────────────────────────────────────────────────────────

    /// Returns the cached value Variant, or NIL if no value received yet.
    Variant    get_tag_value(String tag_name);

    /// Returns the full cached entry: {value, timestamp_ms, quality,
    /// quality_good, tick}.  Returns empty Dictionary if not yet received.
    Dictionary get_tag_entry(String tag_name);

    /// Full cache snapshot: tag_name → entry Dictionary.
    Dictionary get_all_tag_entries();

    /// Returns entries whose tick > since_tick_ms.  Use with
    /// Time.get_ticks_msec() for a pull-based update path alongside callbacks.
    Dictionary get_changed_tags_since(int64_t since_tick_ms);

    // ── Browsing ──────────────────────────────────────────────────────────────

    Dictionary browse_server();
    Array      browse_children(Ref<OpcUaNodeId> node_id);

    // ── Discovery ─────────────────────────────────────────────────────────────

    Array discover_servers(String discovery_url);
    Array get_endpoints(String url);
};

} // namespace godot