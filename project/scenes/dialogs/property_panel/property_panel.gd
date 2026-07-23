# property_panel.gd
class_name PropertyPanel
extends PanelContainer

@onready var node_browser:    BrowseNodes     = $"../../../../../Dialogs/BrowseNodes"
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

    AppState.selected_widget.connect_self_changed(_on_selected_widget_changed)


func _on_apply_btn_pressed() -> void:
    _reapply_current_target()


func _on_close_btn_pressed() -> void:
    IntentBus.deselect_widget_requested.emit()

# ── AppState Handlers ─────────────────────────────────────────────────────────

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

    var cfg: ReactiveOpcUaServer = _find_server_config(server_id)
    if cfg == null:
        OS.alert("Server configuration not found.", "Browse Unavailable")
        return

    var temp_client: GodotOpcUa = GodotOpcUa.new()
    var ok: bool
    if cfg.username.value.is_empty():
        ok = temp_client.connect_to_server(cfg.endpoint_url.value)
    else:
        ok = temp_client.connect_with_credentials(
            cfg.endpoint_url.value, cfg.username.value, cfg.password.value
        )

    if not ok:
        OS.alert(
            "Could not connect to '%s' for browsing.\nCheck the endpoint and credentials in the server configuration." \
                % cfg.display_name.value,
			"Browse Failed"
        )
        return

    node_browser.request_node_id_temporary(temp_client, on_selected)


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
