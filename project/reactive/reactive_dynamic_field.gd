class_name ReactiveDynamicField
extends Reactive

enum SourceType { CONSTANT, OPC_TAG, OPC_TAG_ARRAY, SCRIPT }

var source_type        : ReactiveInt
var constant_value     : ReactiveVariant
var tag_binding         : ReactiveOpcUaTagBinding
var tag_array_binding   : ReactiveOpcUaTagArrayBinding
var script_source       : ReactiveString
var resolved            : ReactiveVariant

var _tag_value_ref      : ReactiveVariant = null
var _array_tag_refs     : Array[ReactiveVariant] = []
var _context_provider   : Callable = Callable()
var _is_deserializing   : bool = false
var _is_vector_field    : bool = false

func _init(default_value: Variant = null, initial_owner: Reactive = null, label: String = "ReactiveDynamicField") -> void:
    super._init(initial_owner, label)

    _is_vector_field = _is_array_like(default_value)

    source_type       = ReactiveInt.new(SourceType.CONSTANT, self, "source_type")
    constant_value    = ReactiveVariant.new(default_value, self, "constant_value")
    tag_binding        = ReactiveOpcUaTagBinding.new({}, self, "tag_binding")
    tag_array_binding   = ReactiveOpcUaTagArrayBinding.new(self, "tag_array_binding")
    script_source      = ReactiveString.new("", self, "script_source")
    resolved            = ReactiveVariant.new(default_value, self, "resolved")

    source_type.connect_self_changed(func(_s: ReactiveInt) -> void: _rebind())
    constant_value.connect_self_changed(func(_c: ReactiveVariant) -> void: _rebind())
    tag_binding.connect_any_changed_self(func(_t: ReactiveOpcUaTagBinding) -> void: _rebind())
    tag_array_binding.tag_bindings.connect_any_changed_self(func(_t) -> void: _rebind())
    script_source.connect_self_changed(func(_s: ReactiveString) -> void: _rebind())

func is_vector_field() -> bool:
    return _is_vector_field

static func _is_array_like(v: Variant) -> bool:
    return v is Array \
        or v is PackedFloat32Array or v is PackedFloat64Array \
        or v is PackedInt32Array or v is PackedInt64Array \
        or v is PackedStringArray or v is PackedByteArray \
        or v is PackedVector2Array or v is PackedVector3Array \
        or v is PackedColorArray

func _describe_value() -> String:
    return ""

func set_context_provider(provider: Callable) -> void:
    _context_provider = provider
    _rebind()

# ── Rebind orchestration ───────────────────────────────────────────────────

func _rebind() -> void:
    if _is_deserializing:
        return

    _unbind_tag()
    _unbind_tag_array()

    match source_type.value:
        SourceType.CONSTANT:
            resolved.value = constant_value.value
        SourceType.OPC_TAG:
            _bind_tag()
        SourceType.OPC_TAG_ARRAY:
            _bind_tag_array()
        SourceType.SCRIPT:
            _bind_script()

# ── Single OPC tag (scalar OR native array-typed node) ─────────────────────

func _resolve_tag() -> ReactiveOpcUaTag:
    var t: ReactiveOpcUaTagBinding = tag_binding
    if t.server_id.value.is_empty() or t.subscription_id.value.is_empty() or t.tag_id.value.is_empty():
        return null

    var project: ReactiveProject = AppState.current_project
    if project == null:
        return null

    var server: ReactiveOpcUaServer = project.opc_ua_servers.get_entry(t.server_id.value)
    if server == null:
        return null

    var subscription: ReactiveOpcUaSubscription = server.subscriptions.get_entry(t.subscription_id.value)
    if subscription == null:
        return null

    return subscription.tags.get_entry(t.tag_id.value)

func _bind_tag() -> void:
    var tag: ReactiveOpcUaTag = _resolve_tag()
    if tag == null:
        return

    _tag_value_ref = tag.value
    _tag_value_ref.connect_self_changed(_on_tag_value_changed)
    resolved.value = _normalize_vector(_tag_value_ref.value)

func _on_tag_value_changed(v: ReactiveVariant) -> void:
    resolved.value = _normalize_vector(v.value)

func _unbind_tag() -> void:
    if _tag_value_ref != null and _tag_value_ref.reactive_changed.is_connected(_on_tag_value_changed):
        _tag_value_ref.reactive_changed.disconnect(_on_tag_value_changed)
    _tag_value_ref = null

# ── Tag array binding: N heterogeneous tags → one Variant array ────────────

