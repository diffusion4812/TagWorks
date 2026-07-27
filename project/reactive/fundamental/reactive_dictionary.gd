class_name ReactiveDictionary
extends Reactive

var value: Dictionary:
    set(v):
        value = v
        _log("CHANGED", "<Dictionary keys=%d>" % v.size())
        reactive_changed.emit(self)

func _init(
    initial_value: Dictionary = {},
    initial_owner: Reactive = null,
    label: String = "",
    key_type: Variant.Type = TYPE_NIL,
    key_class_name: StringName = &"",
    key_script: Script = null,
    value_type: Variant.Type = TYPE_NIL,
    value_class_name: StringName = &"",
    value_script: Script = null
) -> void:
    super._init(initial_owner, label)

    # Build a natively typed Dictionary; Godot enforces types on every insert.
    value = Dictionary(
        initial_value,
        key_type, key_class_name, key_script,
        value_type, value_class_name, value_script
    )

func _describe_value() -> String:
    return "<Dictionary keys=%d>" % value.size()

func set_entry(key: Variant, val: Variant) -> void:
    value[key] = val  # Native type check happens here automatically
    _log("SET", "%s -> %s" % [key, val])
    reactive_changed.emit(self)

func erase_entry(key: Variant) -> bool:
    var erased: bool = value.erase(key)
    if erased:
        _log("ERASE", str(key))
        reactive_changed.emit(self)
    return erased

func clear() -> void:
    value.clear()
    _log("CLEARED", "")
    reactive_changed.emit(self)

func has_entry(key: Variant) -> bool:
    return value.has(key)

func get_entry(key: Variant, default: Variant = null) -> Variant:
    return value.get(key, default)

func keys() -> Array:
    return value.keys()

func values() -> Array:
    return value.values()

func size() -> int:
    return value.size()
