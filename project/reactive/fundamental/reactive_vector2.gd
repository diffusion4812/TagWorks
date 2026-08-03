class_name ReactiveVector2
extends Reactive

var value: Vector2:
    set(v):
        if value == v:
            return
        value = v
        _log("CHANGED", str(v))
        reactive_changed.emit(self)

func _init(initial_value: Vector2 = Vector2.ZERO, initial_owner: Reactive = null, label: String = "") -> void:
    super._init(initial_owner, label)
    value = initial_value

func _describe_value() -> String:
    return str(value)

# ── Serialization ─────────────────────────────────────────────────────────────

func serialize() -> Variant:
    return {"x": value.x, "y": value.y}

func deserialize(data: Variant) -> void:
    assert(data is Dictionary, "ReactiveVector2.deserialize expects a Dictionary with x/y keys")
    var d: Dictionary = data as Dictionary
    value = Vector2(d.get("x", 0.0), d.get("y", 0.0))
    _log("DESERIALIZED", str(value))
