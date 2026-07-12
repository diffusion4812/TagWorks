// =============================================================================
// godot_opcua.h  (v3)
//
// Threading model — unchanged from v2
// ─────────────────────────────────────
// _ua_mutex   serialises every UA_Client_* call (poll thread + main thread).
// _values_mutex guards _latest_values independently so GDScript can read
// cached values without waiting on UA network I/O.
//
// Breaking changes from v2
// ─────────────────────────
// • read_node / write_node now accept Ref<OpcUaNodeId> instead of (int, int).
// • browse_children now accepts Ref<OpcUaNodeId>.
// • tag_updated signal now carries a Dictionary entry (value/timestamp/quality)
//   instead of a bare Variant.
// • Multiple subscriptions are supported; create_subscription returns an int
//   handle instead of a bool.
// =============================================================================

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/thread.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <atomic>
#include <mutex>
#include <unordered_map>
#include <vector>

#include "opcua_node_id.h"

extern "C" {
#include "open62541.h"
}

namespace godot {

// ── Internal subscription bookkeeping (not exposed to GDScript) ───────────────

/// Per-item state inside a live subscription.
struct MonitoredItemEntry {
    UA_UInt32        mon_id      = 0;        ///< Server-assigned monitored-item ID
    String          *tag_ctx     = nullptr;   ///< Heap String owned here; freed on removal
    Ref<OpcUaNodeId> node_id;               ///< Kept for subscription replay after reconnect
    float            sampling_ms = 250.0f;
    float            deadband    = 0.0f;     ///< 0 = disabled
};

/// State for one OPC UA Subscription (one handle → one SubscriptionEntry).
struct SubscriptionEntry {
    UA_UInt32                       sub_id      = 0;
    float                           interval_ms = 1000.0f;
    std::vector<MonitoredItemEntry> items;
};

// =============================================================================
// GodotOpcUa
// =============================================================================
class GodotOpcUa : public RefCounted {
    GDCLASS(GodotOpcUa, RefCounted)

private:
    // ── Authentication mode ───────────────────────────────────────────────────
    enum class AuthMode { Anonymous, Username };
    AuthMode _auth_mode = AuthMode::Anonymous;
    String   _auth_username;
    String   _auth_password;

    // ── OPC UA client ─────────────────────────────────────────────────────────
    UA_Client *_client   = nullptr;
    String     _last_url;
    /// True while the OPC UA session is activated.
    /// Written by the poll thread and by disconnect_server() on the main thread
    /// (polling is always stopped before disconnect_server touches it, so there
    /// is no concurrent write).  std::atomic gives the main thread a tear-free
    /// read via is_server_connected() without any lock.
    std::atomic<bool> _connected{false};

    /// Set to true by the poll thread when max reconnect attempts is exhausted.
    /// Read and atomically cleared by has_connection_failed() on the main thread.
    std::atomic<bool> _connection_failed_flag{false};

    // ── Mutex — ALL UA_Client_* calls must hold this ──────────────────────────
    std::mutex _ua_mutex;

    // ── Subscriptions (guarded by _ua_mutex) ──────────────────────────────────
    std::unordered_map<int, SubscriptionEntry> _subscriptions;
    int _next_sub_handle = 1;

    // ── Value cache (guarded by _values_mutex) ────────────────────────────────
    // Values are entry Dictionaries: {value, timestamp_ms, quality, quality_good, tick}
    Dictionary _latest_values;
    std::mutex _values_mutex;

    // ── Background polling ────────────────────────────────────────────────────
    Ref<Thread>       _poll_thread;
    std::atomic<bool> _polling{false};
    float             _poll_interval_sec      = 0.1f;
    float             _reconnect_base_sec     = 5.0f;   ///< Base reconnect interval (doubles each attempt)
    int               _reconnect_attempt      = 0;
    int               _max_reconnect_attempts = -1;      ///< -1 = unlimited

    static constexpr float RECONNECT_MAX_INTERVAL_SEC = 60.0f;

