class_name ReactiveDynamicField
extends Reactive

enum SourceType { CONSTANT, OPC_TAG, OPC_TAG_ARRAY, SCRIPT }

var source_type         : ReactiveInt
var constant_value      : ReactiveVariant
var tag_binding         : ReactiveOpcUaTagBinding
var tag_array_binding   : ReactiveOpcUaTagArrayBinding
var script_source       : ReactiveString
var resolved            : ReactiveVariant

var _tag_value_ref      : ReactiveVariant = null
var _array_tag_refs     : Array[ReactiveVariant] = []
var _array_tag_callables: Array[Callable] = []
var _context_provider   : Callable = Callable()
var _is_deserializing   : bool = false
var _is_vector_field    : bool = false
var _vector_type        : int = TYPE_NIL

func _init(default_value: Variant = null, initial_owner: Reactive = null, label: String = "ReactiveDynamicField") -> void:
    super._init(initial_owner, label)

    _is_vector_field = _is_array_like(default_value)
    _vector_type      = typeof(default_value)

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
    _array_tag_callables.resize(bindings.size())

    for i in bindings.size():
        var binding: ReactiveOpcUaTagBinding = bindings[i]
        var tag: ReactiveOpcUaTag = _resolve_tag_from_binding(binding)
        if tag == null:
            _array_tag_refs[i] = null
            _array_tag_callables[i] = Callable()
            continue

        var value_ref: ReactiveVariant = tag.value
        _array_tag_refs[i] = value_ref

        # Store the exact bound Callable so _unbind_tag_array() can
        # disconnect precisely this connection later — Godot has no
        # built-in "disconnect everything owned by X" helper, so this
        # must be tracked manually rather than relying on introspection.
        var callable: Callable = func(_v: ReactiveVariant) -> void: _assemble_array_vector()
        _array_tag_callables[i] = callable
        value_ref.connect_self_changed(callable)

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
    # Intentionally left as a generic Array (never coerced via
    # rebuild_typed_array/_vector_type): each zone tag is an independent
    # OPC subscription and may resolve to a different native type
    # (float, bool, String, or null if unresolved). Forcing this into the
    # field's nominal Packed*Array type would silently corrupt or throw
    # on any non-uniform tag result. Consumers (e.g. FlatnessDisplay) are
    # expected to coerce per-element as needed.
    var out: Array = []
    out.resize(_array_tag_refs.size())
    for i in _array_tag_refs.size():
        var ref: ReactiveVariant = _array_tag_refs[i]
        out[i] = ref.value if ref != null else null
    resolved.value = out

func _unbind_tag_array() -> void:
    for i in _array_tag_refs.size():
        var ref: ReactiveVariant = _array_tag_refs[i]
        var callable: Callable = _array_tag_callables[i] if i < _array_tag_callables.size() else Callable()
        if ref != null and callable.is_valid() and ref.reactive_changed.is_connected(callable):
            ref.reactive_changed.disconnect(callable)

    _array_tag_refs.clear()
    _array_tag_callables.clear()

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
    return v

func _array_to_dict(v: Variant) -> Dictionary:
    var dict: Dictionary = {}
    var arr: Array = Array(v) if v != null else []
    for i in arr.size():
        dict[str(i)] = ReactiveVariantCodec.encode_variant(arr[i])
    return dict

