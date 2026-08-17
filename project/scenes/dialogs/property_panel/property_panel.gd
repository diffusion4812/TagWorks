class_name PropertyPanel
extends PanelContainer

var _current_target: ReactiveWidget  = null
var _current_widget_node: BaseWidget = null

@onready var _properties : VBoxContainer = %Properties
@onready var _events :     VBoxContainer = %Events

signal property_changed(p: String, v: Variant)

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    AppState.selected_widgets.connect_self_changed(_on_selected_widgets_changed)

# ── AppState Handlers ─────────────────────────────────────────────────────────

func _on_selected_widgets_changed(selected_widgets: ReactiveArray) -> void:
    if selected_widgets.size() != 1:
        return
    if _current_widget_node != null and property_changed.is_connected(_current_widget_node._on_property_changed):
        property_changed.disconnect(_current_widget_node._on_property_changed)
    _current_widget_node = null

    _current_target = selected_widgets.get_at(0) as ReactiveWidget
    if _current_target == null:
        clear()
        return

    _current_widget_node = get_widget_node(_current_target)
    if _current_widget_node == null:
        push_warning("No live node found for widget_id: %s" % _current_target.widget_id)
    else:
        property_changed.connect(_current_widget_node._on_property_changed)

    _load_widget(_current_widget_node, _current_target)

#TODO: Update this to be more efficient!
func get_widget_node(w: ReactiveWidget) -> BaseWidget:
    return _find_widget(get_tree().root, w)

func _find_widget(node: Node, widget_id: ReactiveWidget) -> BaseWidget:
    if node is BaseWidget and node.data == widget_id:
        return node
    for child: Node in node.get_children():
        var found: BaseWidget = _find_widget(child, widget_id)
        if found != null:
            return found
    return null

# ── Clear / Load ──────────────────────────────────────────────────────────────

func clear() -> void:
    _current_target  = null
    for child: Node in _properties.get_children():
        child.queue_free()
    for child: Node in _events.get_children():
        child.queue_free()


func _load_widget(node: Node, widget: ReactiveWidget) -> void:
    for child: Node in _properties.get_children():
        child.queue_free()
    for child: Node in _events.get_children():
        child.queue_free()

    var base_widget: BaseWidget = node as BaseWidget
    if base_widget != null:
        base_widget.build_properties(WidgetPropertyBuilder.new(self))
    else:
        push_warning("Properties panel: node '%s' is not a BaseWidget." % node.name)

# ── Helpers ───────────────────────────────────────────────────────────────────

## Looks up a ReactiveOpcUaServer by id within the current project.
## Returns null if no project is loaded or no server matches.
func _find_server_config(server_id: String) -> ReactiveOpcUaServer:
    var project: ReactiveProject = AppState.current_project.value
    if project == null:
        return null

    for server: ReactiveOpcUaServer in project.servers.values():
        if server.id.value == server_id:
            return server

    return null
