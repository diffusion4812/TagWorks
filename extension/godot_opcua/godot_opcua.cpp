// =============================================================================
// godot_opcua.cpp  (v4)
//
// Memory contract
// ───────────────
// • Every UA_NodeId from OpcUaNodeId::to_ua_node_id() is held inside a
//   UA_MonitoredItemCreateRequest and freed by UA_MonitoredItemCreateRequest_clear().
//   No separate UA_NodeId_clear() is called on these.
// • Every UA_Variant, UA_BrowseResponse, UA_BrowseNextResponse, UA_ReadResponse,
//   UA_CreateSubscriptionResponse, UA_MonitoredItemCreateResult is cleared before
//   its owning scope exits.
// • MonitoredItemContext objects are owned by unique_ptr in _item_registry.
//   Their raw address is stable even when the map rehashes, so the pointer
//   passed to open62541 as monitoredItemContext remains valid indefinitely.
//
// Threading contract
// ──────────────────
// Everything runs on the main thread.  iterate() is called from GDScript
// _process(); _on_data_change() fires inside that call.  No mutexes, no
// atomics, no cross-thread Godot API calls.
// =============================================================================

#include "godot_opcua.h"
#include "opcua_node_id.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/time.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

// ============================================================================
// Constructor / Destructor
// ============================================================================

GodotOpcUa::GodotOpcUa() {}

GodotOpcUa::~GodotOpcUa() {
    disconnect_server();
}

// ============================================================================
// ClassDB
// ============================================================================

void GodotOpcUa::_bind_methods() {

    // ── Connection ────────────────────────────────────────────────────────────
    ClassDB::bind_method(D_METHOD("connect_to_server", "url"),
                         &GodotOpcUa::connect_to_server);
    ClassDB::bind_method(D_METHOD("connect_with_credentials",
                                   "url", "username", "password"),
                         &GodotOpcUa::connect_with_credentials);
    ClassDB::bind_method(D_METHOD("disconnect_server"),
                         &GodotOpcUa::disconnect_server);

    // ── Network driver ────────────────────────────────────────────────────────
    ClassDB::bind_method(D_METHOD("iterate", "timeout_ms"),
                         &GodotOpcUa::iterate);
    ClassDB::bind_method(D_METHOD("replay_subscriptions"),
                         &GodotOpcUa::replay_subscriptions);

    // ── Read / write ──────────────────────────────────────────────────────────
    ClassDB::bind_method(D_METHOD("read_node", "node_id"),
                         &GodotOpcUa::read_node);
    ClassDB::bind_method(D_METHOD("read_node_data_type", "node_id"),
                         &GodotOpcUa::read_node_data_type);
    ClassDB::bind_method(D_METHOD("read_nodes", "node_ids"),
                         &GodotOpcUa::read_nodes);
    ClassDB::bind_method(D_METHOD("write_node", "node_id", "value"),
                         &GodotOpcUa::write_node);
    ClassDB::bind_method(D_METHOD("call_ua_method",
                                   "object_id", "method_id", "input_args"),
                         &GodotOpcUa::call_ua_method);

    // ── Subscription ──────────────────────────────────────────────────────────
    ClassDB::bind_method(D_METHOD("create_subscription", "interval_ms"),
                         &GodotOpcUa::create_subscription);
    ClassDB::bind_method(D_METHOD("delete_subscription", "handle"),
                         &GodotOpcUa::delete_subscription);
    ClassDB::bind_method(D_METHOD("subscribe",
                                   "handle", "node_id", "callable",
                                   "sampling_ms", "deadband"),
                         &GodotOpcUa::subscribe);
    ClassDB::bind_method(D_METHOD("unsubscribe", "node_id", "callable"),
                         &GodotOpcUa::unsubscribe);
    ClassDB::bind_method(D_METHOD("clear_subscriptions"),
                         &GodotOpcUa::clear_subscriptions);

    // ── Cache ─────────────────────────────────────────────────────────────────
    ClassDB::bind_method(D_METHOD("get_tag_value", "tag_name"),
                         &GodotOpcUa::get_tag_value);
    ClassDB::bind_method(D_METHOD("get_tag_entry", "tag_name"),
                         &GodotOpcUa::get_tag_entry);
    ClassDB::bind_method(D_METHOD("get_all_tag_entries"),
                         &GodotOpcUa::get_all_tag_entries);
    ClassDB::bind_method(D_METHOD("get_changed_tags_since", "since_tick_ms"),
                         &GodotOpcUa::get_changed_tags_since);

    // ── Browse ────────────────────────────────────────────────────────────────
    ClassDB::bind_method(D_METHOD("browse_server"),
                         &GodotOpcUa::browse_server);
    ClassDB::bind_method(D_METHOD("browse_children", "node_id"),
                         &GodotOpcUa::browse_children);

    // ── Discovery ─────────────────────────────────────────────────────────────
    ClassDB::bind_method(D_METHOD("discover_servers", "discovery_url"),
                         &GodotOpcUa::discover_servers);
    ClassDB::bind_method(D_METHOD("get_endpoints", "url"),
                         &GodotOpcUa::get_endpoints);
}

// ============================================================================
// Type conversion — UA_Variant ↔ Godot Variant
// ============================================================================