func _bind_tag_array() -> void:
    var bindings: Array = tag_array_binding.tag_bindings.value
    _array_tag_refs.resize(bindings.size())

    for i in bindings.size():
        var binding: ReactiveOpcUaTagBinding = bindings[i]
        var tag: ReactiveOpcUaTag = _resolve_tag_from_binding(binding)
        if tag == null:
            _array_tag_refs[i] = null
            continue

        var value_ref: ReactiveVariant = tag.value
        _array_tag_refs[i] = value_ref
        # Any zone updating triggers a full reassembly — keeps `resolved`
        # atomic (no torn reads on the consumer side) at the cost of
        # rebuilding the whole array per tick change. Acceptable for
        # typical flatness zone counts (< a few hundred).
        value_ref.connect_self_changed(func(_v: ReactiveVariant) -> void: _assemble_array_vector())

    _assemble_array_vector()

func _resolve_tag_from_binding(t: ReactiveOpcUaTagBinding) -> ReactiveOpcUaTag:
    if t.server_id.value.is_empty() or t.subscription_id.value.is_empty() or t.tag_id.value.is_empty():
        return null
    var project: ReactiveProject = AppState.current_project
    if project == null:
        return null
    var server: ReactiveOpcUaServer = project.opc_ua_servers.get_entry(t.server_id.value)
    if server == null:
        return null
    var subscription: ReactiveOpcUaSubscription = server.subscriptions.get_entry(t.subscription_id.value)
    if subscription == null:
        return null
    return subscription.tags.get_entry(t.tag_id.value)

func _assemble_array_vector() -> void:
    # Generic Variant array — each element keeps its native OPC type.
    # Consumers (e.g. FlatnessDisplay) are responsible for coercing to
    # float where numeric interpretation is required.
    var out: Array = []
    out.resize(_array_tag_refs.size())
    for i in _array_tag_refs.size():
        var ref: ReactiveVariant = _array_tag_refs[i]
        out[i] = ref.value if ref != null else null
    resolved.value = out

func _unbind_tag_array() -> void:
    for ref in _array_tag_refs:
        if ref != null:
            ref.disconnect_all_owned_by(self)  # see note below
    _array_tag_refs.clear()

# ── Script binding ───────────────────────────────────────────────────────────

func _bind_script() -> void:
    var vars: Dictionary = _context_provider.call() if _context_provider.is_valid() else {}
    var expr: Expression = Expression.new()

    if expr.parse(script_source.value, PackedStringArray(vars.keys())) != OK:
        _log("SCRIPT_PARSE_ERROR", expr.get_error_text())
        return

    var result: Variant = expr.execute(vars.values())
    if expr.has_execute_failed():
        _log("SCRIPT_EXECUTE_ERROR", expr.get_error_text())
        return

    resolved.value = result

# ── Vector helpers ───────────────────────────────────────────────────────────

func _normalize_vector(v: Variant) -> Variant:
    # Pass-through by design: coercing arbitrary Variant content to a
    # specific packed type here would silently corrupt non-numeric tags
    # (bool, String, Color, etc.). Type coercion, if needed, belongs at
    # the consuming widget, where the expected semantics are known.
    return v

# ── Serialization ─────────────────────────────────────────────────────────────

func deserialize(data: Variant) -> void:
    assert(data is Dictionary, "ReactiveDynamicField.deserialize expects a Dictionary")
    var d: Dictionary = data as Dictionary

    _is_deserializing = true
    source_type.value = d.get("source_type", SourceType.CONSTANT)

    if d.has("constant_value_b64"):
        var bytes: PackedByteArray = Marshalls.base64_to_raw(d["constant_value_b64"])
        constant_value.value = bytes_to_var(bytes)
    else:
        constant_value.value = d.get("constant_value", null)

    script_source.value = d.get("script_source", "")
    tag_binding.deserialize(d.get("tag_binding", {}))
    tag_array_binding.deserialize(d.get("tag_array_binding", []))
    _is_deserializing = false

    _rebind()
    _log("DESERIALIZED", _get_type_name())
    manually_emit()

func serialize() -> Variant:
    var out: Dictionary = {
        "source_type":       source_type.value,
        "script_source":     script_source.value,
        "tag_binding":       tag_binding.serialize(),
        "tag_array_binding": tag_array_binding.serialize(),
    }

    if _is_vector_field:
        # var_to_bytes() handles arbitrary Variant content generically —
        # Array of mixed types, PackedFloat32Array, nested structures, etc.
        out["constant_value_b64"] = Marshalls.raw_to_base64(var_to_bytes(constant_value.value))
    else:
        out["constant_value"] = constant_value.value

    return out
