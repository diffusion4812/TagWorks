class_name ReactiveArray
extends Reactive

# ── Value ─────────────────────────────────────────────────────────────────────

var value: Array:
    set(v):
        value = v
        _log("CHANGED", _describe_value())
        reactive_changed.emit(self)

# ── Init ──────────────────────────────────────────────────────────────────────

func _init(
    initial_value:  Array    = [],
    initial_owner:  Reactive = null,
    label:          String   = "ReactiveArray"
) -> void:
    super._init(initial_owner, label)
    value = initial_value

# ── Describe ──────────────────────────────────────────────────────────────────

func _describe_value() -> String:
    return "<Array size=%d>" % value.size()

# ── Read ──────────────────────────────────────────────────────────────────────

func get_at(i: int) -> Variant:
    return value[i]


func values() -> Array:
    return value

# ── Write ─────────────────────────────────────────────────────────────────────

func set_at(i: int, v: Variant) -> void:
    value[i] = v
    _log("SET_AT[%d]" % i, str(v))
    reactive_changed.emit(self)


func append(v: Variant) -> void:
    value.append(v)
    _log("APPEND", _describe_value())
    reactive_changed.emit(self)


func append_array(array: Array) -> void:
    value.append_array(array)
    _log("APPEND_ARRAY", _describe_value())
    reactive_changed.emit(self)


func assign(array: Array) -> void:
    value.assign(array)
    _log("ASSIGN", _describe_value())
    reactive_changed.emit(self)


func clear() -> void:
    value.clear()
    _log("CLEAR", _describe_value())
    reactive_changed.emit(self)


func erase(v: Variant) -> void:
    value.erase(v)
    _log("ERASE", _describe_value())
    reactive_changed.emit(self)


func insert(position: int, v: Variant) -> void:
    value.insert(position, v)
    _log("INSERT[%d]" % position, _describe_value())
    reactive_changed.emit(self)


func pop_at(index: int) -> Variant:
    var tmp: Variant = value.pop_at(index)
    _log("POP_AT[%d]" % index, _describe_value())
    reactive_changed.emit(self)
    return tmp


func pop_back() -> Variant:
    var tmp: Variant = value.pop_back()
    _log("POP_BACK", _describe_value())
    reactive_changed.emit(self)
    return tmp


func pop_front() -> Variant:
    var tmp: Variant = value.pop_front()
    _log("POP_FRONT", _describe_value())
    reactive_changed.emit(self)
    return tmp


func push_back(v: Variant) -> void:
    append(v)


func remove_at(index: int) -> void:
    value.remove_at(index)
    _log("REMOVE_AT[%d]" % index, _describe_value())
    reactive_changed.emit(self)


func shuffle() -> void:
    value.shuffle()
    _log("SHUFFLE", _describe_value())
    reactive_changed.emit(self)


func sort() -> void:
    value.sort()
    _log("SORT", _describe_value())
    reactive_changed.emit(self)


func sort_custom(callable: Callable) -> void:
    value.sort_custom(callable)
    _log("SORT_CUSTOM", _describe_value())
    reactive_changed.emit(self)
