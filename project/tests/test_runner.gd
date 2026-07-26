# test/test_opc_ua_reactive_chain.gd
extends Node

var project: ReactiveProject = null

func _ready() -> void:
    print("── Test: Reactive OPC UA Chain (via OpcUaManager autoload) ──────")
    project = ReactiveProject.new(null, "")
    AppState.current_project.value = project

    _test_construction_chain()
    _test_data_roundtrip()
    _test_manager_reconciliation()

    print("── All tests passed ─────────────────────────────────────")
    get_tree().quit()

# ── 1. Construction chain: project → server → group → tag ────────────────────

func _test_construction_chain() -> void:

    project.opc_ua_servers.append(
        ReactiveOpcUaServer.new({}, project.opc_ua_servers, "ReactiveOpcUaServer")
    )

    var server: ReactiveOpcUaServer = project.opc_ua_servers.value[0]
    server.id.value = "server_01"
    server.display_name.value = "Test Server"
    server.endpoint_url.value = "opc.tcp://localhost:4840"

    assert(project.opc_ua_servers.value.size() == 1, "Expected exactly 1 server after append.")
    assert(server.id.value == "server_01", "Server id was not set correctly.")

    server.groups.append(
        ReactiveOpcUaSubscription.new({}, server.groups, "ReactiveOpcUaSubscription")
    )

    var group: ReactiveOpcUaSubscription = server.groups.value[0]
    group.id.value = "group_fast"
    group.pub_interval_ms.value = 100.0

    assert(server.groups.value.size() == 1, "Expected exactly 1 group after append.")
    assert(group.id.value == "group_fast", "Group id was not set correctly.")

    group.tags.append(
        ReactiveOpcUaTag.new({}, group.tags, "ReactiveOpcUaTag")
    )

    var tag: ReactiveOpcUaTag = group.tags.value[0]
    tag.node_id.value = "ns=2;s=Temperature"
    tag.display_name.value = "Temperature"
    tag.is_active.value = true
    tag.sampling_ms.value = 50.0
    tag.deadband.value = 0.5

    assert(group.tags.value.size() == 1, "Expected exactly 1 tag after append.")
    assert(tag.node_id.value == "ns=2;s=Temperature", "Tag node_id was not set correctly.")

    print("  ✔ Construction chain OK: 1 server, 1 group, 1 tag.")

# ── 2. to_data() / from_data() round-trip ─────────────────────────────────────

func _test_data_roundtrip() -> void:
    var server: ReactiveOpcUaServer = project.opc_ua_servers.value[0]
    var exported: Dictionary = server.to_data()

    assert(exported.has("groups"), "Exported server data missing 'groups' key.")
    assert(exported["groups"].size() == 1, "Expected exactly 1 exported group.")
    assert(exported["groups"][0]["tags"].size() == 1, "Expected exactly 1 exported tag.")
    assert(exported["groups"][0]["tags"][0]["node_id"] == "ns=2;s=Temperature",
        "Exported tag node_id does not match source.")

    var reimported: ReactiveOpcUaServer = ReactiveOpcUaServer.new(exported, null, "reimported")

    assert(reimported.groups.value.size() == 1, "Reimported server should have 1 group.")
    assert(reimported.groups.value[0].tags.value.size() == 1,
        "Reimported group should have 1 tag.")
    assert(reimported.groups.value[0].tags.value[0].node_id.value == "ns=2;s=Temperature",
        "Reimported tag node_id mismatch.")

    print("  ✔ to_data()/from_data() round-trip OK.")

# ── 3. OpcUaManager autoload reconciliation ───────────────────────────────────

func _test_manager_reconciliation() -> void:
    # Assigning to AppState.current_project triggers OpcUaManager's own
    # `AppState.current_project.changed` listener, which rebinds and
    # reconciles automatically — no direct calls into OpcUaManager needed
    # to *trigger* the behavior, only to *observe* it below.
    AppState.current_project.value = project

    var server: ReactiveOpcUaServer = project.opc_ua_servers.value[0]
    var server_id: String = server.id.value

    var connection: OpcUaServerConnection = OpcUaManager.get_connection(server_id)
    assert(connection != null,
        "OpcUaManager autoload did not spawn a connection for server '%s'." % server_id)

    # Structural change: appending a new server should trigger reconciliation
    # via project.opc_ua_servers.connect_self_changed(...) inside OpcUaManager.
    project.opc_ua_servers.append(
        ReactiveOpcUaServer.new({"id": "server_02", "display_name": "Second Server"},
            project.opc_ua_servers, "ReactiveOpcUaServer")
    )

    var second_connection: OpcUaServerConnection = OpcUaManager.get_connection("server_02")
    assert(second_connection != null,
        "OpcUaManager autoload did not reconcile the newly appended server 'server_02'.")

    print("  ✔ OpcUaManager reconciliation OK via autoload — 2 live connection(s) confirmed.")
