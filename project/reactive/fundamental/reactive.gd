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

func _propagate(_reactive: Reactive = null) -> void:
    _log("PROPAGATE", _describe_value())
    reactive_changed.emit(self)


func manually_emit() -> void:
    _log("MANUAL_EMIT", _describe_value())
    reactive_changed.emit(self)

# ── Debug Logging ─────────────────────────────────────────────────────────────

func _log(event: String, value_str: String = "") -> void:
    if not DEBUG:
        return
    var timestamp: String = "%010.4f" % (Time.get_ticks_msec() * 0.001)
    var chain:     String = _build_owner_chain()
    var msg:       String = "[%s] [REACTIVE] [%s] %s" % [timestamp, event, chain]
    if value_str != "":
        msg += " → %s" % value_str
    print(msg)


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
