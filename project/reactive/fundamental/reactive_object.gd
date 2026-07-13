class_name ReactiveObject
extends Reactive

var value: Object:
    set(v):
        if value != null and value is Reactive:
            value.reactive_changed.disconnect(_propagate)
        value = v
        if value != null and value is Reactive:
            value.reactive_changed.connect(_propagate)
        _log("CHANGED", _describe_value())
        reactive_changed.emit(self)

func _init(initial_value: Object = null, initial_owner: Reactive = null, label: String = "") -> void:
    super._init(initial_owner, label)
    value = initial_value

func _describe_value() -> String:
    if value == null:
        return "<null>"
    return "<%s>" % value.get_class()