Variant GodotOpcUa::_ua_variant_to_godot(const UA_Variant &ua_var) const {
    if (ua_var.type == nullptr || ua_var.data == nullptr)
        return Variant();

    // ── Scalar ───────────────────────────────────────────────────────────────
    if (UA_Variant_isScalar(&ua_var)) {
        if (ua_var.type == &UA_TYPES[UA_TYPES_BOOLEAN])
            return Variant(*static_cast<const UA_Boolean *>(ua_var.data) != UA_FALSE);
        if (ua_var.type == &UA_TYPES[UA_TYPES_INT16])
            return Variant(static_cast<int64_t>(*static_cast<const UA_Int16  *>(ua_var.data)));
        if (ua_var.type == &UA_TYPES[UA_TYPES_UINT16])
            return Variant(static_cast<int64_t>(*static_cast<const UA_UInt16 *>(ua_var.data)));
        if (ua_var.type == &UA_TYPES[UA_TYPES_INT32])
            return Variant(static_cast<int64_t>(*static_cast<const UA_Int32  *>(ua_var.data)));
        if (ua_var.type == &UA_TYPES[UA_TYPES_UINT32])
            return Variant(static_cast<int64_t>(*static_cast<const UA_UInt32 *>(ua_var.data)));
        if (ua_var.type == &UA_TYPES[UA_TYPES_INT64])
            return Variant(*static_cast<const UA_Int64 *>(ua_var.data));
        if (ua_var.type == &UA_TYPES[UA_TYPES_UINT64]) {
            const UA_UInt64 u = *static_cast<const UA_UInt64 *>(ua_var.data);
            if (u > static_cast<UA_UInt64>(INT64_MAX))
                UtilityFunctions::push_warning("GodotOpcUa: UA_UInt64 truncated.");
            return Variant(static_cast<int64_t>(u));
        }
        if (ua_var.type == &UA_TYPES[UA_TYPES_FLOAT])
            return Variant(static_cast<double>(*static_cast<const UA_Float  *>(ua_var.data)));
        if (ua_var.type == &UA_TYPES[UA_TYPES_DOUBLE])
            return Variant(*static_cast<const UA_Double *>(ua_var.data));
        if (ua_var.type == &UA_TYPES[UA_TYPES_STRING]) {
            const UA_String *s = static_cast<const UA_String *>(ua_var.data);
            if (!s->data || s->length == 0) return Variant(String());
            return Variant(String::utf8(reinterpret_cast<const char *>(s->data),
                                        static_cast<int>(s->length)));
        }
        UtilityFunctions::push_warning(
            String("GodotOpcUa: Unsupported scalar UA type: ") +
            String(ua_var.type->typeName));
        return Variant();
    }

    // ── 1-D array → Godot Array ──────────────────────────────────────────────
    Array out;
    out.resize(static_cast<int>(ua_var.arrayLength));
    for (size_t i = 0; i < ua_var.arrayLength; ++i) {
        // Borrow a pointer into the existing buffer — no allocation.
        UA_Variant elem;
        UA_Variant_init(&elem);
        elem.type = ua_var.type;
        elem.data = static_cast<UA_Byte *>(ua_var.data) + i * ua_var.type->memSize;
        out[static_cast<int>(i)] = _ua_variant_to_godot(elem);
        // Do NOT UA_Variant_clear(&elem) — we don't own the data pointer.
    }
    return Variant(out);
}

bool GodotOpcUa::_godot_to_ua_variant(const Variant &gd_var, UA_Variant &out) const {
    UA_Variant_init(&out);

    auto scalar_copy = [&](const void *val, const UA_DataType *type) -> bool {
        const UA_StatusCode sc = UA_Variant_setScalarCopy(&out, val, type);
        if (sc != UA_STATUSCODE_GOOD) {
            UtilityFunctions::push_error(
                String("GodotOpcUa: UA_Variant_setScalarCopy failed: ") +
                String(UA_StatusCode_name(sc)));
            UA_Variant_clear(&out);
            return false;
        }
        return true;
    };

    switch (gd_var.get_type()) {
        case Variant::BOOL: {
            const UA_Boolean v = static_cast<bool>(gd_var) ? UA_TRUE : UA_FALSE;
            return scalar_copy(&v, &UA_TYPES[UA_TYPES_BOOLEAN]);
        }
        case Variant::INT: {
            const UA_Int64 v = static_cast<int64_t>(gd_var);
            return scalar_copy(&v, &UA_TYPES[UA_TYPES_INT64]);
        }
        case Variant::FLOAT: {
            const UA_Double v = static_cast<double>(gd_var);
            return scalar_copy(&v, &UA_TYPES[UA_TYPES_DOUBLE]);
        }
        case Variant::STRING: {
            const CharString utf8 = static_cast<String>(gd_var).utf8();
            UA_String s;
            UA_String_init(&s);
            s.length = static_cast<size_t>(utf8.length());
            s.data   = reinterpret_cast<UA_Byte *>(const_cast<char *>(utf8.get_data()));
            return scalar_copy(&s, &UA_TYPES[UA_TYPES_STRING]);
        }
        default:
            UtilityFunctions::push_warning(
                String("GodotOpcUa: Cannot convert Variant type '") +
                Variant::get_type_name(gd_var.get_type()) + "'.");
            return false;
    }
}

// ============================================================================
// _make_tag_entry
// ============================================================================

Dictionary GodotOpcUa::_make_tag_entry(const UA_DataValue &dv) const {
    Dictionary entry;
    entry["value"]        = dv.hasValue ? _ua_variant_to_godot(dv.value) : Variant();
    entry["quality"]      = static_cast<int64_t>(dv.status);
    entry["quality_good"] = static_cast<bool>(UA_StatusCode_isGood(dv.status));

    // UA_DateTime: 100-ns ticks since 1601-01-01 → subtract 1601→1970 offset → ms.
    static const int64_t UA_EPOCH_OFFSET_100NS = 116444736000000000LL;
    int64_t ts_ms = 0;
    if (dv.hasSourceTimestamp && dv.sourceTimestamp > UA_EPOCH_OFFSET_100NS)
        ts_ms = (static_cast<int64_t>(dv.sourceTimestamp) - UA_EPOCH_OFFSET_100NS) / 10000LL;
    entry["timestamp_ms"] = ts_ms;
    entry["tick"]         = static_cast<int64_t>(Time::get_singleton()->get_ticks_msec());
    return entry;
}

// ============================================================================
// _map_ua_status_to_error
// ============================================================================

