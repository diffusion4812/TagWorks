# reactive/reactive.gd
class_name Reactive
extends Resource

# ── Debug ─────────────────────────────────────────────────────────────────────

const DEBUG: bool = true

var _label: String = ""

# ── Owner ─────────────────────────────────────────────────────────────────────

var owner: Reactive:
    set(v):
        if owner != null:
            reactive_changed.disconnect(owner._propagate)
        owner = v
        if owner != null:
            reactive_changed.connect(owner._propagate)

signal reactive_changed(reactive: Variant)

# ── Init ──────────────────────────────────────────────────────────────────────

func _init(initial_owner: Reactive = null, label: String = "") -> void:
    _label = label
    owner  = initial_owner

# ── Propagation ───────────────────────────────────────────────────────────────

func _propagate(reactive: Reactive = null) -> void:
    var origin: Reactive = reactive if reactive != null else self
    _log("PROPAGATE", _describe_value(), origin)
    reactive_changed.emit(origin)

func manually_emit() -> void:
    _log("MANUAL_EMIT", _describe_value(), self)
    reactive_changed.emit(self)

# ── Debug Logging ─────────────────────────────────────────────────────────────

func _log(event: String, value_str: String = "", origin: Reactive = null) -> void:
    if not DEBUG:
        return
    var timestamp: String = "%010.4f" % (Time.get_ticks_msec() * 0.001)
    var chain:     String = _build_owner_chain()
    var self_type: String = "(%s)" % _get_type_name()
    var msg:       String = "[%s] [REACTIVE] [%s] %s%s" % [timestamp, event, chain, self_type]

    if value_str != "":
        msg += " → %s" % value_str

    if origin != null and origin != self:
        msg += "  [origin: %s <%s>]" % [origin._build_owner_chain(), origin._get_type_name()]

    print(msg)

## Returns the GDScript `class_name` (e.g. "ReactiveTag") if available,
## falling back to the native engine class (e.g. "Resource") otherwise.
func _get_type_name() -> String:
    var script: Script = get_script()
    if script != null:
        var global_name: String = script.get_global_name()
        if global_name != "":
            return global_name
    return get_class()

## Builds a dot-separated owner chain for tracing propagation context.
## e.g. "current_project.pages.page_name"
func _build_owner_chain() -> String:
    var parts: Array[String] = []
    var current: Reactive    = self

    while current != null:
        var part: String = current._label if current._label != "" else current.get_class()
        parts.push_front(part)
        current = current.owner

    return ".".join(parts)

## Override in subclasses to return a meaningful string for the current value.
func _describe_value() -> String:
    return ""

## Fires callback(origin) for every change in this subtree,
## whether it originates from this node itself or any descendant.
## Useful for coarse-grained tracking like dirty flags.
func connect_any_changed(callback: Callable) -> Callable:
    var wrapper: Callable = func(origin: Reactive) -> void:
        if callback.is_valid():
            callback.call(origin)
    reactive_changed.connect(wrapper)
    return wrapper

## Fires callback(self) only when this exact node changed directly
## (mirrors the old, pre-Option-A behavior — safe drop-in replacement
## for existing `reactive_changed.connect(...)` call sites).
func connect_self_changed(callback: Callable) -> Callable:
    var wrapper: Callable = func(origin: Reactive) -> void:
        if origin == self and callback.is_valid():
            callback.call(self)
    reactive_changed.connect(wrapper)
    return wrapper

## Fires callback(origin) whenever any descendant changes,
## passing the true, deepest originating Reactive.
## Excludes changes to `self` directly.
func connect_descendant_changed(callback: Callable) -> Callable:
    var wrapper: Callable = func(origin: Reactive) -> void:
        if origin != self and callback.is_valid():
            callback.call(origin)
    reactive_changed.connect(wrapper)
    return wrapper

## Fires callback(origin) whenever a change anywhere in this subtree
## originates from an instance of the given type — useful for listening
## at a high-level root (e.g. AppState.current_project) for a specific
## reactive type located anywhere beneath it (e.g. ReactiveTag).
func connect_changed_of_type(type: Variant, callback: Callable) -> Callable:
    var wrapper: Callable = func(origin: Reactive) -> void:
        if not callback.is_valid():
            return
        var current: Reactive = origin
        while current != null:
            if is_instance_of(current, type):
                callback.call(current)
                return
            current = current.owner
    reactive_changed.connect(wrapper)
    return wrapper
