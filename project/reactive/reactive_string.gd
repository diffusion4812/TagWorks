class_name ReactiveString
extends Reactive

var value: String:
    set(v):
        if value == v:
            return
        value = v
        _log("CHANGED", '"%s"' % v)
        reactive_changed.emit(self)

func _init(initial_value: String = "", initial_owner: Reactive = null, label: String = "") -> void:
    super._init(initial_owner, label)
    value = initial_value

func _describe_value() -> String:
    return '"%s"' % value
