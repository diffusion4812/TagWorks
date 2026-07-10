# autoloads/layout_manager.gd
extends Node

const SAVE_DIR: String = "user://layouts/"

func _ready() -> void:
    # Ensure save directory exists
    if not DirAccess.dir_exists_absolute(SAVE_DIR):
        DirAccess.make_dir_absolute(SAVE_DIR)

# ── Save ─────────────────────────────────────────────────────────────
func save_layout(layout_name: String, widgets: Array) -> bool:
    var layout_data: Array = []

    for widget in widgets:
        if widget is BaseWidget:
            layout_data.append(widget.serialize())

    var json_string: String = JSON.stringify(layout_data, "\t")
    var path: String = SAVE_DIR + layout_name + ".json"
    var file := FileAccess.open(path, FileAccess.WRITE)

    if file == null:
        push_error("LayoutManager: Failed to open file for writing: %s" % path)
        return false

    file.store_string(json_string)
    file.close()
    return true

# ── Load ─────────────────────────────────────────────────────────────
func load_layout(layout_name: String, canvas: Control) -> bool:
    var path: String = SAVE_DIR + layout_name + ".json"

    if not FileAccess.file_exists(path):
        push_error("LayoutManager: Layout file not found: %s" % path)
        return false

    var file := FileAccess.open(path, FileAccess.READ)

    if file == null:
        push_error("LayoutManager: Failed to open file for reading: %s" % path)
        return false

    var json_string: String = file.get_as_text()
    file.close()

    var json := JSON.new()
    var parse_result: Error = json.parse(json_string)

    if parse_result != OK:
        push_error("LayoutManager: JSON parse error at line %d: %s" % [
            json.get_error_line(),
            json.get_error_message()
        ])
        return false

    var layout_data: Array = json.get_data()

    for widget_data in layout_data:
        _spawn_widget(widget_data, canvas)

    return true

# ── List Available Layouts ───────────────────────────────────────────
func get_layout_names() -> Array[String]:
    var names: Array[String] = []
    var dir := DirAccess.open(SAVE_DIR)

    if dir == null:
        return names

    dir.list_dir_begin()
    var file_name: String = dir.get_next()

    while file_name != "":
        if not dir.current_is_dir() and file_name.ends_with(".json"):
            names.append(file_name.trim_suffix(".json"))
        file_name = dir.get_next()

    dir.list_dir_end()
    return names

# ── Delete Layout ────────────────────────────────────────────────────
func delete_layout(layout_name: String) -> bool:
    var path: String = SAVE_DIR + layout_name + ".json"

    if not FileAccess.file_exists(path):
        push_error("LayoutManager: Cannot delete, file not found: %s" % path)
        return false

    var err: Error = DirAccess.remove_absolute(path)

    if err != OK:
        push_error("LayoutManager: Failed to delete layout: %s" % path)
        return false

    return true

# ── Internal Widget Spawner ──────────────────────────────────────────
func _spawn_widget(data: Dictionary, canvas: Control) -> void:
    var scene_path: String = _get_scene_path(data.get("type", ""))

    if scene_path.is_empty():
        push_error("LayoutManager: Unknown widget type: %s" % data.get("type", ""))
        return

    var packed: PackedScene = load(scene_path)

    if packed == null:
        push_error("LayoutManager: Failed to load scene: %s" % scene_path)
        return

    var widget: BaseWidget = packed.instantiate()
    canvas.add_child(widget)
    widget.deserialize(data)

# ── Widget Type → Scene Path Map ────────────────────────────────────
func _get_scene_path(type: String) -> String:
    const TYPE_MAP: Dictionary = {
        "ButtonWidget":       "res://widgets/button_widget/button_widget.tscn",
        "SliderWidget":       "res://widgets/slider_widget/slider_widget.tscn",
        "NumericFieldWidget": "res://widgets/numeric_field_widget/numeric_field_widget.tscn",
        "LedIndicatorWidget": "res://widgets/led_indicator_widget/led_indicator_widget.tscn",
        "GaugeWidget":        "res://widgets/gauge_widget/gauge_widget.tscn",
        "TextDisplayWidget":  "res://widgets/text_display_widget/text_display_widget.tscn",
    }
    return TYPE_MAP.get(type, "")
