class_name ReactiveDict
extends Reactive

var value: Dictionary:
    set(v):
        value = v
        reactive_changed.emit(self)

func _init(initial_value: Dictionary = {}, initial_owner: Reactive = null) -> void:
    super._init(initial_owner)
    value = initial_value
