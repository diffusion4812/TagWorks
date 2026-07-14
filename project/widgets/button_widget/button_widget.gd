# widgets/button_widget/button_widget.gd
class_name ButtonWidget
extends BaseWidget

@onready var button: Button = $MarginContainer/ContentSlot/Button

var _binding: OpcUaBinding

var label: String = "Button":
    set(value):
        label = value
        if is_node_ready():
            button.text = value

var node_id: OpcUaNodeId = null:
    set(value):
        node_id = value
        if is_instance_valid(_binding):
            _binding.node_id = value

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
    super._ready()
    button.text = label
    button.button_down.connect(_on_button_down)
    button.button_up.connect(_on_button_up)

    AppState.edit_mode.reactive_changed.connect(_on_edit_mode_changed)
    _on_edit_mode_changed(AppState.edit_mode)

    _binding = OpcUaBinding.new()
    _binding.value_changed.connect(_on_value_changed)

    if node_id != null:
        _binding.node_id = node_id

# ─────────────────────────────────────────────
# Display
# ─────────────────────────────────────────────

func update_display(value: Variant) -> void:
    button.set_pressed_no_signal(bool(value))
    button.text = "ON" if bool(value) else "OFF"

# ─────────────────────────────────────────────
# Signal Handlers
# ─────────────────────────────────────────────

func _on_button_down() -> void:
    if is_instance_valid(_binding):
        _binding.write_value(true)

func _on_button_up() -> void:
    if is_instance_valid(_binding):
        _binding.write_value(false)

func _on_value_changed(value: Variant) -> void:
    update_display(value)

func _on_edit_mode_changed(enabled) -> void:
    button.disabled     = enabled.value
    button.mouse_filter = Control.MOUSE_FILTER_IGNORE if enabled.value else Control.MOUSE_FILTER_STOP

# ─────────────────────────────────────────────
# Class
# ─────────────────────────────────────────────

func get_widget_class() -> String:
    return "ButtonWidget"

# ─────────────────────────────────────────────
# Edit Mode
# ─────────────────────────────────────────────

func build_properties(builder: WidgetPropertyBuilder) -> void:
    builder.add_string_field("label",   "Button Label", label)
    builder.add_node_field(  "node_id", "Node ID",      node_id)

# ─────────────────────────────────────────────
# Serialization
# ─────────────────────────────────────────────

func serialize() -> Dictionary:
    var data := super.serialize()
    data["label"]   = label
    data["node_id"] = node_id.to_tag_name() if node_id != null else null
    return data

func deserialize(data: Dictionary) -> void:
    super.deserialize(data)
    label   = data.get("label", "Button")
    node_id = OpcUaNodeId.parse(data["node_id"]) if data["node_id"] != null else null
