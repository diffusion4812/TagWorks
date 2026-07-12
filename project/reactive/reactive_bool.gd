class_name ReactiveBool
extends Reactive

var value: bool:
    set(v):
        if value == v:
            return
        value = v
        reactive_changed.emit(self)

func _init(initial_value: bool = false, initial_owner: Reactive = null) -> void:
    super._init(initial_owner)
    value = initial_value
