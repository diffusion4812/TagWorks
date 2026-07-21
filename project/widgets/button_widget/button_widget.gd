# widgets/button_widget/button_widget.gd
class_name ButtonWidget
extends BaseWidget

@onready var button: Button = $MarginContainer/ContentSlot/Button

var _binding: OpcUaBinding

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
    button.text = data.properties.value["label"].value
    button.button_down.connect(_on_button_down)
    button.button_up.connect(_on_button_up)

    AppState.edit_mode.connect_self_changed(_on_edit_mode_changed)
    _on_edit_mode_changed(AppState.edit_mode)

    _binding = OpcUaBinding.new()
    _binding.value_changed.connect(_on_value_changed)

    if node_id != null:
        _binding.node_id = node_id

func _define_default_properties() -> void:
    super._define_default_properties()
    _ensure_property("label", func() -> ReactiveString:
        return ReactiveString.new("Button", data.properties, "label")
    )
    _ensure_property("node_id", func() -> ReactiveTag:
        return ReactiveTag.new({}, data.properties, "node_id")
    )

func _connect_data_signals() -> void:
    data.properties.value["label"].connect_self_changed(
        func(s: ReactiveString) -> void:
            button.text = s.value
    )

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

func _on_edit_mode_changed(enabled: ReactiveBool) -> void:
    button.disabled     = enabled.value
    button.mouse_filter = Control.MOUSE_FILTER_IGNORE if enabled.value else Control.MOUSE_FILTER_STOP

func _on_property_changed(p: String, v: Variant) -> void:
    data.properties.value[p].value = v

# ─────────────────────────────────────────────
# Class
# ─────────────────────────────────────────────

func get_widget_class() -> String:
    return "ButtonWidget"

# ─────────────────────────────────────────────
# Edit Mode
# ─────────────────────────────────────────────

func build_properties(builder: WidgetPropertyBuilder) -> void:
    super.build_properties(builder)
    builder.add_string_field("label", "Label",  data.properties)
    builder.add_node_field("node_id", "Node ID",  data.properties)

# ─────────────────────────────────────────────
# Serialization
# ─────────────────────────────────────────────

func serialize() -> Dictionary:
    var serialized_data: Dictionary = super.serialize()
    serialized_data["node_id"] = node_id.to_tag_name() if node_id != null else ""
    return serialized_data

func deserialize(serialized_data: Dictionary) -> void:
    super.deserialize(serialized_data)
    node_id = OpcUaNodeId.parse(serialized_data["node_id"]) if serialized_data["node_id"] != "" else null
