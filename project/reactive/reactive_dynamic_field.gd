class_name ReactiveDynamicField
extends Reactive

enum SourceType { CONSTANT, OPC_TAG, SCRIPT }

var source_type    : ReactiveInt
var constant_value : ReactiveVariant
var tag_binding    : ReactiveOpcUaTagBinding
var script_source  : ReactiveString
var resolved        : ReactiveVariant   # live, computed output — this is what consumers bind to

var _tag_value_ref     : ReactiveVariant = null
var _context_provider  : Callable = Callable()

func _init(default_value: Variant = null, initial_owner: Reactive = null, label: String = "ReactiveDynamicField") -> void:
    super._init(initial_owner, label)

    source_type    = ReactiveInt.new(SourceType.CONSTANT, self, "source_type")
    constant_value = ReactiveVariant.new(default_value, self, "constant_value")
    tag_binding    = ReactiveOpcUaTagBinding.new({}, self, "tag_binding")
    script_source  = ReactiveString.new("", self, "script_source")
    resolved       = ReactiveVariant.new(default_value, self, "resolved")

    source_type.connect_self_changed(func(_s: ReactiveInt) -> void: _rebind())
    constant_value.connect_self_changed(func(_c: ReactiveVariant) -> void: _rebind())
    tag_binding.connect_any_changed_self(func(_t: ReactiveOpcUaTagBinding) -> void: _rebind())
    script_source.connect_self_changed(func(_s: ReactiveString) -> void: _rebind())

func _describe_value() -> String:
    return ""

func set_context_provider(provider: Callable) -> void:
    _context_provider = provider
    _rebind()

func _rebind() -> void:
    _unbind_tag()
    match source_type.value:
        SourceType.CONSTANT:
            resolved.value = constant_value.value
        SourceType.OPC_TAG:
            _bind_tag()
        SourceType.SCRIPT:
            _bind_script()

func _bind_tag() -> void:
    var t: ReactiveOpcUaTagBinding = tag_binding
    if t.server_id.value.is_empty():
        return
    var server: ReactiveOpcUaServer = AppState.current_project.opc_ua_servers.get_entry(t.server_id.value)
    if server == null:
        return
    var subscription: ReactiveOpcUaSubscription = server.subscriptions.get_entry(t.subscription_id.value)
    if subscription == null:
        return
    var tag: ReactiveOpcUaTag = subscription.tags.get_entry(t.tag_id.value)
    if tag == null:
        return
    _tag_value_ref = tag.value
    _tag_value_ref.connect_self_changed(_on_tag_value_changed)
    resolved.value = _tag_value_ref.value

func _on_tag_value_changed(v: ReactiveVariant) -> void:
    resolved.value = v.value

func _unbind_tag() -> void:
    if _tag_value_ref != null:
        _tag_value_ref.reactive_changed.disconnect(_on_tag_value_changed)
    _tag_value_ref = null

func _bind_script() -> void:
    var vars: Dictionary = _context_provider.call() if _context_provider.is_valid() else {}
    var expr: Expression = Expression.new()
    if expr.parse(script_source.value, PackedStringArray(vars.keys())) == OK:
        var result: Variant = expr.execute(vars.values())
        if not expr.has_execute_failed():
            resolved.value = result

func from_data(data: Dictionary) -> void:
    source_type.value    = data.get("source_type", SourceType.CONSTANT)
    constant_value.value = data.get("constant_value", null)
    script_source.value  = data.get("script_source", "")
    tag_binding.from_data(data.get("tag_binding", {}))
    _rebind()

func to_data() -> Dictionary:
    return {
        "source_type": source_type.value,
        "constant_value": constant_value.value,
        "script_source": script_source.value,
        "tag_binding": tag_binding.to_data(),
    }