Error GodotOpcUa::_map_ua_status_to_error(UA_StatusCode rs) {
    if (rs == UA_STATUSCODE_GOOD) {
        return OK;
    }

    switch (rs) {
        case UA_STATUSCODE_BADCONNECTIONCLOSED:
        case UA_STATUSCODE_BADCONNECTIONREJECTED:
        case UA_STATUSCODE_BADSECURECHANNELCLOSED:
            return ERR_CONNECTION_ERROR;
        case UA_STATUSCODE_BADTIMEOUT:
            return ERR_TIMEOUT;
        case UA_STATUSCODE_BADOUTOFMEMORY:
            return ERR_OUT_OF_MEMORY;
        case UA_STATUSCODE_BADNOTCONNECTED:
            return ERR_DOES_NOT_EXIST;
        case UA_STATUSCODE_BADUSERACCESSDENIED:
        case UA_STATUSCODE_BADIDENTITYTOKENINVALID:
        case UA_STATUSCODE_BADIDENTITYTOKENREJECTED:
            return ERR_UNAUTHORIZED;
        case UA_STATUSCODE_BADINVALIDARGUMENT:
            return ERR_INVALID_PARAMETER;
        default:
            if (UA_StatusCode_isBad(rs)) {
                UtilityFunctions::push_error(
                    String("GodotOpcUa: Unmapped bad status: ") +
                    String(UA_StatusCode_name(rs)));
                return ERR_QUERY_FAILED;
            }
            return OK; // Uncertain codes treated as non-fatal
    }
}

// ============================================================================
// _ua_builtin_type_name
// ============================================================================

String GodotOpcUa::_ua_builtin_type_name(UA_UInt32 numeric_id) const {
    switch (numeric_id) {
        case UA_NS0ID_BOOLEAN: return "Boolean";
        case UA_NS0ID_SBYTE:   return "SByte";
        case UA_NS0ID_BYTE:    return "Byte";
        case UA_NS0ID_INT16:   return "Int16";
        case UA_NS0ID_UINT16:  return "UInt16";
        case UA_NS0ID_INT32:   return "Int32";
        case UA_NS0ID_UINT32:  return "UInt32";
        case UA_NS0ID_INT64:   return "Int64";
        case UA_NS0ID_UINT64:  return "UInt64";
        case UA_NS0ID_FLOAT:   return "Float";
        case UA_NS0ID_DOUBLE:  return "Double";
        case UA_NS0ID_STRING:  return "String";
        default:               return "Unsupported";
    }
}

// ============================================================================
// Static helpers
// ============================================================================

String GodotOpcUa::_node_id_to_string(const UA_NodeId &id) {
    return OpcUaNodeId::from_ua_node_id(id)->to_tag_name();
}

const char *GodotOpcUa::_node_class_to_string(UA_NodeClass nc) {
    switch (nc) {
        case UA_NODECLASS_OBJECT:        return "Object";
        case UA_NODECLASS_VARIABLE:      return "Variable";
        case UA_NODECLASS_METHOD:        return "Method";
        case UA_NODECLASS_OBJECTTYPE:    return "ObjectType";
        case UA_NODECLASS_VARIABLETYPE:  return "VariableType";
        case UA_NODECLASS_REFERENCETYPE: return "ReferenceType";
        case UA_NODECLASS_DATATYPE:      return "DataType";
        case UA_NODECLASS_VIEW:          return "View";
        default:                         return "Unknown";
    }
}

// ============================================================================
// _do_connect
// ============================================================================

UA_StatusCode GodotOpcUa::_do_connect(UA_Client *client, const String &url) {
    const CharString u = url.utf8();
    if (_auth_mode == AuthMode::Username) {
        const CharString user = _auth_username.utf8();
        const CharString pass = _auth_password.utf8();
        return UA_Client_connectUsername(client, u.get_data(),
                                          user.get_data(), pass.get_data());
    }
    return UA_Client_connect(client, u.get_data());
}

// ============================================================================
// _init_client
// ============================================================================

bool GodotOpcUa::_init_client() {
    if (_client != nullptr) {
        UA_Client_delete(_client);
        _client = nullptr;
    }
    _client = UA_Client_new();
    if (_client == nullptr) {
        UtilityFunctions::push_error("GodotOpcUa: UA_Client_new() returned null.");
        return false;
    }
    const UA_StatusCode sc = UA_ClientConfig_setDefault(UA_Client_getConfig(_client));
    if (sc != UA_STATUSCODE_GOOD) {
        UtilityFunctions::push_error(
            String("GodotOpcUa: UA_ClientConfig_setDefault() failed: ") +
            String(UA_StatusCode_name(sc)));
        UA_Client_delete(_client);
        _client = nullptr;
        return false;
    }
    return true;
}

// ============================================================================
// _create_subscription_server_side
// ============================================================================

bool GodotOpcUa::_create_subscription_server_side(int              handle,
                                                    SubscriptionEntry &entry) {
    if (_client == nullptr) return false;

    UA_CreateSubscriptionRequest req = UA_CreateSubscriptionRequest_default();
    req.requestedPublishingInterval = static_cast<UA_Double>(entry.interval_ms);
    req.requestedLifetimeCount      = 300;
    req.requestedMaxKeepAliveCount  = 10;
    req.publishingEnabled           = UA_TRUE;

    // Pass 'this' as subscriptionContext so _on_data_change can reach the
    // GodotOpcUa instance through the subContext pointer.
    UA_CreateSubscriptionResponse resp =
        UA_Client_Subscriptions_create(_client, req, this, nullptr, nullptr);

    if (resp.responseHeader.serviceResult != UA_STATUSCODE_GOOD) {
        UtilityFunctions::push_error(
            String("GodotOpcUa: create subscription failed: ") +
            String(UA_StatusCode_name(resp.responseHeader.serviceResult)));
        UA_CreateSubscriptionResponse_clear(&resp);
        return false;
    }

    entry.sub_id = resp.subscriptionId;
    UA_CreateSubscriptionResponse_clear(&resp);
    return true;
}

// ============================================================================
// _create_monitored_item
// ============================================================================

