class_name ReactiveActionBinding
extends Reactive

enum ActionType { NONE, WRITE_TAG, RUN_SCRIPT, NAVIGATE_SCENE, EMIT_APP_EVENT }

var action_type   : ReactiveInt
var target_node   : ReactiveOpcUaWriteTarget
var value         : ReactiveDynamicField
var script_source : ReactiveString
var scene_path    : ReactiveString
var event_name    : ReactiveString

func _init(data: Dictionary = {}, initial_owner: Reactive = null, label: String = "ReactiveActionBinding") -> void:
    super._init(initial_owner, label)

    action_type   = ReactiveInt.new(ActionType.NONE, self, "action_type")
    target_node   = ReactiveOpcUaWriteTarget.new({}, self, "target_node")
    value         = ReactiveDynamicField.new(null, self, "value")
    script_source = ReactiveString.new("", self, "script_source")
    scene_path    = ReactiveString.new("", self, "scene_path")
    event_name    = ReactiveString.new("", self, "event_name")

    if not data.is_empty():
        from_data(data)

func _describe_value() -> String:
    return ""

func execute(context: Dictionary = {}) -> void:
    match action_type.value:
        ActionType.WRITE_TAG:
            _write_tag(value.resolved.value)
        ActionType.RUN_SCRIPT:
            _run_script(context)
        ActionType.NAVIGATE_SCENE:
            AppState.request_scene_change(scene_path.value)
        #ActionType.EMIT_APP_EVENT:
        #    WidgetEventBus.custom_event.emit(event_name.value, context)

func _write_tag(v: Variant) -> void:
    if target_node.server_id.value.is_empty() or target_node.node_id.value.is_empty():
        push_warning("ReactiveActionBinding: WRITE_TAG has no server/node configured — skipping.")
        return
    var server: ReactiveOpcUaServer = AppState.current_project.opc_ua_servers.get_entry(target_node.server_id.value)
    if server == null:
        push_warning("ReactiveActionBinding: server '%s' not found — skipping write." % target_node.server_id.value)
        return
    # Direct write — bypasses subscriptions/groups entirely.
    OpcUaManager.get_connection(server.id.value).write_tag(OpcUaNodeId.parse(target_node.node_id.value), v)

func _run_script(context: Dictionary) -> void:
    var script: GDScript = GDScript.new()
    script.source_code = "extends RefCounted\nfunc execute(ctx: Dictionary) -> void:\n%s" % _indent(script_source.value)
    if script.reload() == OK:
        var instance: RefCounted = RefCounted.new()
        instance.set_script(script)
        instance.execute(context)

func _indent(code: String) -> String:
    var out: Array = []
    for l: String in code.split("\n"):
        out.append("\t" + l)
    return "\n".join(out)

func from_data(data: Dictionary) -> void:
    action_type.value   = data.get("action_type", ActionType.NONE)
    script_source.value = data.get("script_source", "")
    scene_path.value     = data.get("scene_path", "")
    event_name.value     = data.get("event_name", "")
    target_node.from_data(data.get("target_node", {}))
    value.from_data(data.get("value", {}))

func to_data() -> Dictionary:
    return {
        "action_type": action_type.value,
        "script_source": script_source.value,
        "scene_path": scene_path.value,
        "event_name": event_name.value,
        "target_node": target_node.to_data(),
        "value": value.to_data(),
    }
