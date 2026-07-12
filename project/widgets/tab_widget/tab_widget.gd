# widgets/tab_widget/tab_widget.gd
class_name TabWidget
extends BaseWidget

@onready var tab_container: TabContainer = $MarginContainer/ContentSlot/TabContainer

const WIDGET_CANVAS_SCENE := preload("res://scenes/canvas/canvas.tscn")

var tab_titles: Array[String] = []:
    set(value):
        tab_titles = value
        _rebuild_tabs()

## Stores the WidgetCanvas instance for each tab, keyed by tab title.
var _tab_canvases: Dictionary = {}  # title -> WidgetCanvas

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    is_container = true
    super._ready()
    mouse_filter               = Control.MOUSE_FILTER_PASS
    tab_container.mouse_filter = Control.MOUSE_FILTER_STOP
    # Correct canvas filters whenever the active tab changes
    tab_container.tab_changed.connect(_on_tab_changed)
    _rebuild_tabs()

# ── Tab Management ────────────────────────────────────────────────────────────

func _rebuild_tabs() -> void:
    if not is_node_ready():
        return
    if not is_instance_valid(tab_container):
        return

    # Remove tabs whose titles no longer exist in tab_titles
    for title in _tab_canvases.keys():
        if title not in tab_titles:
            var canvas: WidgetCanvas = _tab_canvases[title]
            _disconnect_inner_canvas(canvas)
            tab_container.remove_child(canvas)
            canvas.queue_free()
            _tab_canvases.erase(title)

    # Add tabs that are new in tab_titles
    for title in tab_titles:
        if title not in _tab_canvases:
            _add_tab(title)

    # Reorder children to match tab_titles order
    for i in range(tab_titles.size()):
        var canvas: WidgetCanvas = _tab_canvases[tab_titles[i]]
        tab_container.move_child(canvas, i)
        tab_container.set_tab_title(i, tab_titles[i])


func _add_tab(title: String) -> WidgetCanvas:
    var canvas := WIDGET_CANVAS_SCENE.instantiate() as WidgetCanvas
    canvas.name                  = title.validate_node_name()
    canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    canvas.size_flags_vertical   = Control.SIZE_EXPAND_FILL

    tab_container.add_child(canvas)
    canvas.mouse_filter = Control.MOUSE_FILTER_PASS
    tab_container.set_tab_title(tab_container.get_tab_count() - 1, title)
    _elevate_child(canvas)
    _connect_inner_canvas(canvas)

    _tab_canvases[title] = canvas
    return canvas


func _connect_inner_canvas(canvas: WidgetCanvas) -> void:
    if not canvas.target_selected.is_connected(_on_inner_canvas_target_selected):
        canvas.target_selected.connect(_on_inner_canvas_target_selected)
    if not canvas.target_deselected.is_connected(_on_inner_canvas_target_deselected):
        canvas.target_deselected.connect(_on_inner_canvas_target_deselected)


func _disconnect_inner_canvas(canvas: WidgetCanvas) -> void:
    if canvas.target_selected.is_connected(_on_inner_canvas_target_selected):
        canvas.target_selected.disconnect(_on_inner_canvas_target_selected)
    if canvas.target_deselected.is_connected(_on_inner_canvas_target_deselected):
        canvas.target_deselected.disconnect(_on_inner_canvas_target_deselected)


func _on_inner_canvas_target_selected(target: Node) -> void:
    if is_instance_valid(_root_canvas):
        _root_canvas._select_target(target)


func _on_inner_canvas_target_deselected() -> void:
    if is_instance_valid(_root_canvas):
        _root_canvas._deselect_current()

func _on_tab_changed(_tab: int) -> void:
    # TabContainer resets child filters on tab switch — reassert for all canvases
    for canvas: WidgetCanvas in _tab_canvases.values():
        canvas.mouse_filter = Control.MOUSE_FILTER_PASS

# ── Drop Target ───────────────────────────────────────────────────────────────

## Returns the WidgetCanvas of the active tab as the drop target.
func get_drop_target() -> Control:
    var index := tab_container.current_tab
    if index < 0 or index >= tab_titles.size():
        return null
    return _tab_canvases.get(tab_titles[index], null)

# ── Protected Controls ────────────────────────────────────────────────────────

## Protects the TabContainer so tab switching remains functional in edit mode.
func get_protected_controls() -> Array[Control]:
    return [tab_container]

# ── Virtuals ──────────────────────────────────────────────────────────────────

func get_widget_class() -> String:
    return "TabWidget"

# ── Edit Mode ─────────────────────────────────────────────────────────────────

func _on_edit_mode_changed(enabled: bool) -> void:
    # Allow base class to run the child sweep — TabContainer is protected above
    super._on_edit_mode_changed(enabled)

    # Propagate edit mode to each inner canvas independently
    for canvas: WidgetCanvas in _tab_canvases.values():
        canvas.is_edit_mode = enabled

# ── Property Builder ──────────────────────────────────────────────────────────

func build_properties(builder: WidgetPropertyBuilder) -> void:
    super.build_properties(builder)
    builder.add_string_list_field("tab_titles", "Tab Titles", tab_titles)

# ── Serialization ─────────────────────────────────────────────────────────────

func serialize() -> Dictionary:
    var data := super.serialize()
    data["tab_titles"]  = tab_titles.duplicate()
    data["current_tab"] = tab_container.current_tab

    var tabs_data: Array[Dictionary] = []
    for title in tab_titles:
        var canvas: WidgetCanvas = _tab_canvases.get(title)
        var children: Array[Dictionary] = []
        if is_instance_valid(canvas):
            for widget in canvas.get_all_nodes_recursive():
                children.append(widget.serialize())
        tabs_data.append({ "children": children })

    data["tabs_data"] = tabs_data
    return data


func deserialize(data: Dictionary) -> void:
    super.deserialize(data)
    tab_titles = Array(data.get("tab_titles", []), TYPE_STRING, "", null)
    set_current_tab(data.get("current_tab", 0))

    var tabs_data: Array = data.get("tabs_data", [])
    for i in range(min(tabs_data.size(), tab_titles.size())):
        var canvas: WidgetCanvas = _tab_canvases.get(tab_titles[i])
        if not is_instance_valid(canvas):
            continue
        for child_data: Dictionary in tabs_data[i].get("children", []):
            var scene    := load(child_data["scene"]) as PackedScene
            var instance := scene.instantiate() as BaseWidget
            canvas.add_child(instance)
            instance.deserialize(child_data)

# ── Helpers ───────────────────────────────────────────────────────────────────

func get_current_tab() -> int:
    return tab_container.current_tab


func set_current_tab(index: int) -> void:
    if index >= 0 and index < tab_container.get_tab_count():
        tab_container.current_tab = index
