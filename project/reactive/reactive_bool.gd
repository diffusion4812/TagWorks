class_name ReactiveBool
extends Reactive

func _init(initial_value : bool, initial_owner : Reactive = null) -> void:
    super._init(initial_owner)
    value = initial_value

var value : bool:
    set(v):
        value = v
        reactive_changed.emit(self)
        return value