    // ── Browse ────────────────────────────────────────────────────────────────
    int _max_browse_depth = 5;

    // =========================================================================
    // Private helpers
    // =========================================================================

    // ── Type conversion ───────────────────────────────────────────────────────
    Variant    _ua_variant_to_godot(const UA_Variant &ua_var) const;
    bool       _godot_to_ua_variant(const Variant &gd_var, UA_Variant &out) const;

    /// Build a tag-cache entry Dictionary from a UA_DataValue.
    Dictionary _make_tag_entry(const UA_DataValue &dv) const;

    // ── Node ID helpers ───────────────────────────────────────────────────────
    static String      _node_id_to_string(const UA_NodeId &id);
    static const char *_node_class_to_string(UA_NodeClass nc);

    // ── Connection helpers ────────────────────────────────────────────────────

    /// Issue UA_Client_connect or UA_Client_connect_username depending on _auth_mode.
    /// Must be called with _ua_mutex held (or from a context where no other thread
    /// touches _client).
    UA_StatusCode _do_connect(UA_Client *client, const String &url);

    /// Delete _client and allocate a fresh one with default config.
    /// Resets server-side subscription IDs but preserves item config for replay.
    /// Must be called with _ua_mutex held.
    bool _rebuild_client_locked();

    // ── Subscription helpers (all require _ua_mutex held) ─────────────────────

    /// Create OPC UA Subscription + MonitoredItems for one SubscriptionEntry.
    bool _create_subscription_entry_locked(SubscriptionEntry &entry);

    /// Add one MonitoredItem to an existing live subscription entry.
    bool _add_monitored_item_locked(SubscriptionEntry &entry,
                                    Ref<OpcUaNodeId>   node_id,
                                    float              sampling_ms,
                                    float              deadband);

    /// Remove a MonitoredItem from an entry by tag name; frees its tag_ctx.
    void _remove_monitored_item_by_tag_locked(SubscriptionEntry &entry,
                                              const String      &tag_name);

    /// Tell the server to delete entry's subscription and free all tag_ctx strings.
    void _delete_subscription_entry_locked(SubscriptionEntry &entry);

    /// Delete every subscription; clears _subscriptions map.
    void _delete_all_subscriptions_locked();

    /// Re-create all subscriptions after a reconnect (server-side IDs are gone).
    void _replay_subscriptions_locked();

    // ── Browse helpers (require _ua_mutex held) ───────────────────────────────

    /// Execute one browse request with full continuation-point loop.
    /// Appends results to out_refs; caller owns memory via UA_BrowseResult.
    /// Returns false on service error.
    bool _browse_with_continuation_locked(const UA_NodeId &nodeId,
                                          Array           &out_children,
                                          int              depth);

    /// Process one UA_BrowseResult's references into out_children Dicts,
    /// recursing if depth < _max_browse_depth.
    void _process_browse_result_locked(Array                &out_children,
                                       const UA_BrowseResult &result,
                                       int                    depth);

    // ── Poll thread ───────────────────────────────────────────────────────────
    void _poll_thread_func();

    static void _on_data_change(UA_Client  *client,
                                UA_UInt32   subId,  void *subContext,
                                UA_UInt32   monId,  void *monContext,
                                UA_DataValue *value);

protected:
    static void _bind_methods();

public:
    GodotOpcUa();
    ~GodotOpcUa() override;

    // ── Connection ────────────────────────────────────────────────────────────

    /// Connect anonymously.
    bool connect_to_server(String url);

    /// Connect with OPC UA username/password authentication.
    bool connect_with_credentials(String url, String username, String password);

    /// Stop polling, delete all subscriptions, disconnect, and free the client.
    void disconnect_server();

    // ── Synchronous read / write (main thread) ────────────────────────────────

    /// Single-node read.  Returns the value Variant (NIL on error).
    Variant read_node(Ref<OpcUaNodeId> node_id);

    /// Batch read.  Returns Dictionary: tag_name → entry Dictionary.
    Dictionary read_nodes(Array node_ids);