void GodotOpcUa::_create_monitored_item(MonitoredItemContext &ctx,
                                          UA_UInt32             sub_id) {
    if (_client == nullptr) return;

    // Build directly into mon_req so it is the sole owner of the nodeId bytes.
    // Do NOT create a separate UA_NodeId variable — that causes a double-free
    // for string node IDs when both the local var and mon_req are cleared.
    UA_MonitoredItemCreateRequest mon_req;
    UA_MonitoredItemCreateRequest_init(&mon_req);
    mon_req.itemToMonitor.nodeId      = ctx.node_id->to_ua_node_id(); // sole owner
    mon_req.itemToMonitor.attributeId = UA_ATTRIBUTEID_VALUE;
    mon_req.monitoringMode            = UA_MONITORINGMODE_REPORTING;
    mon_req.requestedParameters.samplingInterval =
        static_cast<UA_Double>(ctx.sampling_ms);
    mon_req.requestedParameters.discardOldest = UA_TRUE;
    mon_req.requestedParameters.queueSize     = 1;

    if (ctx.deadband > 0.0f) {
        // Heap-allocate so UA_MonitoredItemCreateRequest_clear() frees it correctly.
        UA_DataChangeFilter *filt = static_cast<UA_DataChangeFilter *>(
            UA_new(&UA_TYPES[UA_TYPES_DATACHANGEFILTER]));
        UA_DataChangeFilter_init(filt);
        filt->trigger       = UA_DATACHANGETRIGGER_STATUSVALUE;
        filt->deadbandType  = UA_DEADBANDTYPE_ABSOLUTE;
        filt->deadbandValue = static_cast<UA_Double>(ctx.deadband);
        mon_req.requestedParameters.filter.encoding =
            UA_EXTENSIONOBJECT_DECODED;
        mon_req.requestedParameters.filter.content.decoded.type =
            &UA_TYPES[UA_TYPES_DATACHANGEFILTER];
        mon_req.requestedParameters.filter.content.decoded.data = filt;
    }

    // Pass &ctx as monitoredItemContext.  The unique_ptr in _item_registry
    // keeps this address stable for the lifetime of the subscription.
    UA_MonitoredItemCreateResult result =
        UA_Client_MonitoredItems_createDataChange(
            _client, sub_id,
            UA_TIMESTAMPSTORETURN_BOTH,
            mon_req,
            &ctx,
            &GodotOpcUa::_on_data_change,
            nullptr);

    // Clears nodeId bytes (string type) and the deadband filter — exactly once.
    UA_MonitoredItemCreateRequest_clear(&mon_req);

    if (result.statusCode == UA_STATUSCODE_GOOD) {
        ctx.mon_id = result.monitoredItemId;
    } else {
        ctx.mon_id = 0;
        UtilityFunctions::push_warning(
            String("GodotOpcUa: MonitoredItem create failed for ") +
            ctx.tag_name + ": " +
            String(UA_StatusCode_name(result.statusCode)));
    }
    UA_MonitoredItemCreateResult_clear(&result);
}

// ============================================================================
// _on_data_change  (static — fires on main thread inside iterate())
// ============================================================================

void GodotOpcUa::_on_data_change(UA_Client    * /*client*/,
                                   UA_UInt32    /*subId*/, void *subContext,
                                   UA_UInt32    /*monId*/, void *monContext,
                                   UA_DataValue *value) {
    if (!subContext || !monContext || !value) return;

    GodotOpcUa          *self = static_cast<GodotOpcUa *>(subContext);
    MonitoredItemContext *ctx  = static_cast<MonitoredItemContext *>(monContext);

    // Build the entry dictionary once; reuse for all callbacks and the cache.
    const Dictionary entry = self->_make_tag_entry(*value);

    // Update value cache.
    self->_latest_values[ctx->tag_name] = entry;

    // Fan out to all registered Callables.
    // Prune stale (freed-object) callables in the same pass so the list
    // self-heals without requiring explicit unsubscribe calls.
    auto &cbs   = ctx->callbacks;
    size_t write = 0;
    for (size_t i = 0; i < cbs.size(); ++i) {
        if (cbs[i].is_valid()) {
            cbs[i].call(entry);
            if (write != i) cbs[write] = cbs[i];
            ++write;
        }
        // Invalid callable: skip and do not copy forward (effectively erased).
    }
    if (write < cbs.size())
        cbs.resize(write);
}

// ============================================================================
// connect_to_server / connect_with_credentials
// ============================================================================

Error GodotOpcUa::connect_to_server(String url) {
    _auth_mode = AuthMode::Anonymous;
    return connect_with_credentials(url, String(), String());
}

Error GodotOpcUa::connect_with_credentials(String url,
                                             String username,
                                             String password) {
    if (_client != nullptr) {
        UtilityFunctions::push_warning(
            "GodotOpcUa: Already connected. Call disconnect_server() first.");
        return ERR_ALREADY_IN_USE;
    }

    if (url.is_empty()) {
        UtilityFunctions::push_error("GodotOpcUa: Connect failed, URL is empty.");
        return ERR_INVALID_PARAMETER;
    }

    if (!username.is_empty()) {
        _auth_mode     = AuthMode::Username;
        _auth_username = username;
        _auth_password = password;
    } else {
        _auth_mode = AuthMode::Anonymous;
    }

    if (!_init_client()) {
        UtilityFunctions::push_error("GodotOpcUa: Client initialization failed.");
        return ERR_CANT_CREATE;
    }

    const UA_StatusCode sc = _do_connect(_client, url);
    const Error err = _map_ua_status_to_error(sc);

    if (err != OK) {
        UtilityFunctions::push_error(
            String("GodotOpcUa: Connect to \"") + url + "\" failed: " +
            String(UA_StatusCode_name(sc)));
        UA_Client_delete(_client);
        _client = nullptr;
        return err;
    }

    _last_url = url;
    return OK;
}

// ============================================================================
// disconnect_server
// ============================================================================

void GodotOpcUa::disconnect_server() {
    if (_client == nullptr) return;

    // Best-effort server-side cleanup; errors ignored (connection may be gone).
    for (auto &[handle, entry] : _subscriptions) {
        if (entry.sub_id != 0)
            UA_Client_Subscriptions_deleteSingle(_client, entry.sub_id);
        entry.sub_id = 0;
    }

    // Reset all server-side item IDs; preserve contexts and Callables for replay.
    for (auto &[key, ctx] : _item_registry)
        ctx->mon_id = 0;

    UA_Client_disconnect(_client);
    UA_Client_delete(_client);
    _client = nullptr;

    _latest_values.clear();
}

// ============================================================================
// iterate
// ============================================================================

