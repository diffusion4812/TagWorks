class_name ReactiveFloat
extends Reactive

var value: float:
    set(v):
        if value == v:
            return
        value = v
        reactive_changed.emit(self)

func _init(initial_value: float = 0.0, initial_owner: Reactive = null) -> void:
    super._init(initial_owner)
    value = initial_value