    /// Single-node write.
    bool write_node(Ref<OpcUaNodeId> node_id, const Variant &value);

    /// Invoke an OPC UA Method node.
    /// Returns {"success":bool, "output_args":Array, "error":String}.
    Dictionary call_ua_method(Ref<OpcUaNodeId> object_id,
                              Ref<OpcUaNodeId> method_id,
                              Array            input_args);

    // ── Subscription management ───────────────────────────────────────────────

    /// Create a subscription for a list of nodes.
    ///
    /// node_specs is an Array of Dictionaries, each with:
    ///   "node_id"     : OpcUaNodeId (required)
    ///   "sampling_ms" : float       (optional, default 250)
    ///   "deadband"    : float       (optional, default 0 = disabled)
    ///
    /// Returns a subscription handle (>0) on success, or -1 on failure.
    /// The handle is used by delete_subscription / add_monitored_item / remove_monitored_item.
    int create_subscription(Array node_specs, float interval_ms);

    /// Delete one subscription by handle.
    void delete_subscription(int handle);

    /// Delete all active subscriptions.
    void delete_all_subscriptions();

    /// Add a single MonitoredItem to an existing subscription.
    bool add_monitored_item(int              handle,
                            Ref<OpcUaNodeId> node_id,
                            float            sampling_ms,
                            float            deadband);

    /// Remove a MonitoredItem from a subscription by node.
    void remove_monitored_item(int handle, Ref<OpcUaNodeId> node_id);

    // ── Polling & reconnection ────────────────────────────────────────────────

    void start_polling(float interval_sec);
    void stop_polling();

    /// Set base reconnect interval.  Actual wait uses exponential backoff,
    /// doubling each failed attempt up to 60 s.
    void set_reconnect_interval(float seconds);

    /// -1 = unlimited attempts (default).
    void set_max_reconnect_attempts(int attempts);

    // ── Value cache ───────────────────────────────────────────────────────────

    /// Just the value Variant (NIL if not yet received).
    Variant get_tag_value(String tag_name);

    /// Full entry Dictionary: {value, timestamp_ms, quality, quality_good, tick}.
    Dictionary get_tag_entry(String tag_name);

    /// All cached values: tag_name → Variant.
    Dictionary get_all_tag_values();

    /// All cached entries: tag_name → entry Dictionary.
    Dictionary get_all_tag_entries();

    /// Tags updated since since_tick_ms (as returned by Time.get_ticks_msec()).
    /// Returns tag_name → entry Dictionary.
    Dictionary get_changed_tags_since(int64_t since_tick_ms);

    // ── Browsing ──────────────────────────────────────────────────────────────

    /// Recursively browse from OPC UA Root (ns=0, i=84).
    /// Supports continuation points; respects _max_browse_depth.
    Dictionary browse_server();

    /// Browse immediate children of node_id (no recursion).
    Array browse_children(Ref<OpcUaNodeId> node_id);

    // ── Server discovery ──────────────────────────────────────────────────────

    /// Discover OPC UA servers at a Local Discovery Server URL.
    /// Returns Array of {"name":String, "url":String, "product_uri":String}.
    /// Uses a temporary UA_Client; safe to call before connect_to_server.
    Array discover_servers(String discovery_url);

    /// Enumerate endpoints advertised by a server.
    /// Returns Array of {"url":String, "security_mode":String, "security_policy":String}.
    Array get_endpoints(String url);

    // ── State polling (GDScript _process alternative to signals) ─────────────

    /// Returns true if the OPC UA session is currently activated.
    /// Thread-safe: reads an atomic bool — no lock, no Godot API overhead.
    /// Call this from GDScript's _process() to detect connect/disconnect events
    /// instead of relying on the connection_changed signal.
    bool is_server_connected() const;

    /// Returns true (exactly once per failure event) when the poll thread has
    /// exhausted max_reconnect_attempts without success.  Atomically clears the
    /// flag on read so subsequent calls return false until the next failure.
    /// Call this from GDScript's _process().
    bool has_connection_failed();
};

} // namespace godot