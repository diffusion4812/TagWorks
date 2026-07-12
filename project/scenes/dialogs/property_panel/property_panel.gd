# property_panel.gd
class_name PropertyPanel
extends PanelContainer

var _current_target: BaseWidget = null

# Set externally by InspectorManager or the scene that owns these nodes
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

    EventBus.widget_selected.connect(_on_widget_selected)
    EventBus.widget_deselected.connect(_on_widget_deselected)
    EventBus.widget_property_changed.connect(_on_widget_property_changed)


func _on_apply_btn_pressed() -> void:
    _reapply_current_target()


func _on_close_btn_pressed() -> void:
    # Emit deselect intent so the manager can handle docked vs. floating
    # behaviour rather than hiding directly.
    IntentBus.deselect_widget_requested.emit()

# ── EventBus handlers ─────────────────────────────────────────────────────────

## Responds to a confirmed widget selection and loads the widget into the panel.
func _on_widget_selected(widget: BaseWidget) -> void:
    _load_target(widget)


## Responds to a confirmed widget deselection and clears the panel.
func _on_widget_deselected() -> void:
    clear()


## Responds to a confirmed property change and forwards it to the widget's
## WidgetProperties instance so live state remains consistent.
func _on_widget_property_changed(widget_id: String, property: String, value: Variant) -> void:
    if _current_target == null:
        return
    if _current_target.widget_id != widget_id:
        return

    var props := _get_target_properties(_current_target)
    if props != null:
        props.on_property_changed(property, value)

# ── Load target into panel ────────────────────────────────────────────────────

## Loads a BaseWidget into the panel. Called internally via EventBus.
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

# ── Widget loading ────────────────────────────────────────────────────────────

func _load_widget(widget: BaseWidget) -> void:
    panel_title.text = widget.get_widget_class()
    widget.build_properties(WidgetPropertyBuilder.new(self))

# ── Property emission ─────────────────────────────────────────────────────────

## Called by WidgetPropertyBuilder when the user edits a property in the UI.
## Emits a change intent rather than applying the value directly.
func emit_property_changed(property: String, value: Variant) -> void:
    if _current_target == null:
        return
    IntentBus.change_widget_property_requested.emit(
        _current_target.widget_id,
        property,
        value
    )

# ── Helpers called by WidgetPropertyBuilder ───────────────────────────────────

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