Error GodotOpcUa::iterate(int timeout_ms) {
    if (_client == nullptr) {
        return ERR_UNCONFIGURED;
    }

    // Negative values are clamped to 0 (non-blocking iterate).
    UA_UInt32 timeout = static_cast<UA_UInt32>(timeout_ms < 0 ? 0 : timeout_ms);
    UA_StatusCode rs = UA_Client_run_iterate(_client, timeout);

    return _map_ua_status_to_error(rs);
}

// ============================================================================
// replay_subscriptions
// ============================================================================

void GodotOpcUa::replay_subscriptions() {
    if (_client == nullptr) return;

    // (Re-)create every subscription on the server, obtaining new sub_ids.
    for (auto &[handle, entry] : _subscriptions)
        _create_subscription_server_side(handle, entry);

    // (Re-)create every monitored item under its subscription.
    for (auto &[key, ctx] : _item_registry) {
        auto it = _subscriptions.find(ctx->sub_handle);
        if (it == _subscriptions.end() || it->second.sub_id == 0) continue;
        _create_monitored_item(*ctx, it->second.sub_id);
    }
}

// ============================================================================
// create_subscription / delete_subscription
// ============================================================================

int GodotOpcUa::create_subscription(float interval_ms) {
    const int handle = _next_sub_handle++;
    SubscriptionEntry &entry = _subscriptions[handle];
    entry.interval_ms = interval_ms;
    entry.sub_id      = 0;

    // Create server-side immediately if we are already connected.
    if (_client != nullptr)
        _create_subscription_server_side(handle, entry);

    return handle;
}

void GodotOpcUa::delete_subscription(int handle) {
    auto it = _subscriptions.find(handle);
    if (it == _subscriptions.end()) return;

    if (_client != nullptr && it->second.sub_id != 0)
        UA_Client_Subscriptions_deleteSingle(_client, it->second.sub_id);

    // Remove all monitored items that belonged to this subscription.
    for (auto item_it = _item_registry.begin();
             item_it != _item_registry.end(); ) {
        if (item_it->second->sub_handle == handle) {
            item_it = _item_registry.erase(item_it);
        } else {
            ++item_it;
        }
    }

    _subscriptions.erase(it);
}

// ============================================================================
// subscribe
// ============================================================================

bool GodotOpcUa::subscribe(int              handle,
                             Ref<OpcUaNodeId> node_id,
                             Callable         callable,
                             float            sampling_ms,
                             float            deadband) {
    if (node_id.is_null()) {
        UtilityFunctions::push_error("GodotOpcUa: subscribe() called with null node_id.");
        return false;
    }

    auto sub_it = _subscriptions.find(handle);
    if (sub_it == _subscriptions.end()) {
        UtilityFunctions::push_error(
            String("GodotOpcUa: Unknown subscription handle ") +
            String::num_int64(handle));
        return false;
    }

    const String      tag_name = node_id->to_tag_name();
    const std::string key      = tag_name.utf8().get_data();

    auto ctx_it = _item_registry.find(key);

    if (ctx_it != _item_registry.end()) {
        // Context already exists for this tag — just append the callable.
        auto &cbs = ctx_it->second->callbacks;
        for (const Callable &cb : cbs) {
            if (cb == callable) {
                UtilityFunctions::push_warning(
                    String("GodotOpcUa: Callable already registered for ") +
                    tag_name);
                return true; // Idempotent — not an error.
            }
        }
        cbs.push_back(callable);
        return true;
    }

    // First subscriber for this tag — create a new context.
    auto ctx = std::make_unique<MonitoredItemContext>();
    ctx->tag_name    = tag_name;
    ctx->node_id     = node_id;
    ctx->sampling_ms = sampling_ms;
    ctx->deadband    = deadband;
    ctx->sub_handle  = handle;
    ctx->mon_id      = 0;
    ctx->callbacks.push_back(callable);

    // If connected and the subscription is live, create the MonitoredItem now.
    if (_client != nullptr && sub_it->second.sub_id != 0)
        _create_monitored_item(*ctx, sub_it->second.sub_id);

    // Store after creation so the pointer passed to open62541 (&ctx) remains
    // valid: unique_ptr moves into the map without moving the pointed-to object.
    _item_registry[key] = std::move(ctx);
    return true;
}

// ============================================================================
// unsubscribe
// ============================================================================

void GodotOpcUa::unsubscribe(Ref<OpcUaNodeId> node_id, Callable callable) {
    if (node_id.is_null()) return;

    const std::string key = node_id->to_tag_name().utf8().get_data();
    auto it = _item_registry.find(key);
    if (it == _item_registry.end()) return;

    auto &cbs = it->second->callbacks;
    cbs.erase(std::remove_if(cbs.begin(), cbs.end(),
        [&callable](const Callable &cb) { return cb == callable; }),
        cbs.end());

    // No subscribers left — remove the MonitoredItem from the server and
    // erase the context entirely.
    if (cbs.empty()) {
        MonitoredItemContext &ctx = *it->second;
        if (_client != nullptr && ctx.mon_id != 0) {
            auto sub_it = _subscriptions.find(ctx.sub_handle);
            if (sub_it != _subscriptions.end() && sub_it->second.sub_id != 0)
                UA_Client_MonitoredItems_deleteSingle(
                    _client, sub_it->second.sub_id, ctx.mon_id);
        }
        _item_registry.erase(it);
    }
}

// ============================================================================
// clear_subscriptions
// ============================================================================

void GodotOpcUa::clear_subscriptions() {
    if (_client != nullptr) {
        for (auto &[handle, entry] : _subscriptions)
            if (entry.sub_id != 0)
                UA_Client_Subscriptions_deleteSingle(_client, entry.sub_id);
    }
    _subscriptions.clear();
    _item_registry.clear();
    _next_sub_handle = 1;
}

// ============================================================================
// read_node
// ============================================================================

