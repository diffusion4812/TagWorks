# autoloads/project_manager.gd
extends Node

const SAVE_DIR     := "user://projects/"
const FILE_VERSION := 2

const NODE_REGISTRY: Dictionary = {
    "ButtonWidget":       "res://widgets/button_widget/button_widget.tscn",
    "LabelWidget":        "res://widgets/label_widget/label_widget.tscn",
    "SliderWidget":       "res://widgets/slider_widget/slider_widget.tscn",
    "NumericFieldWidget": "res://widgets/numeric_field_widget/numeric_field_widget.tscn",
    "LivePlotWidget":     "res://widgets/live_plot_widget/live_plot_widget.tscn",
    "LedIndicatorWidget": "res://widgets/led_indicator_widget/led_indicator_widget.tscn",
    "GaugeWidget":        "res://widgets/gauge_widget/gauge_widget.tscn",
    "TextDisplayWidget":  "res://widgets/text_display_widget/text_display_widget.tscn",
    "TabWidget":          "res://widgets/tab_widget/tab_widget.tscn",
    "WidgetCanvas":       "res://scenes/canvas/canvas.tscn",
}

var opc_ua_registry := OpcUaConfigRegistry.new()

var _current_project_path: String = ""

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    IntentBus.new_project_requested.connect(_on_new_project_requested)
    IntentBus.save_project_requested.connect(_on_save_project_requested)
    IntentBus.save_project_as_requested.connect(_on_save_project_as_requested)
    IntentBus.load_project_requested.connect(_on_load_project_requested)
    IntentBus.close_project_requested.connect(_on_close_project_requested)

# ── Helpers ───────────────────────────────────────────────────────────────────

func has_active_project() -> bool:
    return _current_project_path != ""


func get_current_project_path() -> String:
    return _current_project_path

# ── IntentBus Handlers ────────────────────────────────────────────────────────

func _on_new_project_requested() -> void:
    var data          := ProjectData.new()
    data.project_name =  "New Project"

    var default_page := PageData.create("Page 1")
    data.add_page(default_page)

    # Hydrate project first — this emits project_opened
    AppState.current_project.from_data(data)


func _on_save_project_requested() -> void:
    if _current_project_path.is_empty():
        push_warning("ProjectManager: save requested but no active project path.")
        return
    _save(_current_project_path)


func _on_save_project_as_requested(path: String) -> void:
    _save(path)


func _on_load_project_requested(path: String) -> void:
    _load(path)


func _on_close_project_requested() -> void:
    _current_project_path = ""
    AppState.clear()

# ── Save ──────────────────────────────────────────────────────────────────────

func _save(path: String) -> void:
    _ensure_save_dir()

    # Extract raw ProjectData from the reactive wrapper for serialisation
    var data := AppState.current_project.to_data()
    data.opc_ua_servers = opc_ua_registry.serialize()

    var canvas := _find_canvas()
    if canvas == null:
        EventBus.project_error.emit("No active canvas found for saving.")
        return

    data.canvas = canvas.serialize()

    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        EventBus.project_error.emit("Failed to open file for writing: %s" % path)
        return

    file.store_string(JSON.stringify(data.serialize(), "\t"))
    _current_project_path = path
    EventBus.project_saved.emit(path)

# ── Load ──────────────────────────────────────────────────────────────────────

func _load(path: String) -> void:
    if not FileAccess.file_exists(path):
        EventBus.project_error.emit("Project file not found: %s" % path)
        return

    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        EventBus.project_error.emit("Failed to open file for reading: %s" % path)
        return

    var payload: Variant = JSON.parse_string(file.get_as_text())
    if not payload is Dictionary:
        EventBus.project_error.emit("Invalid project file format.")
        return

    var data := ProjectData.from_dict(payload)
    if data == null:
        EventBus.project_error.emit("Unsupported or corrupt project file.")
        return

    data.file_path = path

    var canvas := _find_canvas()
    if canvas == null:
        EventBus.project_error.emit("No active canvas found for loading.")
        return

    canvas.clear_all_widgets()
    _restore_node(canvas, data.canvas)
    opc_ua_registry.deserialize(data.opc_ua_servers)

    _current_project_path = path

    # Hydrate the reactive wrappers from the loaded raw data
    AppState.current_project.from_data(data)

    var default_page := data.get_default_page()
    if default_page != null:
        AppState.current_page.from_data(default_page)

# ── Restore ───────────────────────────────────────────────────────────────────

func _restore_node(parent: Control, data: Dictionary) -> void:
    for child_data: Dictionary in data.get("children", []):
        var type: String = child_data.get("type", "")

        if not NODE_REGISTRY.has(type):
            push_error("ProjectManager: Unknown node type '%s'" % type)
            continue

        var packed := load(NODE_REGISTRY[type]) as PackedScene
        if packed == null:
            push_error("ProjectManager: Failed to load scene for '%s'" % type)
            continue

        var instance := packed.instantiate()
        if not instance is BaseWidget:
            push_error("ProjectManager: Instantiated scene is not a BaseWidget for type '%s'" % type)
            instance.queue_free()
            continue

        parent.add_child(instance)

        var widget := instance as BaseWidget

        if parent is WidgetCanvas:
            (parent as WidgetCanvas)._elevate_child(widget)
        elif parent is BaseWidget and (parent as BaseWidget).is_container:
            (parent as BaseWidget)._elevate_child(widget)

        var found_canvas := _find_canvas_for(widget)
        if found_canvas != null:
            found_canvas._subscribe_widget(widget)

        widget.deserialize(child_data)

        if widget.is_container:
            var drop_target := widget.get_drop_target()
            if drop_target != null:
                _restore_node(drop_target, child_data)

# ── Canvas Resolution ─────────────────────────────────────────────────────────

func _find_canvas() -> WidgetCanvas:
    return get_tree().root.find_child("Canvas", true, false) as WidgetCanvas


func _find_canvas_for(node: Node) -> WidgetCanvas:
    var current := node.get_parent()
    while current != null:
        if current is WidgetCanvas:
            return current as WidgetCanvas
        current = current.get_parent()
    return null

# ── Helpers ───────────────────────────────────────────────────────────────────

func get_saved_projects() -> Array[String]:
    _ensure_save_dir()
    var result: Array[String] = []
    var dir := DirAccess.open(SAVE_DIR)
    if dir == null:
        return result
    dir.list_dir_begin()
    var file_name := dir.get_next()
    while file_name != "":
        if not dir.current_is_dir() and file_name.ends_with(".json"):
            result.append(file_name.trim_suffix(".json"))
        file_name = dir.get_next()
    return result


func _ensure_save_dir() -> void:
    if not DirAccess.dir_exists_absolute(SAVE_DIR):
        DirAccess.make_dir_recursive_absolute(SAVE_DIR)
