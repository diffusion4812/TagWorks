# autoloads/signal_logger.gd
extends Node

const ENABLED:       bool   = true
const LOG_TO_FILE:   bool   = false
const LOG_FILE_PATH: String = "user://signal_log.txt"

signal logger_ready

var is_ready:  bool       = false
var _log_file: FileAccess = null

## Tracks emission and handler call counts per signal.
## Structure: { "BusName.signal_name": { "emitted": int, "handlers": { "handler_desc": int } } }
var _stats: Dictionary = {}

var _poll_timer := Timer.new()

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    if not ENABLED:
        is_ready = true
        logger_ready.emit()
        return

    if LOG_TO_FILE:
        _log_file = FileAccess.open(LOG_FILE_PATH, FileAccess.WRITE)

    _connect_bus(IntentBus, "IntentBus")

    _write("SignalLogger initialised. Monitoring EventBus and IntentBus.")

    # Trigger an immediate scan once all scene nodes have finished _ready()
    get_tree().root.ready.connect(_on_scene_tree_ready, CONNECT_ONE_SHOT)

    # Continue polling for connections made dynamically after scene init
    _poll_timer.wait_time = 1.0
    _poll_timer.autostart = true
    _poll_timer.timeout.connect(_poll_late_connections)
    add_child(_poll_timer)

    is_ready = true
    logger_ready.emit()


func _exit_tree() -> void:
    if _log_file != null:
        _log_file.close()


## Fires once after all scene nodes have completed their _ready() calls.
## This is the earliest point at which all bus connections are guaranteed
## to be registered.
func _on_scene_tree_ready() -> void:
    _write("Scene tree ready — scanning for late connections.")
    _poll_late_connections()

# ── Awaitable Helper ──────────────────────────────────────────────────────────

## Awaitable helper. Returns immediately if already ready, otherwise
## suspends the caller until logger_ready is emitted.
func wait_until_ready() -> void:
    if not is_ready:
        await logger_ready

# ── Timestamp Helper ──────────────────────────────────────────────────────────
func _timestamp() -> String:
    return "%010.4f" % (Time.get_ticks_msec() * 0.001)

# ── Bus Connection ────────────────────────────────────────────────────────────

func _connect_bus(bus: Node, bus_name: String) -> void:
    for sig in bus.get_signal_list():
        var signal_name: String = sig["name"]
        var arg_count:   int    = sig["args"].size()
        var full_name:   String = "%s.%s" % [bus_name, signal_name]

        _stats[full_name] = { "emitted": 0, "handlers": {} }

        var existing: Array = bus.get_signal_connection_list(signal_name)
        for conn: Dictionary in existing:
            var original_callable: Callable = conn["callable"]
            var handler_desc:      String   = _describe_callable(original_callable)

            _stats[full_name]["handlers"][handler_desc] = 0
            _write("[%s] [CONNECT] %s → %s" % [_timestamp(), full_name, handler_desc])

            bus.disconnect(signal_name, original_callable)

            var wrapped := _wrap_handler(original_callable, full_name, handler_desc, arg_count)
            bus.connect(signal_name, wrapped)

        var emit_logger := _make_emit_logger(bus_name, signal_name, arg_count)
        bus.connect(signal_name, emit_logger)

# ── Late Connection Polling ───────────────────────────────────────────────────

func _poll_late_connections() -> void:
    _scan_for_late_connections(IntentBus, "IntentBus")


## Scans all tracked signals for newly added connections that have not yet
## been wrapped, and wraps them automatically.
func _scan_for_late_connections(bus: Node, bus_name: String) -> void:
    for sig in bus.get_signal_list():
        var signal_name: String = sig["name"]
        var arg_count:   int    = sig["args"].size()
        var full_name:   String = "%s.%s" % [bus_name, signal_name]

        if not _stats.has(full_name):
            _stats[full_name] = { "emitted": 0, "handlers": {} }

        var connections: Array = bus.get_signal_connection_list(signal_name)
        for conn: Dictionary in connections:
            var callable:     Callable = conn["callable"]
            var handler_desc: String   = _describe_callable(callable)

            if _stats[full_name]["handlers"].has(handler_desc):
                continue
            if callable.get_object() == self:
                continue

            _stats[full_name]["handlers"][handler_desc] = 0
            _write("[%s] [CONNECT] %s → %s (late)" % [_timestamp(), full_name, handler_desc])

            bus.disconnect(signal_name, callable)
            var wrapped := _wrap_handler(callable, full_name, handler_desc, arg_count)
            bus.connect(signal_name, wrapped)

# ── Handler Wrapping ──────────────────────────────────────────────────────────