Variant GodotOpcUa::read_node(Ref<OpcUaNodeId> node_id) {
    if (node_id.is_null() || _client == nullptr) return Variant();

    UA_NodeId nid = node_id->to_ua_node_id();
    UA_Variant ua_val;
    UA_Variant_init(&ua_val);

    const UA_StatusCode sc =
        UA_Client_readValueAttribute(_client, nid, &ua_val);
    UA_NodeId_clear(&nid);

    if (sc != UA_STATUSCODE_GOOD) {
        UtilityFunctions::push_error(
            String("GodotOpcUa: Read ") + node_id->to_tag_name() +
            " → " + String(UA_StatusCode_name(sc)));
        UA_Variant_clear(&ua_val);
        return Variant();
    }

    const Variant result = _ua_variant_to_godot(ua_val);
    UA_Variant_clear(&ua_val);
    return result;
}

Dictionary GodotOpcUa::read_node_data_type(const String &node_id_string) {
    Dictionary out;
    out["data_type"]      = -1;
    out["data_type_name"] = String();
    out["success"]        = false;

    if (_client == nullptr) {
        UtilityFunctions::push_error("GodotOpcUa: read_node_data_type called with no active client.");
        return out;
    }

    Ref<OpcUaNodeId> parsed_id = OpcUaNodeId::parse(node_id_string);
    if (parsed_id.is_null()) {
        UtilityFunctions::push_error(
            String("GodotOpcUa: Failed to parse NodeId string: ") + node_id_string);
        return out;
    }

    UA_NodeId nid = parsed_id->to_ua_node_id();

    UA_NodeId data_type_id;
    UA_NodeId_init(&data_type_id);

    const UA_StatusCode sc = UA_Client_readDataTypeAttribute(_client, nid, &data_type_id);
    UA_NodeId_clear(&nid);

    if (sc != UA_STATUSCODE_GOOD) {
        UtilityFunctions::push_error(
            String("GodotOpcUa: readDataTypeAttribute failed for ") + node_id_string +
            " → " + String(UA_StatusCode_name(sc)));
        UA_NodeId_clear(&data_type_id);
        return out;
    }

    if (data_type_id.namespaceIndex == 0 &&
        data_type_id.identifierType == UA_NODEIDTYPE_NUMERIC) {
        out["data_type"]      = static_cast<int64_t>(data_type_id.identifier.numeric);
        out["data_type_name"] = _ua_builtin_type_name(data_type_id.identifier.numeric);
        out["success"]        = true;
    } else {
        // Complex/custom (ns>0) DataType — not a simple scalar we support.
        out["data_type_name"] = String("Unsupported");
        out["success"]        = true;  // read succeeded, just not a scalar builtin
    }

    UA_NodeId_clear(&data_type_id);
    return out;
}

// ============================================================================
// read_nodes  (batch)
// ============================================================================

Dictionary GodotOpcUa::read_nodes(Array node_ids) {
    Dictionary results;
    if (node_ids.size() == 0 || _client == nullptr) return results;

    const size_t count = static_cast<size_t>(node_ids.size());

    UA_ReadRequest req;
    UA_ReadRequest_init(&req);
    req.timestampsToReturn = UA_TIMESTAMPSTORETURN_BOTH;
    req.nodesToRead = static_cast<UA_ReadValueId *>(
        UA_Array_new(count, &UA_TYPES[UA_TYPES_READVALUEID]));
    req.nodesToReadSize = count;

    std::vector<String>    tag_names(count);
    std::vector<UA_NodeId> nids(count);

    for (size_t i = 0; i < count; ++i) {
        Ref<OpcUaNodeId> n = node_ids[static_cast<int>(i)];
        if (n.is_null()) {
            req.nodesToRead[i].nodeId    = UA_NODEID_NUMERIC(0, 0);
            req.nodesToRead[i].attributeId = UA_ATTRIBUTEID_VALUE;
            continue;
        }
        tag_names[i]                   = n->to_tag_name();
        nids[i]                        = n->to_ua_node_id();
        req.nodesToRead[i].nodeId      = nids[i];
        req.nodesToRead[i].attributeId = UA_ATTRIBUTEID_VALUE;
    }

    UA_ReadResponse resp = UA_Client_Service_read(_client, req);

    // Zero out the aliased nodeId pointers before clearing the request so
    // UA_ReadRequest_clear does not attempt to free memory it does not own.
    for (size_t i = 0; i < count; ++i)
        UA_NodeId_init(&req.nodesToRead[i].nodeId);
    UA_ReadRequest_clear(&req);

    for (size_t i = 0; i < count; ++i)
        UA_NodeId_clear(&nids[i]);

    if (resp.responseHeader.serviceResult == UA_STATUSCODE_GOOD) {
        for (size_t i = 0; i < resp.resultsSize && i < count; ++i) {
            if (!tag_names[i].is_empty())
                results[tag_names[i]] = _make_tag_entry(resp.results[i]);
        }
    } else {
        UtilityFunctions::push_error(
            String("GodotOpcUa: read_nodes service failed: ") +
            String(UA_StatusCode_name(resp.responseHeader.serviceResult)));
    }

    UA_ReadResponse_clear(&resp);
    return results;
}

// ============================================================================
// write_node
// ============================================================================

bool GodotOpcUa::write_node(Ref<OpcUaNodeId> node_id, const Variant &value) {
    if (node_id.is_null() || _client == nullptr) return false;

    UA_Variant ua_val;
    if (!_godot_to_ua_variant(value, ua_val)) return false;

    UA_NodeId nid = node_id->to_ua_node_id();
    const UA_StatusCode sc = UA_Client_writeValueAttribute(_client, nid, &ua_val);
    UA_NodeId_clear(&nid);
    UA_Variant_clear(&ua_val);

    if (sc != UA_STATUSCODE_GOOD) {
        UtilityFunctions::push_error(
            String("GodotOpcUa: Write ") + node_id->to_tag_name() +
            " → " + String(UA_StatusCode_name(sc)));
        return false;
    }
    return true;
}

// ============================================================================
// call_ua_method
// ============================================================================

