// =============================================================================
// godot_opcua.cpp  (v3)
//
// Memory contract
// ───────────────
// Every UA_NodeId from OpcUaNodeId::to_ua_node_id() is cleared with
// UA_NodeId_clear() after use (no-op for numeric; frees string bytes).
// Every UA_Variant, UA_BrowseResponse, UA_BrowseNextResponse,
// UA_ReadResponse, UA_CreateSubscriptionResponse, UA_MonitoredItemCreateResult
// is cleared before its scope exits, including all error paths.
// Heap-allocated String* tag contexts are freed in
// _delete_subscription_entry_locked() or _remove_monitored_item_by_tag_locked().
// =============================================================================

#include "godot_opcua.h"
#include "opcua_node_id.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/time.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

// ============================================================================
// Constructor / Destructor
// ============================================================================

GodotOpcUa::GodotOpcUa() {
    _poll_thread.instantiate();
}

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
    ClassDB::bind_method(D_METHOD("connect_with_credentials", "url", "username", "password"),
                         &GodotOpcUa::connect_with_credentials);
    ClassDB::bind_method(D_METHOD("disconnect_server"),
                         &GodotOpcUa::disconnect_server);

    // ── Read / write ──────────────────────────────────────────────────────────
    ClassDB::bind_method(D_METHOD("read_node", "node_id"),
                         &GodotOpcUa::read_node);
    ClassDB::bind_method(D_METHOD("read_nodes", "node_ids"),
                         &GodotOpcUa::read_nodes);
    ClassDB::bind_method(D_METHOD("write_node", "node_id", "value"),
                         &GodotOpcUa::write_node);
    ClassDB::bind_method(D_METHOD("call_ua_method", "object_id", "method_id", "input_args"),
                         &GodotOpcUa::call_ua_method);

    // ── Subscription ──────────────────────────────────────────────────────────
    ClassDB::bind_method(D_METHOD("create_subscription", "node_specs", "interval_ms"),
                         &GodotOpcUa::create_subscription);
    ClassDB::bind_method(D_METHOD("delete_subscription", "handle"),
                         &GodotOpcUa::delete_subscription);
    ClassDB::bind_method(D_METHOD("delete_all_subscriptions"),
                         &GodotOpcUa::delete_all_subscriptions);
    ClassDB::bind_method(D_METHOD("add_monitored_item",
                                   "handle", "node_id", "sampling_ms", "deadband"),
                         &GodotOpcUa::add_monitored_item);
    ClassDB::bind_method(D_METHOD("remove_monitored_item", "handle", "node_id"),
                         &GodotOpcUa::remove_monitored_item);

    // ── Polling ───────────────────────────────────────────────────────────────
    ClassDB::bind_method(D_METHOD("start_polling", "interval_sec"),
                         &GodotOpcUa::start_polling);
    ClassDB::bind_method(D_METHOD("stop_polling"),
                         &GodotOpcUa::stop_polling);
    ClassDB::bind_method(D_METHOD("set_reconnect_interval", "seconds"),
                         &GodotOpcUa::set_reconnect_interval);
    ClassDB::bind_method(D_METHOD("set_max_reconnect_attempts", "attempts"),
                         &GodotOpcUa::set_max_reconnect_attempts);

    // ── Cache ─────────────────────────────────────────────────────────────────
    ClassDB::bind_method(D_METHOD("get_tag_value", "tag_name"),
                         &GodotOpcUa::get_tag_value);
    ClassDB::bind_method(D_METHOD("get_tag_entry", "tag_name"),
                         &GodotOpcUa::get_tag_entry);
    ClassDB::bind_method(D_METHOD("get_all_tag_values"),
                         &GodotOpcUa::get_all_tag_values);
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

    // ── State polling ─────────────────────────────────────────────────────────
    ClassDB::bind_method(D_METHOD("is_server_connected"),
                         &GodotOpcUa::is_server_connected);
    ClassDB::bind_method(D_METHOD("has_connection_failed"),
                         &GodotOpcUa::has_connection_failed);

    // ── Signals ───────────────────────────────────────────────────────────────
    // tag_updated: carries full entry Dictionary (value, timestamp_ms, quality, …)
    ADD_SIGNAL(MethodInfo("tag_updated",
        PropertyInfo(Variant::STRING,     "tag_name"),
        PropertyInfo(Variant::DICTIONARY, "entry")));

    ADD_SIGNAL(MethodInfo("connection_changed",
        PropertyInfo(Variant::BOOL, "connected")));

    // Emitted when max_reconnect_attempts is reached without success.
    ADD_SIGNAL(MethodInfo("connection_failed"));
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

    // ── 1-D array ─────────────────────────────────────────────────────────────
    // Flatten into a Godot Array of the corresponding scalar type.
    Array out;
    out.resize(static_cast<int>(ua_var.arrayLength));

    // Build a temporary scalar UA_Variant that borrows each element's pointer
    // so we can reuse the scalar conversion path without extra allocations.
    for (size_t i = 0; i < ua_var.arrayLength; ++i) {
        const size_t stride = ua_var.type->memSize;
        UA_Variant elem;
        UA_Variant_init(&elem);
        elem.type = ua_var.type;
        // Point into the array storage — no allocation, no ownership transfer.
        elem.data = static_cast<UA_Byte *>(ua_var.data) + i * stride;
        // isScalar => arrayLength==0 and arrayDimensionsSize==0 (already true after init)
        out[static_cast<int>(i)] = _ua_variant_to_godot(elem);
        // Do NOT UA_Variant_clear elem — we don't own the data pointer.
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
            // UA_Variant_setScalarCopy deep-copies the bytes; do NOT UA_String_clear(&s).
            return scalar_copy(&s, &UA_TYPES[UA_TYPES_STRING]);
        }
        default:
            UtilityFunctions::push_warning(
                String("GodotOpcUa: Cannot convert Variant type '") +
                Variant::get_type_name(gd_var.get_type()) + "' to UA_Variant.");
            return false;
    }
}

