class_name ReactiveVariant
extends Reactive

var value: Variant:
    set(v):
        if value == v:
            return
        value = v
        _log("CHANGED", str(v))
        reactive_changed.emit(self)

func _init(initial_value: Variant = null, initial_owner: Reactive = null, label: String = "") -> void:
    super._init(initial_owner, label)
    value = initial_value

func _describe_value() -> String:
    if value == null:
        return "null"
    if value.has_method("_describe_value"):
        return value._describe_value()
    return str(value)
