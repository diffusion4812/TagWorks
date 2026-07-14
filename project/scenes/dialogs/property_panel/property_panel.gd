# property_panel.gd
class_name PropertyPanel
extends PanelContainer

var _current_target: BaseWidget = null

var node_browser:  BrowseNodes = null
var script_editor: Node        = null

@onready var panel_title: Label         = $MarginContainer/VBoxContainer/PanelTitle
@onready var extra_props: VBoxContainer = %ExtraProperties
@onready var apply_btn:   Button        = %ApplyButton
@onready var close_btn:   Button        = %CloseButton

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    apply_btn.pressed.connect(_on_apply_btn_pressed)
    close_btn.pressed.connect(_on_close_btn_pressed)

    AppState.selected_widget.changed.connect(_on_selected_widget_changed)


func _on_apply_btn_pressed() -> void:
    _reapply_current_target()


func _on_close_btn_pressed() -> void:
    IntentBus.deselect_widget_requested.emit()

# ── AppState Handlers ─────────────────────────────────────────────────────────

## Responds to changes on AppState.selected_widget.
## Null indicates deselection; any BaseWidget value triggers a panel load.
func _on_selected_widget_changed() -> void:
    var widget: BaseWidget = AppState.selected_widget.value
    if widget == null:
        clear()
    else:
        _load_target(widget)

# ── Load target into panel ────────────────────────────────────────────────────

func _load_target(target: BaseWidget) -> void:
    _current_target = target

    for child in extra_props.get_children():
        child.queue_free()

    _load_widget(target)


func clear() -> void:
    _current_target  = null
    panel_title.text = ""
    for child in extra_props.get_children():
        child.queue_free()
    hide()

# ── Apply ─────────────────────────────────────────────────────────────────────

func _reapply_current_target() -> void:
    var props := _get_target_properties(_current_target)
    if props != null:
        props.reapply()

# ── Widget Loading ────────────────────────────────────────────────────────────

func _load_widget(widget: BaseWidget) -> void:
    panel_title.text = widget.get_widget_class()
    widget.build_properties(WidgetPropertyBuilder.new(self))

# ── Property Emission ─────────────────────────────────────────────────────────

## Called by WidgetPropertyBuilder when the user edits a property.
## Emits a change intent — BaseWidget receives it, mutates ReactiveWidget,
## and the reactive changed signal propagates to any listeners automatically.
func emit_property_changed(property: String, value: Variant) -> void:
    if _current_target == null or _current_target.data == null:
        return
    IntentBus.change_widget_property_requested.emit(
        _current_target.data.widget_id.value,
        property,
        value
    )

# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_target_properties(target: Node) -> WidgetProperties:
    if target == null:
        return null
    if "properties" in target and target.properties is WidgetProperties:
        return target.properties
    push_warning("PropertyPanel: target '%s' has no WidgetProperties instance." % target.name)
    return null


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

    var cfg := ProjectManager.opc_ua_registry.get_config(server_id)
    if cfg == null:
        OS.alert("Server configuration not found.", "Browse Unavailable")
        return

    var temp_client := GodotOpcUa.new()
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
