class_name ReactiveDictionary
extends Reactive

var value: Dictionary:
    set(v):
        value = v
        _log("CHANGED", "<Dictionary keys=%d>" % v.size())
        reactive_changed.emit(self)

func _init(initial_value: Dictionary = {}, initial_owner: Reactive = null, label: String = "") -> void:
    super._init(initial_owner, label)
    value = initial_value

func _describe_value() -> String:
    return "<Dictionary keys=%d>" % value.size()
