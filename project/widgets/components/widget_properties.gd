class_name WidgetProperties
extends RefCounted

## Emitted whenever any property value changes.
signal changed(prop: String, value: Variant)

## Internal property store.
var _props: Dictionary = {}

# ── Registration ──────────────────────────────────────────────────────────────

## Register a property with an initial value and an optional setter callable.
## The setter is invoked immediately with the initial value and on every change.
func register(prop: String, initial: Variant, setter: Callable = Callable()) -> void:
    _props[prop] = {
        "value":  initial,
        "setter": setter
    }
    if setter.is_valid():
        setter.call(initial)


## Returns the current value of a registered property.
func get_value(prop: String) -> Variant:
    return _props[prop]["value"] if _props.has(prop) else null

# ── Application ───────────────────────────────────────────────────────────────

## Receive a property change from PropertyPanel.
## Routes the new value to the registered setter and emits changed.
func apply(prop: String, value: Variant) -> void:
    if not _props.has(prop):
        push_warning("WidgetProperties: unknown property '%s'" % prop)
        return
    _props[prop]["value"] = value
    var setter: Callable = _props[prop]["setter"]
    if setter.is_valid():
        setter.call(value)
    changed.emit(prop, value)

## Re-invokes every registered setter with its current stored value.
## Called when the Apply button is pressed in PropertyPanel to guarantee
## widget state is consistent with the panel's current values.
func reapply() -> void:
    for prop in _props:
        var setter: Callable = _props[prop]["setter"]
        if setter.is_valid():
            setter.call(_props[prop]["value"])

# ── Panel integration ─────────────────────────────────────────────────────────

## Called by PropertyPanel — satisfies the on_property_changed interface.
func on_property_changed(prop: String, value: Variant) -> void:
    apply(prop, value)