Dictionary GodotOpcUa::call_ua_method(Ref<OpcUaNodeId> object_id,
                                        Ref<OpcUaNodeId> method_id,
                                        Array            input_args) {
    Dictionary result;
    result["success"]     = false;
    result["output_args"] = Array();
    result["error"]       = String();

    if (object_id.is_null() || method_id.is_null()) {
        result["error"] = "Null node ID";
        return result;
    }
    if (_client == nullptr) {
        result["error"] = "Not connected";
        return result;
    }

    const size_t in_count = static_cast<size_t>(input_args.size());
    std::vector<UA_Variant> in_vars(in_count);
    for (size_t i = 0; i < in_count; ++i) {
        UA_Variant_init(&in_vars[i]);
        if (!_godot_to_ua_variant(input_args[static_cast<int>(i)], in_vars[i])) {
            result["error"] = "Failed to convert input arg " + String::num_int64(i);
            for (size_t j = 0; j < i; ++j) UA_Variant_clear(&in_vars[j]);
            return result;
        }
    }

    UA_NodeId obj_nid = object_id->to_ua_node_id();
    UA_NodeId mth_nid = method_id->to_ua_node_id();

    UA_Variant *out_vars  = nullptr;
    size_t      out_count = 0;

    const UA_StatusCode sc = UA_Client_call(
        _client, obj_nid, mth_nid,
        in_count, in_vars.empty() ? nullptr : in_vars.data(),
        &out_count, &out_vars);

    UA_NodeId_clear(&obj_nid);
    UA_NodeId_clear(&mth_nid);
    for (size_t i = 0; i < in_count; ++i) UA_Variant_clear(&in_vars[i]);

    if (sc != UA_STATUSCODE_GOOD) {
        result["error"] = String(UA_StatusCode_name(sc));
        return result;
    }

    Array out_arr;
    for (size_t i = 0; i < out_count; ++i)
        out_arr.push_back(_ua_variant_to_godot(out_vars[i]));

    UA_Array_delete(out_vars, out_count, &UA_TYPES[UA_TYPES_VARIANT]);

    result["success"]     = true;
    result["output_args"] = out_arr;
    return result;
}

// ============================================================================
// Value cache
// ============================================================================

Variant GodotOpcUa::get_tag_value(String tag_name) {
    if (!_latest_values.has(tag_name)) return Variant();
    const Dictionary e = _latest_values[tag_name];
    return e.has("value") ? e["value"] : Variant();
}

Dictionary GodotOpcUa::get_tag_entry(String tag_name) {
    return _latest_values.has(tag_name)
        ? static_cast<Dictionary>(_latest_values[tag_name])
        : Dictionary();
}

Dictionary GodotOpcUa::get_all_tag_entries() {
    return _latest_values.duplicate();
}

Dictionary GodotOpcUa::get_changed_tags_since(int64_t since_tick_ms) {
    Dictionary out;
    Array keys = _latest_values.keys();
    for (int i = 0; i < keys.size(); ++i) {
        const Variant   &k     = keys[i];
        const Dictionary entry = _latest_values[k];
        if (entry.has("tick") &&
                static_cast<int64_t>(entry["tick"]) > since_tick_ms)
            out[k] = entry;
    }
    return out;
}

// ============================================================================
// Browse helpers
// ============================================================================

void GodotOpcUa::_process_browse_result(Array                &out_children,
                                          const UA_BrowseResult &result,
                                          int                    depth) {
    for (size_t i = 0; i < result.referencesSize; ++i) {
        const UA_ReferenceDescription &ref = result.references[i];
        Dictionary entry;

        if (ref.displayName.text.data && ref.displayName.text.length > 0)
            entry["name"] = String::utf8(
                reinterpret_cast<const char *>(ref.displayName.text.data),
                static_cast<int>(ref.displayName.text.length));
        else
            entry["name"] = String("(unnamed)");

        entry["node_id"]    = _node_id_to_string(ref.nodeId.nodeId);
        entry["node_class"] = String(_node_class_to_string(ref.nodeClass));

        if (depth < _max_browse_depth) {
            Array children;
            _browse_with_continuation(ref.nodeId.nodeId, children, depth + 1);
            entry["children"] = children;
        } else {
            entry["children"] = Array();
        }

        out_children.push_back(entry);
    }
}

bool GodotOpcUa::_browse_with_continuation(const UA_NodeId &nodeId,
                                             Array           &out_children,
                                             int              depth) {
    UA_BrowseRequest bReq;
    UA_BrowseRequest_init(&bReq);
    bReq.requestedMaxReferencesPerNode = 0;
    bReq.nodesToBrowse = static_cast<UA_BrowseDescription *>(
        UA_Array_new(1, &UA_TYPES[UA_TYPES_BROWSEDESCRIPTION]));
    bReq.nodesToBrowseSize = 1;
    UA_NodeId_copy(&nodeId, &bReq.nodesToBrowse[0].nodeId);
    bReq.nodesToBrowse[0].resultMask      = UA_BROWSERESULTMASK_ALL;
    bReq.nodesToBrowse[0].browseDirection = UA_BROWSEDIRECTION_FORWARD;
    bReq.nodesToBrowse[0].referenceTypeId =
        UA_NODEID_NUMERIC(0, UA_NS0ID_HIERARCHICALREFERENCES);
    bReq.nodesToBrowse[0].includeSubtypes = UA_TRUE;

    UA_BrowseResponse bResp = UA_Client_Service_browse(_client, bReq);
    UA_BrowseRequest_clear(&bReq);

    if (bResp.responseHeader.serviceResult != UA_STATUSCODE_GOOD ||
            bResp.resultsSize == 0) {
        UA_BrowseResponse_clear(&bResp);
        return false;
    }

    _process_browse_result(out_children, bResp.results[0], depth);

    // Continuation-point loop — handles servers that page browse results.
    UA_ByteString cont;
    UA_ByteString_init(&cont);
    if (bResp.results[0].continuationPoint.length > 0)
        UA_ByteString_copy(&bResp.results[0].continuationPoint, &cont);
    UA_BrowseResponse_clear(&bResp);

    while (cont.length > 0) {
        UA_BrowseNextRequest nextReq;
        UA_BrowseNextRequest_init(&nextReq);
        nextReq.releaseContinuationPoints = UA_FALSE;
        nextReq.continuationPoints        = &cont;
        nextReq.continuationPointsSize    = 1;

        UA_BrowseNextResponse nextResp =
            UA_Client_Service_browseNext(_client, nextReq);

        UA_ByteString next_cont;
        UA_ByteString_init(&next_cont);
        if (nextResp.resultsSize > 0 &&
                nextResp.results[0].continuationPoint.length > 0)
            UA_ByteString_copy(&nextResp.results[0].continuationPoint,
                               &next_cont);

        if (nextResp.resultsSize > 0)
            _process_browse_result(out_children, nextResp.results[0], depth);

        UA_BrowseNextResponse_clear(&nextResp);
        UA_ByteString_clear(&cont);
        cont = next_cont;
    }
    UA_ByteString_clear(&cont);
    return true;
}

