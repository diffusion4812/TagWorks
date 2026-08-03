class_name ReactiveDictionary
extends Reactive

var value: Dictionary:
    set(v):
        value = v
        _log("CHANGED", "<Dictionary keys=%d>" % v.size())
        reactive_changed.emit(self)

func _init(
    initial_value: Dictionary = {},
    initial_owner: Reactive = null,
    label: String = "",
    key_type: Variant.Type = TYPE_NIL,
    key_class_name: StringName = &"",
    key_script: Script = null,
    value_type: Variant.Type = TYPE_NIL,
    value_class_name: StringName = &"",
    value_script: Script = null
) -> void:
    super._init(initial_owner, label)
    value = Dictionary(
        initial_value,
        key_type, key_class_name, key_script,
        value_type, value_class_name, value_script
    )

func _describe_value() -> String:
    return "<Dictionary keys=%d>" % value.size()

# ── Serialization ─────────────────────────────────────────────────────────────

## Wraps each Reactive entry with a "__type" tag so it can be reconstructed
## later with zero external schema knowledge. Plain, non-Reactive entries
## (raw primitives) pass through unchanged.
func serialize() -> Variant:
    var out: Dictionary = {}
    for key: Variant in value.keys():
        var raw: Variant = value[key]
        if raw is Reactive:
            out[key] = {
                "__type": (raw as Reactive)._get_type_name(),
                "data":   (raw as Reactive).serialize(),
            }
        else:
            out[key] = raw
    return out

## Restores entries from `data`. For each tagged entry:
##   1. If an existing Reactive instance of the SAME type already sits at
##      this key (pre-built by a View's schema), reuse it in place —
##      preserves any external references/signal connections to it.
##   2. Otherwise, reconstruct the correct subclass from the "__type" tag
##      via ReactiveTypeRegistry — no external schema required at all.
func deserialize(data: Variant) -> void:
    assert(data is Dictionary, "ReactiveDictionary.deserialize expects a Dictionary")
    var d: Dictionary = data as Dictionary

    for key: Variant in d.keys():
        var raw: Variant = d[key]

        if raw is Dictionary and (raw as Dictionary).has("__type"):
            var type_name: String   = (raw as Dictionary)["__type"]
            var payload:   Variant  = (raw as Dictionary)["data"]
            var existing:  Variant  = value.get(key)

            var instance: Reactive
            if existing is Reactive and (existing as Reactive)._get_type_name() == type_name:
                instance = existing as Reactive  # reuse — keeps external refs valid
            else:
                instance = ReactiveTypeRegistry.create(type_name)
                if instance == null:
                    push_warning("ReactiveDictionary: could not reconstruct key '%s'" % key)
                    continue
                instance.owner = self

            instance.deserialize(payload)
            value[key] = instance
        else:
            value[key] = raw  # plain, non-Reactive-wrapped entry

    _log("DESERIALIZED", "<Dictionary keys=%d>" % value.size())
    reactive_changed.emit(self)

# ── Mutators (unchanged) ──────────────────────────────────────────────────────

func set_entry(key: Variant, val: Variant) -> void:
    value[key] = val
    _log("SET", "%s -> %s" % [key, val])
    reactive_changed.emit(self)

func erase_entry(key: Variant) -> bool:
    var erased: bool = value.erase(key)
    if erased:
        _log("ERASE", str(key))
        reactive_changed.emit(self)
    return erased

func clear() -> void:
    value.clear()
    _log("CLEARED", "")
    reactive_changed.emit(self)

func has_entry(key: Variant) -> bool:
    return value.has(key)

func get_entry(key: Variant, default: Variant = null) -> Variant:
    return value.get(key, default)

func keys() -> Array:
    return value.keys()

func values() -> Array:
    return value.values()

func size() -> int:
    return value.size()