## Wraps an existing downstream callable so its invocation is logged.
func _wrap_handler(
    original:     Callable,
    full_name:    String,
    handler_desc: String,
    arg_count:    int
) -> Callable:
    match arg_count:
        0:
            return func() -> void:
                _stats[full_name]["handlers"][handler_desc] += 1
                _write("[%s] [HANDLER] %s → %s called" % [_timestamp(), full_name, handler_desc])
                original.call()
        1:
            return func(a: Variant) -> void:
                _stats[full_name]["handlers"][handler_desc] += 1
                _write("[%s] [HANDLER] %s → %s called(%s)" % [_timestamp(), full_name, handler_desc, str(a)])
                original.call(a)
        2:
            return func(a: Variant, b: Variant) -> void:
                _stats[full_name]["handlers"][handler_desc] += 1
                _write("[%s] [HANDLER] %s → %s called(%s, %s)" % [_timestamp(), full_name, handler_desc, str(a), str(b)])
                original.call(a, b)
        3:
            return func(a: Variant, b: Variant, c: Variant) -> void:
                _stats[full_name]["handlers"][handler_desc] += 1
                _write("[%s] [HANDLER] %s → %s called(%s, %s, %s)" % [_timestamp(), full_name, handler_desc, str(a), str(b), str(c)])
                original.call(a, b, c)
        _:
            push_warning("SignalLogger: '%s' has >3 args — handler wrapping skipped." % full_name)
            return original


## Returns a callable that logs the emission of a signal.
func _make_emit_logger(bus_name: String, signal_name: String, arg_count: int) -> Callable:
    var full_name := "%s.%s" % [bus_name, signal_name]
    match arg_count:
        0:
            return func() -> void:
                _log_emission(full_name, [])
        1:
            return func(a: Variant) -> void:
                _log_emission(full_name, [a])
        2:
            return func(a: Variant, b: Variant) -> void:
                _log_emission(full_name, [a, b])
        3:
            return func(a: Variant, b: Variant, c: Variant) -> void:
                _log_emission(full_name, [a, b, c])
        _:
            push_warning("SignalLogger: '%s' has >3 args — emission args will not be logged." % full_name)
            return func() -> void:
                _log_emission(full_name, [])

# ── Runtime Connection Watching ───────────────────────────────────────────────

## Call this to register and wrap a connection made after _ready().
## Usage: SignalLogger.watch_connection(EventBus, "widget_selected", my_callable)
func watch_connection(bus: Node, signal_name: String, original: Callable) -> Callable:
    if not ENABLED:
        return original

    var bus_name:     String = _get_bus_name(bus)
    var full_name:    String = "%s.%s" % [bus_name, signal_name]
    var arg_count:    int    = _get_signal_arg_count(bus, signal_name)
    var handler_desc: String = _describe_callable(original)

    if not _stats.has(full_name):
        _stats[full_name] = { "emitted": 0, "handlers": {} }

    _stats[full_name]["handlers"][handler_desc] = 0
    _write("[%s] [CONNECT] %s → %s" % [_timestamp(), full_name, handler_desc])

    return _wrap_handler(original, full_name, handler_desc, arg_count)

# ── Logging ───────────────────────────────────────────────────────────────────

func _log_emission(full_name: String, args: Array) -> void:
    if _stats.has(full_name):
        _stats[full_name]["emitted"] += 1

    var arg_str   := ", ".join(args.map(func(a: Variant) -> String: return str(a)))
    var entry     := "[%s] [EMIT]    %s(%s)" % [_timestamp(), full_name, arg_str]
    _write(entry)


func _write(entry: String) -> void:
    print(entry)
    if _log_file != null:
        _log_file.store_line(entry)
        _log_file.flush()

# ── Stats Summary ─────────────────────────────────────────────────────────────

## Prints a formatted summary of all tracked signals, emission counts,
## registered handlers, and handler call counts.
func print_summary() -> void:
    _write("═══════════════ SIGNAL LOGGER SUMMARY ═══════════════")
    for full_name: String in _stats.keys():
        var entry:    Dictionary = _stats[full_name]
        var emitted:  int        = entry["emitted"]
        var handlers: Dictionary = entry["handlers"]
        _write("  %s — emitted: %d" % [full_name, emitted])
        if handlers.is_empty():
            _write("    (no handlers registered)")
        else:
            for handler_desc: String in handlers.keys():
                _write("    → %s — called: %d" % [handler_desc, handlers[handler_desc]])
    _write("═════════════════════════════════════════════════════")

# ── Utilities ─────────────────────────────────────────────────────────────────

func _describe_callable(c: Callable) -> String:
    var obj    := c.get_object()
    var method := c.get_method()

    if obj == null:
        return "<lambda>" if method.is_empty() else method

    var name_variant: Variant = obj.get("name")
    var obj_name: String      = name_variant as String if name_variant != null else obj.get_class()

    return "%s::%s" % [obj_name, method] if not method.is_empty() else "%s::<lambda>" % obj_name


func _get_bus_name(bus: Node) -> String:
    if bus == IntentBus:
        return "IntentBus"
    return bus.name


func _get_signal_arg_count(bus: Node, signal_name: String) -> int:
    for sig in bus.get_signal_list():
        if sig["name"] == signal_name:
            return sig["args"].size()
    return 0