// ============================================================================
// _make_tag_entry — build a cached value Dictionary from a UA_DataValue
// ============================================================================

Dictionary GodotOpcUa::_make_tag_entry(const UA_DataValue &dv) const {
    Dictionary entry;

    entry["value"]        = dv.hasValue ? _ua_variant_to_godot(dv.value) : Variant();
    entry["quality"]      = static_cast<int64_t>(dv.status);
    // UA_StatusCode_isGood: top two bits == 0x00 means Good category.
    entry["quality_good"] = static_cast<bool>(UA_StatusCode_isGood(dv.status));

    // UA_DateTime = 100-nanosecond intervals since 1601-01-01.
    // Subtract the 1601→1970 offset (in 100 ns ticks) then convert to ms.
    static const int64_t UA_EPOCH_OFFSET_100NS = 116444736000000000LL;
    int64_t ts_ms = 0;
    if (dv.hasSourceTimestamp && dv.sourceTimestamp > UA_EPOCH_OFFSET_100NS)
        ts_ms = (static_cast<int64_t>(dv.sourceTimestamp) - UA_EPOCH_OFFSET_100NS) / 10000LL;

    entry["timestamp_ms"] = ts_ms;

    // Monotonic engine tick (milliseconds since start) used by get_changed_tags_since.
    entry["tick"] = static_cast<int64_t>(Time::get_singleton()->get_ticks_msec());

    return entry;
}

// ============================================================================
// Static helpers — node IDs and node class
// ============================================================================

