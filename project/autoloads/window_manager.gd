# WindowManager.gd
extends Node

const WINDOW_SCENES = {
    "script_editor": preload("res://scenes/dialogs/script_editor/script_editor.tscn"),
    "opc_ua_connection_dialog": preload("res://scenes/dialogs/opc_ua_connection_dialog/opc_ua_connection_dialog.tscn"),
    "browse_nodes": preload("res://scenes/dialogs/browse_nodes/browse_nodes.tscn")
}

## Keep track of active window instances in memory
var active_windows: Dictionary = {}

## Tracks per-call signal connections made via the "callbacks" option,
## keyed by window_key, so they can be cleanly disconnected on reuse/close.
## { window_key: [ { "signal": String, "callable": Callable }, ... ] }
var _dynamic_connections: Dictionary = {}

## Opens (or refocuses) a window.
##
## options:
##   "params"    : Dictionary of properties to set on the instance
##                 (e.g. { "file_mode": FileDialog.FILE_MODE_OPEN_FILE })
##   "callbacks" : Dictionary of signal_name -> Callable, connected as
##                 ONE_SHOT so repeated opens don't stack handlers
##   "size"      : Vector2i popup size override
##   "force_new" : bool, bypasses the cached instance and creates a new one
func open_window(window_key: String, options: Dictionary = {}) -> Node:
    var params: Dictionary = options.get("params", {})
    var callbacks: Dictionary = options.get("callbacks", {})
    var force_new: bool = options.get("force_new", false)
    var auto_popup: bool = options.get("auto_popup", true)

    var window_instance: Node = null

    if not force_new and active_windows.has(window_key) and is_instance_valid(active_windows[window_key]):
        window_instance = active_windows[window_key]
        _bring_to_front(window_instance)
        _clear_dynamic_connections(window_key)
    else:
        if window_key == "filedialog":
            window_instance = FileDialog.new()
            window_instance.access = FileDialog.ACCESS_FILESYSTEM
            window_instance.file_mode = FileDialog.FILE_MODE_OPEN_FILE
        else:
            if not WINDOW_SCENES.has(window_key):
                printerr("Window key not found: ", window_key)
                return null
            window_instance = WINDOW_SCENES[window_key].instantiate()

        get_tree().root.add_child(window_instance)
        active_windows[window_key] = window_instance

        if window_instance.has_signal("close_requested"):
            window_instance.close_requested.connect(func(): close_window(window_key))
        elif window_instance.has_signal("canceled"):
            window_instance.canceled.connect(func(): close_window(window_key))

    for prop_name: String in params.keys():
        if prop_name in window_instance:
            window_instance.set(prop_name, params[prop_name])

    _dynamic_connections[window_key] = []
    for signal_name: String in callbacks.keys():
        if window_instance.has_signal(signal_name):
            var callable: Callable = callbacks[signal_name]
            window_instance.connect(signal_name, callable, CONNECT_ONE_SHOT)
            _dynamic_connections[window_key].append({"signal": signal_name, "callable": callable})
        else:
            printerr("Signal not found on window '%s': %s" % [window_key, signal_name])

    if auto_popup and window_instance is Window:
        window_instance.popup_centered(options.get("size", Vector2i(800, 600)))

    return window_instance

## Brings an already-active window instance to the foreground.
## Window nodes use grab_focus() (there is no move_to_front() on Window).
## Control-based "windows" are re-parented to the end of their sibling
## list so they render/draw on top within their parent container.
func _bring_to_front(window_instance: Node) -> void:
    if window_instance is Window:
        window_instance.grab_focus()
    elif window_instance is Control:
        var parent: Node = window_instance.get_parent()
        if parent != null:
            parent.move_child(window_instance, parent.get_child_count() - 1)

func _clear_dynamic_connections(window_key: String) -> void:
    if not _dynamic_connections.has(window_key):
        return
    var win: Node = active_windows.get(window_key)
    if is_instance_valid(win):
        for conn: Dictionary in _dynamic_connections[window_key]:
            if win.is_connected(conn["signal"], conn["callable"]):
                win.disconnect(conn["signal"], conn["callable"])
    _dynamic_connections.erase(window_key)

func close_window(window_key: String) -> void:
    _clear_dynamic_connections(window_key)
    if active_windows.has(window_key):
        var win: Node = active_windows[window_key]
        if is_instance_valid(win):
            win.queue_free()
        active_windows.erase(window_key)

func toggle_window(window_key: String, options: Dictionary = {}) -> void:
    if active_windows.has(window_key) and is_instance_valid(active_windows[window_key]):
        close_window(window_key)
    else:
        open_window(window_key, options)