// ============================================================================
// browse_server / browse_children
// ============================================================================

Dictionary GodotOpcUa::browse_server() {
    Dictionary root;
    if (_client == nullptr) {
        UtilityFunctions::push_error("GodotOpcUa: browse_server() while disconnected.");
        return root;
    }
    root["name"]       = String("Root");
    root["node_id"]    = String("ns0|i=84");
    root["node_class"] = String("Object");
    const UA_NodeId root_id = UA_NODEID_NUMERIC(0, UA_NS0ID_ROOTFOLDER);
    Array children;
    _browse_with_continuation(root_id, children, 0);
    root["children"] = children;
    return root;
}

Array GodotOpcUa::browse_children(Ref<OpcUaNodeId> node_id) {
    Array result;
    if (node_id.is_null() || _client == nullptr) return result;

    UA_NodeId nid = node_id->to_ua_node_id();
    _browse_with_continuation(nid, result, _max_browse_depth);
    UA_NodeId_clear(&nid);
    
    // Strip the "children" key — this is the flat, lazy variant.
    for (int i = 0; i < result.size(); ++i) {
        Dictionary d = result[i];
        d.erase("children");
        result[i] = d;
    }
    return result;
}

// ============================================================================
// discover_servers / get_endpoints
// ============================================================================

Array GodotOpcUa::discover_servers(String discovery_url) {
    Array servers;
    UA_Client *tmp = UA_Client_new();
    if (!tmp) return servers;
    UA_ClientConfig_setDefault(UA_Client_getConfig(tmp));

    UA_ApplicationDescription *descs = nullptr;
    size_t count = 0;
    const CharString url_utf8 = discovery_url.utf8();

    const UA_StatusCode sc = UA_Client_findServers(
        tmp, url_utf8.get_data(), 0, nullptr, 0, nullptr, &count, &descs);
    UA_Client_delete(tmp);

    if (sc != UA_STATUSCODE_GOOD || !descs) {
        UtilityFunctions::push_warning(
            String("GodotOpcUa: discover_servers failed: ") +
            String(UA_StatusCode_name(sc)));
        return servers;
    }

    for (size_t i = 0; i < count; ++i) {
        const UA_ApplicationDescription &d = descs[i];
        Dictionary entry;
        if (d.applicationName.text.data && d.applicationName.text.length > 0)
            entry["name"] = String::utf8(
                reinterpret_cast<const char *>(d.applicationName.text.data),
                static_cast<int>(d.applicationName.text.length));
        else
            entry["name"] = String();

        if (d.productUri.data && d.productUri.length > 0)
            entry["product_uri"] = String::utf8(
                reinterpret_cast<const char *>(d.productUri.data),
                static_cast<int>(d.productUri.length));
        else
            entry["product_uri"] = String();

        if (d.discoveryUrlsSize > 0 &&
                d.discoveryUrls[0].data && d.discoveryUrls[0].length > 0)
            entry["url"] = String::utf8(
                reinterpret_cast<const char *>(d.discoveryUrls[0].data),
                static_cast<int>(d.discoveryUrls[0].length));
        else
            entry["url"] = String();

        servers.push_back(entry);
    }

    UA_Array_delete(descs, count, &UA_TYPES[UA_TYPES_APPLICATIONDESCRIPTION]);
    return servers;
}

Array GodotOpcUa::get_endpoints(String url) {
    Array endpoints;
    UA_Client *tmp = UA_Client_new();
    if (!tmp) return endpoints;
    UA_ClientConfig_setDefault(UA_Client_getConfig(tmp));

    UA_EndpointDescription *descs = nullptr;
    size_t count = 0;
    const CharString url_utf8 = url.utf8();

    const UA_StatusCode sc =
        UA_Client_getEndpoints(tmp, url_utf8.get_data(), &count, &descs);
    UA_Client_delete(tmp);

    if (sc != UA_STATUSCODE_GOOD || !descs) {
        UtilityFunctions::push_warning(
            String("GodotOpcUa: get_endpoints failed: ") +
            String(UA_StatusCode_name(sc)));
        return endpoints;
    }

    auto security_mode_str = [](UA_MessageSecurityMode m) -> const char * {
        switch (m) {
            case UA_MESSAGESECURITYMODE_NONE:           return "None";
            case UA_MESSAGESECURITYMODE_SIGN:           return "Sign";
            case UA_MESSAGESECURITYMODE_SIGNANDENCRYPT: return "SignAndEncrypt";
            default:                                    return "Invalid";
        }
    };

    for (size_t i = 0; i < count; ++i) {
        const UA_EndpointDescription &ep = descs[i];
        Dictionary entry;

        if (ep.endpointUrl.data && ep.endpointUrl.length > 0)
            entry["url"] = String::utf8(
                reinterpret_cast<const char *>(ep.endpointUrl.data),
                static_cast<int>(ep.endpointUrl.length));
        else
            entry["url"] = String();

        entry["security_mode"] = String(security_mode_str(ep.securityMode));

        if (ep.securityPolicyUri.data && ep.securityPolicyUri.length > 0)
            entry["security_policy"] = String::utf8(
                reinterpret_cast<const char *>(ep.securityPolicyUri.data),
                static_cast<int>(ep.securityPolicyUri.length));
        else
            entry["security_policy"] = String();

        endpoints.push_back(entry);
    }

    UA_Array_delete(descs, count, &UA_TYPES[UA_TYPES_ENDPOINTDESCRIPTION]);
    return endpoints;
}