String GodotOpcUa::_node_id_to_string(const UA_NodeId &id) {
    // Reuse OpcUaNodeId to avoid duplicating the logic.
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
// Private — _do_connect
// ============================================================================

UA_StatusCode GodotOpcUa::_do_connect(UA_Client *client, const String &url) {
    const CharString url_utf8 = url.utf8();
    if (_auth_mode == AuthMode::Username) {
        const CharString user_utf8 = _auth_username.utf8();
        const CharString pass_utf8 = _auth_password.utf8();
        // UA_Client_connect_username sets a UA_UserNameIdentityToken internally.
        return UA_Client_connectUsername(client,
                                         url_utf8.get_data(),
                                         user_utf8.get_data(),
                                         pass_utf8.get_data());
    }
    return UA_Client_connect(client, url_utf8.get_data());
}

// ============================================================================
// Private — _rebuild_client_locked  (called with _ua_mutex held)
// ============================================================================

bool GodotOpcUa::_rebuild_client_locked() {
    if (_client != nullptr) {
        // Reset server-side IDs for all subscription entries; keep item configs
        // so _replay_subscriptions_locked() can recreate them on the new session.
        for (auto &[handle, entry] : _subscriptions) {
            entry.sub_id = 0;
            for (auto &item : entry.items)
                item.mon_id = 0;
        }
        // Deleting the client implicitly closes the TCP socket; no explicit
        // disconnect is needed (and may fail anyway if the network is gone).
        UA_Client_delete(_client);
        _client = nullptr;
    }

    _client = UA_Client_new();
    if (_client == nullptr) {
        UtilityFunctions::push_error("GodotOpcUa: UA_Client_new() returned null.");
        return false;
    }

    UA_ClientConfig *cfg = UA_Client_getConfig(_client);
    const UA_StatusCode sc = UA_ClientConfig_setDefault(cfg);
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
// Private — subscription helpers  (all with _ua_mutex held)
// ============================================================================

bool GodotOpcUa::_create_subscription_entry_locked(SubscriptionEntry &entry) {
    if (_client == nullptr) return false;

    UA_CreateSubscriptionRequest sub_req = UA_CreateSubscriptionRequest_default();
    sub_req.requestedPublishingInterval = static_cast<UA_Double>(entry.interval_ms);
    sub_req.requestedLifetimeCount      = 300;
    sub_req.requestedMaxKeepAliveCount  = 10;
    sub_req.maxNotificationsPerPublish  = 0;   // no server-side cap
    sub_req.publishingEnabled           = UA_TRUE;

    UA_CreateSubscriptionResponse sub_resp =
        UA_Client_Subscriptions_create(_client, sub_req,
            /*subscriptionContext=*/this,
            nullptr, nullptr);

    if (sub_resp.responseHeader.serviceResult != UA_STATUSCODE_GOOD) {
        UtilityFunctions::push_error(
            String("GodotOpcUa: Create subscription failed: ") +
            String(UA_StatusCode_name(sub_resp.responseHeader.serviceResult)));
        UA_CreateSubscriptionResponse_clear(&sub_resp);
        return false;
    }

    entry.sub_id = sub_resp.subscriptionId;
    UA_CreateSubscriptionResponse_clear(&sub_resp);

    // Create monitored items for every saved item config.
    for (auto &item : entry.items) {
        if (item.node_id.is_null()) continue;
        // mon_id == 0 means it needs (re-)creating on the server.
        if (item.mon_id != 0) continue;

        // Build the request manually rather than using
        // UA_MonitoredItemCreateRequest_default(), which does a shallow struct
        // copy of the UA_NodeId.  For string node IDs that copy shares the
        // heap-allocated data pointer between nid and mon_req, causing a
        // double-free when both are cleared.  Building directly into mon_req
        // makes mon_req the sole owner; UA_MonitoredItemCreateRequest_clear()
        // then frees the string bytes exactly once.
        UA_MonitoredItemCreateRequest mon_req;
        UA_MonitoredItemCreateRequest_init(&mon_req);
        mon_req.itemToMonitor.nodeId      = item.node_id->to_ua_node_id(); // sole owner
        mon_req.itemToMonitor.attributeId = UA_ATTRIBUTEID_VALUE;
        mon_req.monitoringMode            = UA_MONITORINGMODE_REPORTING;
        mon_req.requestedParameters.samplingInterval =
            static_cast<UA_Double>(item.sampling_ms);
        mon_req.requestedParameters.discardOldest = UA_TRUE;
        mon_req.requestedParameters.queueSize     = 1;

        // Apply absolute dead-band filter if requested.
        if (item.deadband > 0.0f) {
            // Heap-allocate so UA_MonitoredItemCreateRequest_clear() frees it.
            UA_DataChangeFilter *filt = static_cast<UA_DataChangeFilter *>(
                UA_new(&UA_TYPES[UA_TYPES_DATACHANGEFILTER]));
            UA_DataChangeFilter_init(filt);
            filt->trigger       = UA_DATACHANGETRIGGER_STATUSVALUE;
            filt->deadbandType  = UA_DEADBANDTYPE_ABSOLUTE;
            filt->deadbandValue = static_cast<UA_Double>(item.deadband);

            mon_req.requestedParameters.filter.encoding =
                UA_EXTENSIONOBJECT_DECODED;
            mon_req.requestedParameters.filter.content.decoded.type =
                &UA_TYPES[UA_TYPES_DATACHANGEFILTER];
            mon_req.requestedParameters.filter.content.decoded.data = filt;
        }

        UA_MonitoredItemCreateResult mon_result =
            UA_Client_MonitoredItems_createDataChange(
                _client, entry.sub_id,
                UA_TIMESTAMPSTORETURN_BOTH,
                mon_req,
                item.tag_ctx,            // monitoredItemContext
                &GodotOpcUa::_on_data_change,
                nullptr);

        // Clears nodeId string bytes (if string type) and filter — exactly once.
        UA_MonitoredItemCreateRequest_clear(&mon_req);

        if (mon_result.statusCode == UA_STATUSCODE_GOOD) {
            item.mon_id = mon_result.monitoredItemId;
        } else {
            UtilityFunctions::push_warning(
                String("GodotOpcUa: MonitoredItem create failed for ") +
                *item.tag_ctx + ": " +
                String(UA_StatusCode_name(mon_result.statusCode)));
        }
        UA_MonitoredItemCreateResult_clear(&mon_result);
    }
    return true;
}

bool GodotOpcUa::_add_monitored_item_locked(SubscriptionEntry  &entry,
                                             Ref<OpcUaNodeId>    node_id,
                                             float               sampling_ms,
                                             float               deadband) {
    if (node_id.is_null() || _client == nullptr) return false;

    const String tag_name = node_id->to_tag_name();

    // Reject duplicate.
    for (const auto &existing : entry.items) {
        if (existing.tag_ctx && *existing.tag_ctx == tag_name) {
            UtilityFunctions::push_warning(
                String("GodotOpcUa: add_monitored_item: ") +
                tag_name + " already in subscription.");
            return false;
        }
    }

    MonitoredItemEntry item;
    item.node_id     = node_id;
    item.sampling_ms = sampling_ms;
    item.deadband    = deadband;
    item.tag_ctx     = new String(tag_name);

    // Same single-owner pattern as _create_subscription_entry_locked.
    UA_MonitoredItemCreateRequest mon_req;
    UA_MonitoredItemCreateRequest_init(&mon_req);
    mon_req.itemToMonitor.nodeId      = node_id->to_ua_node_id(); // sole owner
    mon_req.itemToMonitor.attributeId = UA_ATTRIBUTEID_VALUE;
    mon_req.monitoringMode            = UA_MONITORINGMODE_REPORTING;
    mon_req.requestedParameters.samplingInterval =
        static_cast<UA_Double>(sampling_ms);
    mon_req.requestedParameters.discardOldest = UA_TRUE;
    mon_req.requestedParameters.queueSize     = 1;

    if (deadband > 0.0f) {
        UA_DataChangeFilter *filt = static_cast<UA_DataChangeFilter *>(
            UA_new(&UA_TYPES[UA_TYPES_DATACHANGEFILTER]));
        UA_DataChangeFilter_init(filt);
        filt->trigger       = UA_DATACHANGETRIGGER_STATUSVALUE;
        filt->deadbandType  = UA_DEADBANDTYPE_ABSOLUTE;
        filt->deadbandValue = static_cast<UA_Double>(deadband);
        mon_req.requestedParameters.filter.encoding =
            UA_EXTENSIONOBJECT_DECODED;
        mon_req.requestedParameters.filter.content.decoded.type =
            &UA_TYPES[UA_TYPES_DATACHANGEFILTER];
        mon_req.requestedParameters.filter.content.decoded.data = filt;
    }

    UA_MonitoredItemCreateResult mon_result =
        UA_Client_MonitoredItems_createDataChange(
            _client, entry.sub_id,
            UA_TIMESTAMPSTORETURN_BOTH,
            mon_req,
            item.tag_ctx,
            &GodotOpcUa::_on_data_change,
            nullptr);

    UA_MonitoredItemCreateRequest_clear(&mon_req);

    bool ok = (mon_result.statusCode == UA_STATUSCODE_GOOD);
    if (ok) {
        item.mon_id = mon_result.monitoredItemId;
        entry.items.push_back(std::move(item));
    } else {
        UtilityFunctions::push_warning(
            String("GodotOpcUa: add_monitored_item failed for ") + tag_name +
            ": " + String(UA_StatusCode_name(mon_result.statusCode)));
        delete item.tag_ctx;
    }
    UA_MonitoredItemCreateResult_clear(&mon_result);
    return ok;
}

void GodotOpcUa::_remove_monitored_item_by_tag_locked(SubscriptionEntry &entry,
                                                       const String      &tag_name) {
    for (auto it = entry.items.begin(); it != entry.items.end(); ++it) {
        if (it->tag_ctx && *it->tag_ctx == tag_name) {
            if (_client != nullptr && it->mon_id != 0) {
                UA_Client_MonitoredItems_deleteSingle(
                    _client, entry.sub_id, it->mon_id);
            }
            delete it->tag_ctx;
            entry.items.erase(it);
            return;
        }
    }
}

void GodotOpcUa::_delete_subscription_entry_locked(SubscriptionEntry &entry) {
    if (entry.sub_id != 0 && _client != nullptr) {
        UA_Client_Subscriptions_deleteSingle(_client, entry.sub_id);
    }
    entry.sub_id = 0;
    for (auto &item : entry.items) {
        delete item.tag_ctx;
        item.tag_ctx = nullptr;
    }
    entry.items.clear();
}

void GodotOpcUa::_delete_all_subscriptions_locked() {
    for (auto &[handle, entry] : _subscriptions)
        _delete_subscription_entry_locked(entry);
    _subscriptions.clear();
}

void GodotOpcUa::_replay_subscriptions_locked() {
    // Called after a successful reconnect. The old UA_Client was destroyed so
    // all server-side subscriptions are gone. item configs and tag_ctx strings
    // are intact because _rebuild_client_locked() does NOT free them.
    for (auto &[handle, entry] : _subscriptions)
        _create_subscription_entry_locked(entry);
}

// ============================================================================
// Static callback — _on_data_change  (poll thread, inside UA_Client_run_iterate)
// ============================================================================

void GodotOpcUa::_on_data_change(UA_Client * /*client*/,
                                  UA_UInt32 /*subId*/, void *subContext,
                                  UA_UInt32 /*monId*/, void *monContext,
                                  UA_DataValue *value) {
    if (!subContext || !monContext || !value) return;

    GodotOpcUa *self      = static_cast<GodotOpcUa *>(subContext);
    const String tag_name = *static_cast<String *>(monContext);

    // Build entry (const operation, no shared-state mutation needed).
    const Dictionary entry = self->_make_tag_entry(*value);

    // Update cache under _values_mutex (independent of _ua_mutex — no deadlock).
    // GDScript detects new values via get_changed_tags_since() in _process();
    // no call_deferred is needed here and none is safe from a background thread
    // in GDExtension.
    {
        std::lock_guard<std::mutex> lock(self->_values_mutex);
        self->_latest_values[tag_name] = entry;
    }
}

// ============================================================================
// Poll thread
// ============================================================================

void GodotOpcUa::_poll_thread_func() {
    // Pre-charge accumulator so the first reconnect attempt fires immediately.
    double reconnect_acc = static_cast<double>(_reconnect_base_sec);

    while (_polling.load(std::memory_order_relaxed)) {

        {
            std::lock_guard<std::mutex> lock(_ua_mutex);

            if (_client != nullptr) {
                UA_SecureChannelState ch;
                UA_SessionState       se;
                UA_StatusCode         cs;
                UA_Client_getState(_client, &ch, &se, &cs);

                const bool alive = (se == UA_SESSIONSTATE_ACTIVATED);

                if (alive) {
                    // ── Connected ─────────────────────────────────────────
                    if (!_connected.load(std::memory_order_relaxed)) {
                        // Publish the new state; GDScript's _process() detects
                        // the change via is_server_connected() and emits its own
                        // signals on the main thread.  No call_deferred here —
                        // calling Godot API from a GDExtension background thread
                        // is unreliable across Godot versions.
                        _connected.store(true, std::memory_order_release);
                        _reconnect_attempt = 0;
                    }
                    // Drive OPC UA network I/O + fire subscription callbacks.
                    UA_Client_run_iterate(_client, 1 /* ms */);
                    reconnect_acc = 0.0;

                } else {
                    // ── Disconnected ─────────────────────────────────────
                    if (_connected.load(std::memory_order_relaxed)) {
                        _connected.store(false, std::memory_order_release);
                    }

                    // Exponential back-off: base * 2^attempt, capped at 60 s.
                    const double wait = std::min(
                        static_cast<double>(_reconnect_base_sec) *
                            std::pow(2.0, static_cast<double>(_reconnect_attempt)),
                        static_cast<double>(RECONNECT_MAX_INTERVAL_SEC));

                    reconnect_acc += static_cast<double>(_poll_interval_sec);

                    if (reconnect_acc >= wait && !_last_url.is_empty()) {
                        reconnect_acc = 0.0;

                        // Rebuild the client from scratch to guarantee a clean state.
                        if (_rebuild_client_locked()) {
                            const UA_StatusCode sc =
                                _do_connect(_client, _last_url);

                            if (sc == UA_STATUSCODE_GOOD) {
                                _connected.store(true, std::memory_order_release);
                                _reconnect_attempt = 0;
                                _replay_subscriptions_locked();
                            } else {
                                ++_reconnect_attempt;
                                if (_max_reconnect_attempts != -1 &&
                                        _reconnect_attempt >= _max_reconnect_attempts) {
                                    // Signal failure via atomic flag; GDScript's
                                    // _process() reads this via has_connection_failed().
                                    _connection_failed_flag.store(
                                        true, std::memory_order_release);
                                    _polling.store(false, std::memory_order_relaxed);
                                }
                            }
                        }
                    }
                }
            }
        } // _ua_mutex released

        // Sleep in 10 ms chunks so stop_polling() exits within ~10 ms.
        const int total_ms = static_cast<int>(_poll_interval_sec * 1000.0f);
        for (int e = 0; e < total_ms && _polling.load(std::memory_order_relaxed); e += 10)
            OS::get_singleton()->delay_msec(10);
    }
}

// ============================================================================
// Public — connect_to_server / connect_with_credentials
// ============================================================================

bool GodotOpcUa::connect_to_server(String url) {
    _auth_mode = AuthMode::Anonymous;
    return connect_with_credentials(url, String(), String());
}

bool GodotOpcUa::connect_with_credentials(String url,
                                            String username,
                                            String password) {
    if (_polling.load()) {
        UtilityFunctions::push_warning(
            "GodotOpcUa: Stop polling before calling connect.");
        return false;
    }
    if (_client != nullptr) {
        UtilityFunctions::push_warning(
            "GodotOpcUa: Already connected. Call disconnect_server() first.");
        return false;
    }

    if (!username.is_empty()) {
        _auth_mode     = AuthMode::Username;
        _auth_username = username;
        _auth_password = password;
    } else {
        _auth_mode = AuthMode::Anonymous;
    }

    // Use rebuild to initialise a clean, configured client.
    {
        std::lock_guard<std::mutex> lock(_ua_mutex);
        if (!_rebuild_client_locked()) return false;
    }

    const UA_StatusCode sc = _do_connect(_client, url);
    if (sc != UA_STATUSCODE_GOOD) {
        UtilityFunctions::push_error(
            String("GodotOpcUa: Connect to \"") + url + "\" failed: " +
            String(UA_StatusCode_name(sc)));
        UA_Client_delete(_client);
        _client = nullptr;
        return false;
    }

    // _connected is intentionally NOT set here.  The poll thread is the sole
    // writer to _connected during normal operation; setting it here would cause
    // the poll thread's "if (!_connected)" guard to never fire on the very first
    // iteration, so GDScript would never observe the connected→true transition.
    _last_url          = url;
    _reconnect_attempt = 0;
    return true;
}

// ============================================================================
// Public — is_server_connected / has_connection_failed
// ============================================================================

bool GodotOpcUa::is_server_connected() const {
    // acquire matches the release stores in _poll_thread_func so the calling
    // thread sees all writes the poll thread made before setting _connected.
    return _connected.load(std::memory_order_acquire);
}

bool GodotOpcUa::has_connection_failed() {
    // exchange atomically reads and clears the flag in one operation, so only
    // one call per failure event ever returns true.
    return _connection_failed_flag.exchange(false, std::memory_order_acq_rel);
}

// ============================================================================
// Public — disconnect_server
// ============================================================================

void GodotOpcUa::disconnect_server() {
    stop_polling(); // joins thread; after this no poll thread touches _client

    {
        std::lock_guard<std::mutex> lock(_ua_mutex);
        _delete_all_subscriptions_locked();
        if (_client != nullptr) {
            UA_Client_disconnect(_client);
            UA_Client_delete(_client);
            _client = nullptr;
        }
    }

    _connected  = false;
    _last_url   = String();
    _auth_mode  = AuthMode::Anonymous;

    {
        std::lock_guard<std::mutex> lock(_values_mutex);
        _latest_values.clear();
    }
}

// ============================================================================
// Public — read_node  (single, synchronous)
// ============================================================================

Variant GodotOpcUa::read_node(Ref<OpcUaNodeId> node_id) {
    if (node_id.is_null()) return Variant();
    std::lock_guard<std::mutex> lock(_ua_mutex);

    if (_client == nullptr) {
        UtilityFunctions::push_error("GodotOpcUa: read_node() while disconnected.");
        return Variant();
    }

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

// ============================================================================
// Public — read_nodes  (batch, synchronous)
// ============================================================================

Dictionary GodotOpcUa::read_nodes(Array node_ids) {
    Dictionary results;
    if (node_ids.size() == 0) return results;

    std::lock_guard<std::mutex> lock(_ua_mutex);
    if (_client == nullptr) {
        UtilityFunctions::push_error("GodotOpcUa: read_nodes() while disconnected.");
        return results;
    }

    const size_t count = static_cast<size_t>(node_ids.size());

    UA_ReadRequest req;
    UA_ReadRequest_init(&req);
    req.timestampsToReturn = UA_TIMESTAMPSTORETURN_BOTH;
    req.nodesToRead = static_cast<UA_ReadValueId *>(
        UA_Array_new(count, &UA_TYPES[UA_TYPES_READVALUEID]));
    req.nodesToReadSize = count;

    // Build the request and record tag names in the same order.
    std::vector<String> tag_names(count);
    std::vector<UA_NodeId> nids(count);
    for (size_t i = 0; i < count; ++i) {
        Ref<OpcUaNodeId> n = node_ids[static_cast<int>(i)];
        if (n.is_null()) {
            req.nodesToRead[i].nodeId    = UA_NODEID_NUMERIC(0, 0);
            req.nodesToRead[i].attributeId = UA_ATTRIBUTEID_VALUE;
            continue;
        }
        tag_names[i]                    = n->to_tag_name();
        nids[i]                         = n->to_ua_node_id();
        req.nodesToRead[i].nodeId       = nids[i];  // pointer-alias, valid for call lifetime
        req.nodesToRead[i].attributeId  = UA_ATTRIBUTEID_VALUE;
    }

    UA_ReadResponse resp = UA_Client_Service_read(_client, req);
    // Clear the request; the nodeId entries are aliases into nids[]; do NOT
    // let UA_ReadRequest_clear try to free them — zero the pointer first.
    for (size_t i = 0; i < count; ++i)
        UA_NodeId_init(&req.nodesToRead[i].nodeId); // prevent double-free
    UA_ReadRequest_clear(&req);

    // Now free our own copies.
    for (size_t i = 0; i < count; ++i)
        UA_NodeId_clear(&nids[i]);

    if (resp.responseHeader.serviceResult == UA_STATUSCODE_GOOD) {
        for (size_t i = 0; i < resp.resultsSize && i < count; ++i) {
            if (tag_names[i].is_empty()) continue;
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
// Public — write_node
// ============================================================================

bool GodotOpcUa::write_node(Ref<OpcUaNodeId> node_id, const Variant &value) {
    if (node_id.is_null()) return false;
    std::lock_guard<std::mutex> lock(_ua_mutex);

    if (_client == nullptr) {
        UtilityFunctions::push_error("GodotOpcUa: write_node() while disconnected.");
        return false;
    }

    UA_Variant ua_val;
    if (!_godot_to_ua_variant(value, ua_val)) return false;

    UA_NodeId nid    = node_id->to_ua_node_id();
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
// Public — call_ua_method
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

    std::lock_guard<std::mutex> lock(_ua_mutex);
    if (_client == nullptr) {
        result["error"] = "Not connected";
        return result;
    }

    // Convert input arguments.
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
        _client,
        obj_nid, mth_nid,
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

    // UA_Array_delete calls UA_Variant_clear on each element then frees the array.
    UA_Array_delete(out_vars, out_count, &UA_TYPES[UA_TYPES_VARIANT]);

    result["success"]     = true;
    result["output_args"] = out_arr;
    return result;
}

// ============================================================================
// Public — Subscription management
// ============================================================================

int GodotOpcUa::create_subscription(Array node_specs, float interval_ms) {
    if (node_specs.size() == 0) {
        UtilityFunctions::push_warning("GodotOpcUa: create_subscription with empty list.");
        return -1;
    }

    std::lock_guard<std::mutex> lock(_ua_mutex);

    const int handle = _next_sub_handle++;
    SubscriptionEntry &entry = _subscriptions[handle];
    entry.interval_ms = interval_ms;

    // Parse node_specs into MonitoredItemEntry configs (without server-side IDs yet).
    for (int i = 0; i < node_specs.size(); ++i) {
        const Dictionary spec = node_specs[i];
        if (!spec.has("node_id")) {
            UtilityFunctions::push_warning(
                "GodotOpcUa: create_subscription: spec missing 'node_id'; skipping.");
            continue;
        }

        Ref<OpcUaNodeId> nid = spec["node_id"];
        if (nid.is_null()) continue;

        const float samp = spec.has("sampling_ms")
            ? static_cast<float>(spec["sampling_ms"]) : 250.0f;
        const float dead = spec.has("deadband")
            ? static_cast<float>(spec["deadband"]) : 0.0f;

        MonitoredItemEntry item;
        item.node_id     = nid;
        item.sampling_ms = samp;
        item.deadband    = dead;
        item.tag_ctx     = new String(nid->to_tag_name());
        entry.items.push_back(std::move(item));
    }

    if (entry.items.empty()) {
        _subscriptions.erase(handle);
        return -1;
    }

    // Only create server-side if we are connected.
    if (_client != nullptr) {
        if (!_create_subscription_entry_locked(entry)) {
            // Creation failed; keep the config so it is replayed on reconnect.
            UtilityFunctions::push_warning(
                "GodotOpcUa: Subscription config saved; will be applied on reconnect.");
        }
    } else {
        UtilityFunctions::push_warning(
            "GodotOpcUa: Not connected; subscription config saved for reconnect.");
    }

    return handle;
}

void GodotOpcUa::delete_subscription(int handle) {
    std::lock_guard<std::mutex> lock(_ua_mutex);
    auto it = _subscriptions.find(handle);
    if (it == _subscriptions.end()) return;
    _delete_subscription_entry_locked(it->second);
    _subscriptions.erase(it);
}

void GodotOpcUa::delete_all_subscriptions() {
    std::lock_guard<std::mutex> lock(_ua_mutex);
    _delete_all_subscriptions_locked();
}

bool GodotOpcUa::add_monitored_item(int              handle,
                                     Ref<OpcUaNodeId> node_id,
                                     float            sampling_ms,
                                     float            deadband) {
    std::lock_guard<std::mutex> lock(_ua_mutex);
    auto it = _subscriptions.find(handle);
    if (it == _subscriptions.end()) {
        UtilityFunctions::push_error(
            String("GodotOpcUa: Unknown subscription handle ") +
            String::num_int64(handle));
        return false;
    }
    return _add_monitored_item_locked(it->second, node_id, sampling_ms, deadband);
}

void GodotOpcUa::remove_monitored_item(int handle, Ref<OpcUaNodeId> node_id) {
    if (node_id.is_null()) return;
    std::lock_guard<std::mutex> lock(_ua_mutex);
    auto it = _subscriptions.find(handle);
    if (it == _subscriptions.end()) return;
    _remove_monitored_item_by_tag_locked(it->second, node_id->to_tag_name());
}

// ============================================================================
// Public — Polling & reconnection
// ============================================================================

void GodotOpcUa::start_polling(float interval_sec) {
    if (_polling.load()) {
        UtilityFunctions::push_warning("GodotOpcUa: Polling already active.");
        return;
    }
    _poll_interval_sec = (interval_sec > 0.0f) ? interval_sec : 0.05f;
    _polling.store(true, std::memory_order_relaxed);
    _poll_thread->start(callable_mp(this, &GodotOpcUa::_poll_thread_func));
}

void GodotOpcUa::stop_polling() {
    if (!_polling.load()) return;
    _polling.store(false, std::memory_order_relaxed);
    _poll_thread->wait_to_finish();
}

void GodotOpcUa::set_reconnect_interval(float seconds) {
    _reconnect_base_sec = (seconds > 0.0f) ? seconds : 1.0f;
}

void GodotOpcUa::set_max_reconnect_attempts(int attempts) {
    _max_reconnect_attempts = attempts;
}

// ============================================================================
// Public — Cached value access
// ============================================================================

Variant GodotOpcUa::get_tag_value(String tag_name) {
    std::lock_guard<std::mutex> lock(_values_mutex);
    if (!_latest_values.has(tag_name)) return Variant();
    const Dictionary entry = _latest_values[tag_name];
    return entry.has("value") ? entry["value"] : Variant();
}

Dictionary GodotOpcUa::get_tag_entry(String tag_name) {
    std::lock_guard<std::mutex> lock(_values_mutex);
    if (!_latest_values.has(tag_name)) return Dictionary();
    return _latest_values[tag_name];
}

Dictionary GodotOpcUa::get_all_tag_values() {
    std::lock_guard<std::mutex> lock(_values_mutex);
    Dictionary out;
    Array keys = _latest_values.keys();
    for (int i = 0; i < keys.size(); ++i) {
        const Variant &k   = keys[i];
        const Dictionary e = _latest_values[k];
        out[k] = e.has("value") ? e["value"] : Variant();
    }
    return out;
}

Dictionary GodotOpcUa::get_all_tag_entries() {
    std::lock_guard<std::mutex> lock(_values_mutex);
    return _latest_values.duplicate();
}

Dictionary GodotOpcUa::get_changed_tags_since(int64_t since_tick_ms) {
    std::lock_guard<std::mutex> lock(_values_mutex);
    Dictionary out;
    Array keys = _latest_values.keys();
    for (int i = 0; i < keys.size(); ++i) {
        const Variant   &k    = keys[i];
        const Dictionary entry = _latest_values[k];
        if (entry.has("tick") &&
                static_cast<int64_t>(entry["tick"]) > since_tick_ms)
            out[k] = entry;
    }
    return out;
}

// ============================================================================
// Private — browse helpers  (called with _ua_mutex held)
// ============================================================================

void GodotOpcUa::_process_browse_result_locked(Array                &out_children,
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
            _browse_with_continuation_locked(ref.nodeId.nodeId, children, depth + 1);
            entry["children"] = children;
        } else {
            entry["children"] = Array();
        }

        out_children.push_back(entry);
    }
}

bool GodotOpcUa::_browse_with_continuation_locked(const UA_NodeId &nodeId,
                                                   Array           &out_children,
                                                   int              depth) {
    // ── Initial browse request ────────────────────────────────────────────────
    UA_BrowseRequest bReq;
    UA_BrowseRequest_init(&bReq);
    bReq.requestedMaxReferencesPerNode = 0; // 0 = server decides (no artificial cap)
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
    UA_BrowseRequest_clear(&bReq); // frees the copied nodeId

    if (bResp.responseHeader.serviceResult != UA_STATUSCODE_GOOD ||
            bResp.resultsSize == 0) {
        UA_BrowseResponse_clear(&bResp);
        return false;
    }

    _process_browse_result_locked(out_children, bResp.results[0], depth);

    // ── Continuation-point loop ───────────────────────────────────────────────
    // If the server has more references than it returned, continuationPoint
    // is non-empty.  Keep calling BrowseNext until it is empty.
    UA_ByteString cont;
    UA_ByteString_init(&cont);
    if (bResp.results[0].continuationPoint.length > 0)
        UA_ByteString_copy(&bResp.results[0].continuationPoint, &cont);

    UA_BrowseResponse_clear(&bResp);

    while (cont.length > 0) {
        UA_BrowseNextRequest nextReq;
        UA_BrowseNextRequest_init(&nextReq);
        // UA_FALSE = keep the continuation point alive for the next call.
        nextReq.releaseContinuationPoints = UA_FALSE;
        nextReq.continuationPoints        = &cont; // alias, not owned
        nextReq.continuationPointsSize    = 1;

        UA_BrowseNextResponse nextResp =
            UA_Client_Service_browseNext(_client, nextReq);
        // nextReq holds a non-owning alias into cont; do not clear nextReq.

        // Extract the next continuation point before we clear the response.
        UA_ByteString next_cont;
        UA_ByteString_init(&next_cont);
        if (nextResp.resultsSize > 0 &&
                nextResp.results[0].continuationPoint.length > 0)
            UA_ByteString_copy(&nextResp.results[0].continuationPoint, &next_cont);

        if (nextResp.resultsSize > 0)
            _process_browse_result_locked(out_children, nextResp.results[0], depth);

        UA_BrowseNextResponse_clear(&nextResp);

        // Swap continuation points and free the old one.
        UA_ByteString_clear(&cont);
        cont = next_cont; // takes ownership
    }
    UA_ByteString_clear(&cont);
    return true;
}

// ============================================================================
// Public — browse_server
// ============================================================================

Dictionary GodotOpcUa::browse_server() {
    Dictionary root;
    std::lock_guard<std::mutex> lock(_ua_mutex);

    if (_client == nullptr) {
        UtilityFunctions::push_error("GodotOpcUa: browse_server() while disconnected.");
        return root;
    }

    root["name"]       = String("Root");
    root["node_id"]    = String("ns0|i=84");
    root["node_class"] = String("Object");

    const UA_NodeId root_id = UA_NODEID_NUMERIC(0, UA_NS0ID_ROOTFOLDER);
    Array children;
    _browse_with_continuation_locked(root_id, children, 0);
    root["children"] = children;
    return root;
}

// ============================================================================
// Public — browse_children  (flat, no recursion, with continuation points)
// ============================================================================

Array GodotOpcUa::browse_children(Ref<OpcUaNodeId> node_id) {
    Array result;
    if (node_id.is_null()) return result;
    std::lock_guard<std::mutex> lock(_ua_mutex);

    if (_client == nullptr) {
        UtilityFunctions::push_error("GodotOpcUa: browse_children() while disconnected.");
        return result;
    }

    // Flat browse: depth argument is irrelevant since _process_browse_result_locked
    // only recurses when depth < _max_browse_depth. By passing _max_browse_depth
    // we prevent any recursion and get a flat list.
    UA_NodeId nid = node_id->to_ua_node_id();
    _browse_with_continuation_locked(nid, result, _max_browse_depth);
    UA_NodeId_clear(&nid);

    // Strip the "children" key that _process_browse_result_locked always adds.
    for (int i = 0; i < result.size(); ++i) {
        Dictionary d = result[i];
        d.erase("children");
        result[i] = d;
    }
    return result;
}

// ============================================================================
// Public — discover_servers
// ============================================================================

Array GodotOpcUa::discover_servers(String discovery_url) {
    Array servers;

    // Spin up a temporary client purely for the discovery call.
    UA_Client *tmp = UA_Client_new();
    if (!tmp) return servers;
    UA_ClientConfig_setDefault(UA_Client_getConfig(tmp));

    UA_ApplicationDescription *descs = nullptr;
    size_t desc_count = 0;

    const CharString url_utf8 = discovery_url.utf8();

    // UA_Client_findServers: 0/nullptr for serverUris and localeIds = no filter.
    const UA_StatusCode sc = UA_Client_findServers(
        tmp, url_utf8.get_data(),
        0, nullptr,   // serverUrisSize, serverUris
        0, nullptr,   // localeIdsSize, localeIds
        &desc_count, &descs);

    UA_Client_delete(tmp);

    if (sc != UA_STATUSCODE_GOOD || descs == nullptr) {
        UtilityFunctions::push_warning(
            String("GodotOpcUa: discover_servers failed: ") +
            String(UA_StatusCode_name(sc)));
        return servers;
    }

    for (size_t i = 0; i < desc_count; ++i) {
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

        // Report the first discovery URL as the server's endpoint URL.
        if (d.discoveryUrlsSize > 0 &&
                d.discoveryUrls[0].data && d.discoveryUrls[0].length > 0)
            entry["url"] = String::utf8(
                reinterpret_cast<const char *>(d.discoveryUrls[0].data),
                static_cast<int>(d.discoveryUrls[0].length));
        else
            entry["url"] = String();

        servers.push_back(entry);
    }

    UA_Array_delete(descs, desc_count, &UA_TYPES[UA_TYPES_APPLICATIONDESCRIPTION]);
    return servers;
}

// ============================================================================
// Public — get_endpoints
// ============================================================================

Array GodotOpcUa::get_endpoints(String url) {
    Array endpoints;

    UA_Client *tmp = UA_Client_new();
    if (!tmp) return endpoints;
    UA_ClientConfig_setDefault(UA_Client_getConfig(tmp));

    UA_EndpointDescription *descs = nullptr;
    size_t desc_count = 0;

    const CharString url_utf8 = url.utf8();
    const UA_StatusCode sc = UA_Client_getEndpoints(
        tmp, url_utf8.get_data(), &desc_count, &descs);

    UA_Client_delete(tmp);

    if (sc != UA_STATUSCODE_GOOD || descs == nullptr) {
        UtilityFunctions::push_warning(
            String("GodotOpcUa: get_endpoints failed: ") +
            String(UA_StatusCode_name(sc)));
        return endpoints;
    }

    auto security_mode_name = [](UA_MessageSecurityMode m) -> const char * {
        switch (m) {
            case UA_MESSAGESECURITYMODE_NONE:           return "None";
            case UA_MESSAGESECURITYMODE_SIGN:           return "Sign";
            case UA_MESSAGESECURITYMODE_SIGNANDENCRYPT: return "SignAndEncrypt";
            default:                                    return "Invalid";
        }
    };

    for (size_t i = 0; i < desc_count; ++i) {
        const UA_EndpointDescription &ep = descs[i];
        Dictionary entry;

        if (ep.endpointUrl.data && ep.endpointUrl.length > 0)
            entry["url"] = String::utf8(
                reinterpret_cast<const char *>(ep.endpointUrl.data),
                static_cast<int>(ep.endpointUrl.length));
        else
            entry["url"] = String();

        entry["security_mode"] = String(security_mode_name(ep.securityMode));

        if (ep.securityPolicyUri.data && ep.securityPolicyUri.length > 0)
            entry["security_policy"] = String::utf8(
                reinterpret_cast<const char *>(ep.securityPolicyUri.data),
                static_cast<int>(ep.securityPolicyUri.length));
        else
            entry["security_policy"] = String();

        endpoints.push_back(entry);
    }

    UA_Array_delete(descs, desc_count, &UA_TYPES[UA_TYPES_ENDPOINTDESCRIPTION]);
    return endpoints;
}