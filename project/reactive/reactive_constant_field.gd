class_name ReactiveConstantField
extends Reactive

enum SourceType { CONSTANT, SCRIPT }

var source_type    : ReactiveInt
var constant_value : ReactiveVariant
var script_source   : ReactiveString
var resolved         : ReactiveVariant

var _context_provider : Callable = Callable()
var _is_deserializing : bool = false
var _is_vector_field  : bool = false
var _vector_type      : int = TYPE_NIL  # typeof() of the original default value, used to rebuild the correct Packed*Array on load

func _init(default_value: Variant = null, initial_owner: Reactive = null, label: String = "ReactiveConstantField") -> void:
    super._init(initial_owner, label)

    _is_vector_field = _is_array_like(default_value)
    _vector_type      = typeof(default_value)

    source_type    = ReactiveInt.new(SourceType.CONSTANT, self, "source_type")
    constant_value = ReactiveVariant.new(default_value, self, "constant_value")
    script_source   = ReactiveString.new("", self, "script_source")
    resolved         = ReactiveVariant.new(default_value, self, "resolved")

    source_type.connect_self_changed(func(_s: ReactiveInt) -> void: _rebind())
    constant_value.connect_self_changed(func(_c: ReactiveVariant) -> void: _rebind())
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

    match source_type.value:
        SourceType.CONSTANT:
            resolved.value = constant_value.value
        SourceType.SCRIPT:
            _bind_script()

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

# ── Array <-> Dictionary helpers ────────────────────────────────────────────

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
        _: return arr  # TYPE_ARRAY (generic Variant array) or unknown

# ── Serialization ─────────────────────────────────────────────────────────────

func deserialize(data: Variant) -> void:
    assert(data is Dictionary, "ReactiveConstantField.deserialize expects a Dictionary")
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
    _is_deserializing = false

    _rebind()
    _log("DESERIALIZED", _get_type_name())
    manually_emit()

func serialize() -> Variant:
    var out: Dictionary = {
        "source_type":     source_type.value,
        "script_source":   script_source.value,
        "is_vector_field": _is_vector_field,
        "vector_type":      _vector_type,
    }

    if _is_vector_field:
        out["constant_value"] = _array_to_dict(constant_value.value)
    else:
        out["constant_value"] = ReactiveVariantCodec.encode_variant(constant_value.value)

    return out