func _dict_to_array(d: Dictionary) -> Variant:
    var keys: Array = d.keys()
    keys.sort_custom(func(a, b): return int(a) < int(b))

    var arr: Array = []
    for k in keys:
        arr.append(ReactiveVariantCodec.decode_variant(d[k]))

    match _vector_type:
        TYPE_PACKED_FLOAT32_ARRAY: return PackedFloat32Array(arr)
        TYPE_PACKED_FLOAT64_ARRAY: return PackedFloat64Array(arr)
        TYPE_PACKED_INT32_ARRAY:   return PackedInt32Array(arr)
        TYPE_PACKED_INT64_ARRAY:   return PackedInt64Array(arr)
        TYPE_PACKED_STRING_ARRAY:  return PackedStringArray(arr)
        TYPE_PACKED_COLOR_ARRAY:   return PackedColorArray(arr)
        TYPE_PACKED_VECTOR2_ARRAY: return PackedVector2Array(arr)
        TYPE_PACKED_VECTOR3_ARRAY: return PackedVector3Array(arr)
        TYPE_PACKED_BYTE_ARRAY:    return PackedByteArray(arr)
        _: return arr

    match _vector_type:
        TYPE_PACKED_FLOAT32_ARRAY: return PackedFloat32Array(arr)
        TYPE_PACKED_FLOAT64_ARRAY: return PackedFloat64Array(arr)
        TYPE_PACKED_INT32_ARRAY:   return PackedInt32Array(arr)
        TYPE_PACKED_INT64_ARRAY:   return PackedInt64Array(arr)
        TYPE_PACKED_STRING_ARRAY:  return PackedStringArray(arr)
        TYPE_PACKED_COLOR_ARRAY:   return PackedColorArray(arr)
        TYPE_PACKED_VECTOR2_ARRAY: return PackedVector2Array(arr)
        TYPE_PACKED_VECTOR3_ARRAY: return PackedVector3Array(arr)
        TYPE_PACKED_BYTE_ARRAY:    return PackedByteArray(arr)
        _: return arr

## Converts a plain Array back into the field's original native storage
## type (PackedFloat32Array, PackedColorArray, generic Array, etc.), based
## on the type captured from the constructor's default_value. Use this
## instead of hardcoding a specific Packed*Array constructor anywhere a
## plain Array needs to be written back to constant_value.
func rebuild_typed_array(arr: Array) -> Variant:
    match _vector_type:
        TYPE_PACKED_FLOAT32_ARRAY: return PackedFloat32Array(arr)
        TYPE_PACKED_FLOAT64_ARRAY: return PackedFloat64Array(arr)
        TYPE_PACKED_INT32_ARRAY:   return PackedInt32Array(arr)
        TYPE_PACKED_INT64_ARRAY:   return PackedInt64Array(arr)
        TYPE_PACKED_STRING_ARRAY:  return PackedStringArray(arr)
        TYPE_PACKED_COLOR_ARRAY:   return PackedColorArray(arr)
        TYPE_PACKED_VECTOR2_ARRAY: return PackedVector2Array(arr)
        TYPE_PACKED_VECTOR3_ARRAY: return PackedVector3Array(arr)
        TYPE_PACKED_BYTE_ARRAY:    return PackedByteArray(arr)
        _: return arr  # TYPE_ARRAY (generic Variant array) or unknown

# ── Serialization ─────────────────────────────────────────────────────────────

func deserialize(data: Variant) -> void:
    assert(data is Dictionary, "ReactiveDynamicField.deserialize expects a Dictionary")
    var d: Dictionary = data as Dictionary

    _is_deserializing = true
    source_type.value = d.get("source_type", SourceType.CONSTANT)

    _is_vector_field = d.get("is_vector_field", _is_vector_field)
    _vector_type       = d.get("vector_type", _vector_type)

    var stored_value: Variant = d.get("constant_value", null)
    if _is_vector_field and stored_value is Dictionary:
        constant_value.value = _dict_to_array(stored_value)
    else:
        constant_value.value = ReactiveVariantCodec.decode_variant(stored_value)

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
        "is_vector_field":   _is_vector_field,
        "vector_type":        _vector_type,
        "tag_binding":       tag_binding.serialize(),
        "tag_array_binding": tag_array_binding.serialize(),
    }

    if _is_vector_field:
        out["constant_value"] = _array_to_dict(constant_value.value)
    else:
        out["constant_value"] = ReactiveVariantCodec.encode_variant(constant_value.value)

    return out
