extends Node

const SAVE_DIR     :String = "user://projects/"
const FILE_VERSION :int    = 2

const NODE_REGISTRY: Dictionary = {
    "LabelWidget":        preload("res://widgets/label_widget/label_widget.tscn"),
    "NumericFieldWidget": preload("res://widgets/numeric_field_widget/numeric_field_widget.tscn"),
    "LivePlotWidget":     preload("res://widgets/live_plot_widget/live_plot_widget.tscn"),
    "LedIndicatorWidget": preload("res://widgets/led_indicator_widget/led_indicator_widget.tscn"),
}

const PROJECT_FILE_FILTER: PackedStringArray = ["*.json ; Project Files"]

var project: ReactiveProject = null

## Reactive status owned exclusively by ProjectManager — the single
## source of truth for the outcome of the last load/save attempt.
## Success is observed separately via AppState.current_project.is_loaded.
var last_error: ReactiveString = ReactiveString.new("")

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    IntentBus.new_project_requested.connect(_on_new_project_requested)
    IntentBus.save_project_requested.connect(_on_save_project_requested)
    IntentBus.save_project_as_requested.connect(_on_save_project_as_requested)
    IntentBus.open_project_requested.connect(_on_open_project_requested)
    IntentBus.close_project_requested.connect(_on_close_project_requested)
    IntentBus.open_project_dialog_requested.connect(_on_open_project_dialog_requested)
    IntentBus.save_project_as_dialog_requested.connect(_on_save_project_as_dialog_requested)

# ── Helpers ───────────────────────────────────────────────────────────────────

func has_active_project() -> bool:
    return not AppState.current_project.value.file_path.value.is_empty()

func get_current_project_path() -> String:
    return AppState.current_project.value.file_path.value

# ── IntentBus Handlers ────────────────────────────────────────────────────────

func _on_new_project_requested() -> void:
    last_error.value = ""
    AppState.new_project()


func _on_save_project_requested() -> void:
    if AppState.current_project.file_path.value.is_empty():
        _on_save_project_as_dialog_requested()
        return
    _save(AppState.current_project.file_path.value)


func _on_save_project_as_requested(path: String) -> void:
    _save(path)


func _on_open_project_requested(path: String) -> void:
    last_error.value = ""

    if not FileAccess.file_exists(path):
        _fail("Project file not found: %s" % path)
        return

    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        _fail("Failed to open file for reading: %s" % path)
        return

    var payload: Variant = JSON.parse_string(file.get_as_text())
    file.close()

    if not payload is Dictionary:
        _fail("Invalid project file format.")
        return

    AppState.load_project(payload)

    if AppState.current_project.is_loaded.value:
        AppState.current_project.file_path.value = path
        RecentProjects.add(path, AppState.current_project.project_name.value)
    else:
        _fail("Project failed to initialize after loading.")


func _on_close_project_requested() -> void:
    AppState.close_project()


func _fail(reason: String) -> void:
    push_warning("ProjectManager: %s" % reason)
    last_error.value = reason

# ── File Dialogs ──────────────────────────────────────────────────────────────

func _on_open_project_dialog_requested() -> void:
    _ensure_save_dir()

    WindowManager.open_window("filedialog", {
        "params": {
            "title":       "Open Project",
            "file_mode":   FileDialog.FILE_MODE_OPEN_FILE,
            "access":      FileDialog.ACCESS_FILESYSTEM,
            "current_dir": SAVE_DIR,
            "filters":     PROJECT_FILE_FILTER
        },
        "callbacks": {
            "file_selected": _on_open_dialog_selected
        }
    })


func _on_save_project_as_dialog_requested() -> void:
    _ensure_save_dir()

    var params: Dictionary = {
        "title":     "Save Project As",
        "file_mode": FileDialog.FILE_MODE_SAVE_FILE,
        "access":    FileDialog.ACCESS_FILESYSTEM,
        "filters":   PROJECT_FILE_FILTER
    }

    var current_path: String = AppState.current_project.file_path.value
    if not current_path.is_empty():
        params["current_path"] = current_path
    else:
        params["current_dir"] = SAVE_DIR

    WindowManager.open_window("filedialog", {
        "params": params,
        "callbacks": {
            "file_selected": _on_save_dialog_selected
        }
    })


func _on_open_dialog_selected(path: String) -> void:
    _on_open_project_requested(path)


func _on_save_dialog_selected(path: String) -> void:
    _save(path)

# ── Save ──────────────────────────────────────────────────────────────────────

func _save(path: String) -> void:
    _ensure_save_dir()

    var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        _fail("Failed to open file for writing: %s" % path)
        return

    file.store_string(JSON.stringify(AppState.current_project.serialize(), "\t"))
    file.close()

    AppState.current_project.file_path.value = path
    RecentProjects.add(AppState.current_project.file_path.value, AppState.current_project.project_name.value)

# ── Canvas Restore ────────────────────────────────────────────────────────────

func _restore_all_canvases(pages: ReactiveArray) -> void:
    for item: Variant in pages.values():
        var page: ReactivePage = item as ReactivePage
        if page == null:
            continue
        _restore_canvas(page)
        _restore_all_canvases(page.children)


func _restore_canvas(page: ReactivePage) -> void:
    var host: Control = _find_host_for_page(page)
    if host == null:
        push_warning("ProjectManager: No widget host found for page '%s'." % page.page_id.value)
        return

    host.clear_all_widgets()

    for item: Variant in page.canvas.widgets.values():
        if item is Dictionary:
            _restore_node(host, item)


func _find_host_for_page(page: ReactivePage) -> Control:
    var hosts: Array[Node] = get_tree().get_nodes_in_group("widget_host")
    for node: Node in hosts:
        var host: Control = node as Control
        if host != null and host.get("page_id") == page.page_id.value:
            return host
    return null

# ── Node Restore ──────────────────────────────────────────────────────────────

func _restore_node(parent: Control, data: Dictionary) -> void:
    var type: String = data.get("type", "")

    if not NODE_REGISTRY.has(type):
        push_error("ProjectManager: Unknown node type '%s'." % type)
        return

    var packed: PackedScene = load(NODE_REGISTRY[type]) as PackedScene
    if packed == null:
        push_error("ProjectManager: Failed to load scene for '%s'." % type)
        return

    var instance: Node = packed.instantiate()
    if not instance is BaseWidget:
        push_error("ProjectManager: Scene is not a BaseWidget for type '%s'." % type)
        instance.queue_free()
        return

    parent.add_child(instance)

    var widget: BaseWidget = instance as BaseWidget

    if parent is BaseWidget and (parent as BaseWidget).is_container:
        (parent as BaseWidget)._elevate_child(widget)

    widget.deserialize(data)

    if widget.is_container:
        var drop_target: Control = widget.get_drop_target()
        if drop_target != null:
            for child_data: Variant in data.get("children", []):
                if child_data is Dictionary:
                    _restore_node(drop_target, child_data)

# ── Project Listing ───────────────────────────────────────────────────────────

func get_saved_projects() -> Array[String]:
    _ensure_save_dir()
    var result: Array[String] = []
    var dir: DirAccess = DirAccess.open(SAVE_DIR)
    if dir == null:
        return result
    dir.list_dir_begin()
    var file_name: String = dir.get_next()
    while file_name != "":
        if not dir.current_is_dir() and file_name.ends_with(".json"):
            result.append(file_name.trim_suffix(".json"))
        file_name = dir.get_next()
    return result


func _ensure_save_dir() -> void:
    if not DirAccess.dir_exists_absolute(SAVE_DIR):
        DirAccess.make_dir_recursive_absolute(SAVE_DIR)
