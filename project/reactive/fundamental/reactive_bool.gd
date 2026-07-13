class_name ReactiveBool
extends Reactive

var value: bool:
    set(v):
        if value == v:
            return
        value = v
        _log("CHANGED", str(v))
        reactive_changed.emit(self)

func _init(initial_value: bool = false, initial_owner: Reactive = null, label: String = "") -> void:
    super._init(initial_owner, label)
    value = initial_value

func _describe_value() -> String:
    return str(value)
