# property_panel.gd
class_name PropertyPanel
extends PanelContainer

var node_browser:    BrowseNodes     = null
var script_editor:   Node            = null
var _current_target: ReactiveWidget  = null
var _current_widget_node: BaseWidget = null

@onready var panel_title: Label         = $MarginContainer/VBoxContainer/PanelTitle
@onready var extra_props: VBoxContainer = %ExtraProperties
@onready var apply_btn:   Button        = %ApplyButton
@onready var close_btn:   Button        = %CloseButton

signal property_changed(p: String, v: Variant)

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    apply_btn.pressed.connect(_on_apply_btn_pressed)
    close_btn.pressed.connect(_on_close_btn_pressed)

    AppState.selected_widget.reactive_changed.connect(_on_selected_widget_changed)


func _on_apply_btn_pressed() -> void:
    _reapply_current_target()


func _on_close_btn_pressed() -> void:
    IntentBus.deselect_widget_requested.emit()

# ── AppState Handlers ─────────────────────────────────────────────────────────

## Responds to changes on AppState.selected_widget.
## Null indicates deselection; any ReactiveWidget value triggers a panel load.
func _on_selected_widget_changed(selected_widget: ReactiveVariant) -> void:
    if _current_widget_node != null and property_changed.is_connected(_current_widget_node._on_property_changed):
        property_changed.disconnect(_current_widget_node._on_property_changed)
    _current_widget_node = null

    _current_target = selected_widget.value as ReactiveWidget
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
    panel_title.text = ""
    _current_target  = null
    for child: Node in extra_props.get_children():
        child.queue_free()
    hide()


func _load_widget(node: Node, widget: ReactiveWidget) -> void:
    for child: Node in extra_props.get_children():
        child.queue_free()

    panel_title.text = widget.widget_type.value
    node.build_properties(WidgetPropertyBuilder.new(self, widget))

    show()

# ── Apply ─────────────────────────────────────────────────────────────────────

## Re-emits every current property value on the selected widget through the
## Intent Bus. Useful after reconnecting a data source or forcing a resync.
func _reapply_current_target() -> void:
    if _current_target != null:
        for id: String in _current_target.properties.keys():
            IntentBus.change_widget_property_requested.emit(_current_target, id, _current_target.properties[id])

# ── Helpers ───────────────────────────────────────────────────────────────────

func _open_script_editor(_prop: String) -> void:
    if not is_instance_valid(script_editor):
        push_warning("PropertyPanel: script_editor is not assigned.")
        return
    script_editor.show()


func _open_browser_for_server(server_id: String, on_selected: Callable) -> void:
    if not is_instance_valid(node_browser):
        push_warning("PropertyPanel: node_browser is not assigned.")
        return

    if OpcUaManager.is_server_connected(server_id):
        node_browser.request_node_id(OpcUaManager, server_id, on_selected)
        return

    var cfg: OpcUaServerConfig = ProjectManager.opc_ua_registry.get_config(server_id)
    if cfg == null:
        OS.alert("Server configuration not found.", "Browse Unavailable")
        return

    var temp_client: GodotOpcUa = GodotOpcUa.new()
    var ok: bool
    if cfg.username.is_empty():
        ok = temp_client.connect_to_server(cfg.endpoint_url)
    else:
        ok = temp_client.connect_with_credentials(
            cfg.endpoint_url, cfg.username, cfg.password
        )

    if not ok:
        OS.alert(
            "Could not connect to '%s' for browsing.\nCheck the endpoint and credentials in the server configuration." \
                % cfg.display_name,
            "Browse Failed"
        )
        return

    node_browser.request_node_id_temporary(temp_client, on_selected)
