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
}

var opc_ua_registry := OpcUaConfigRegistry.new()

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    IntentBus.new_project_requested.connect(_on_new_project_requested)
    IntentBus.save_project_requested.connect(_on_save_project_requested)
    IntentBus.save_project_as_requested.connect(_on_save_project_as_requested)
    IntentBus.open_project_requested.connect(_on_open_project_requested)
    IntentBus.close_project_requested.connect(_on_close_project_requested)

# ── Helpers ───────────────────────────────────────────────────────────────────

func has_active_project() -> bool:
    return not AppState.current_project.value.file_path.value.is_empty()


func get_current_project_path() -> String:
    return AppState.current_project.value.file_path.value

# ── IntentBus Handlers ────────────────────────────────────────────────────────

func _on_new_project_requested() -> void:
    var new_project: ReactiveProject = ReactiveProject.new(null, "new_project")
    new_project.project_name.value = "New Project"
    var new_page := ReactivePage.create("New Page", new_project.pages, "new_page")
    new_project.pages.append(new_page)

    AppState.current_project.value = new_project


func _on_save_project_requested() -> void:
    if AppState.current_project.value.file_path.value.is_empty():
        push_warning("ProjectManager: Save requested but no active project path.")
        return
    _save(AppState.current_project.value.file_path.value)


func _on_save_project_as_requested(path: String) -> void:
    _save(path)


func _on_open_project_requested(path: String) -> void:
    _load(path)


func _on_close_project_requested() -> void:
    AppState.clear()

# ── Save ──────────────────────────────────────────────────────────────────────

## Serialises the full reactive project tree to JSON.
## ReactiveCanvas on each page already holds the current widget layout —
## no scene tree traversal is required.
func _save(path: String) -> void:
    _ensure_save_dir()

    var project: ReactiveProject = AppState.current_project.value

    # Inject live OPC UA server state before serialising
    project.opc_ua_servers.value = opc_ua_registry.serialize()

    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        push_error("Failed to open file for writing: %s" % path)
        return

    file.store_string(JSON.stringify(project.serialize(), "\t"))
    file.close()

    project.file_path.value = path

# ── Load ──────────────────────────────────────────────────────────────────────

## Deserialises a project from JSON, restores OPC UA state, rebuilds all
## page canvas widget trees in the scene, then pushes the result into AppState.
func _load(path: String) -> void:
    if not FileAccess.file_exists(path):
        AppState.last_error.value = "Project file not found: %s" % path
        return

    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        AppState.last_error.value = "Failed to open file for reading: %s" % path
        return

    var payload: Variant = JSON.parse_string(file.get_as_text())
    file.close()

    if not payload is Dictionary:
        AppState.last_error.value = "Invalid project file format."
        return

    var project := ReactiveProject.from_dict(payload)
    if project == null:
        AppState.last_error.value = "Unsupported or corrupt project file."
        return

    project.file_path.value = path

    opc_ua_registry.deserialize(project.opc_ua_servers.value)

    # Rebuild the live scene widget trees for every page from canvas data
    _restore_all_canvases(project.pages)

    # Push the fully hydrated project into AppState
    AppState.current_project.value = project

    var default_page: ReactivePage = AppState.current_project.value.get_default_page()
    if default_page != null:
        AppState.focused_page.value = default_page
        AppState.active_page.value  = default_page

# ── Canvas Restore ────────────────────────────────────────────────────────────

## Recursively walks all pages and rebuilds each page's live widget scene
## tree from the widget dictionaries stored in ReactivePage.canvas.
func _restore_all_canvases(pages: ReactiveArray) -> void:
    for item: Variant in pages.values():
        var page := item as ReactivePage
        if page == null:
            continue

        _restore_canvas(page)
        _restore_all_canvases(page.children)


## Restores the widget scene tree for a single page from its ReactiveCanvas.
func _restore_canvas(page: ReactivePage) -> void:
    # Resolve the scene node responsible for hosting this page's widgets.
    # Each WidgetHost node should expose a page_id property and belong to
    # the "widget_host" group so it can be matched to its ReactivePage.
    var host := _find_host_for_page(page)
    if host == null:
        push_warning("ProjectManager: No widget host found for page '%s'." % page.page_id.value)
        return

    host.clear_all_widgets()

    for item: Variant in page.canvas.widgets.values():
        if item is Dictionary:
            _restore_node(host, item)


## Resolves the scene node responsible for hosting widgets for the given page.
func _find_host_for_page(page: ReactivePage) -> Control:
    var hosts := get_tree().get_nodes_in_group("widget_host")
    for node: Node in hosts:
        var host := node as Control
        if host != null and host.get("page_id") == page.page_id.value:
            return host
    return null

# ── Node Restore ──────────────────────────────────────────────────────────────

## Instantiates and deserialises a single widget from a serialised Dictionary,
## then recurses into container children.
func _restore_node(parent: Control, data: Dictionary) -> void:
    var type: String = data.get("type", "")

    if not NODE_REGISTRY.has(type):
        push_error("ProjectManager: Unknown node type '%s'." % type)
        return

    var packed := load(NODE_REGISTRY[type]) as PackedScene
    if packed == null:
        push_error("ProjectManager: Failed to load scene for '%s'." % type)
        return

    var instance := packed.instantiate()
    if not instance is BaseWidget:
        push_error("ProjectManager: Scene is not a BaseWidget for type '%s'." % type)
        instance.queue_free()
        return

    parent.add_child(instance)

    var widget := instance as BaseWidget

    if parent is BaseWidget and (parent as BaseWidget).is_container:
        (parent as BaseWidget)._elevate_child(widget)

    widget.deserialize(data)

    if widget.is_container:
        var drop_target := widget.get_drop_target()
        if drop_target != null:
            for child_data: Variant in data.get("children", []):
                if child_data is Dictionary:
                    _restore_node(drop_target, child_data)

# ── Project Listing ───────────────────────────────────────────────────────────

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
