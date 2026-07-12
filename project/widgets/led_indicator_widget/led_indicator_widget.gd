# widgets/led_indicator_widget/led_indicator_widget.gd
class_name LedIndicatorWidget
extends BaseWidget

@onready var led_lamp: TextureRect = $MarginContainer/ContentSlot/Lamp

# ─────────────────────────────────────────────
# Properties
# ─────────────────────────────────────────────

var state: bool = false:
    set(value):
        state = value
        if is_node_ready():
            update_display(state)

var color_on: Color = Color.GREEN:
    set(value):
        color_on = value
        if is_node_ready():
            update_display(state)

var color_off: Color = Color.DARK_GREEN:
    set(value):
        color_off = value
        if is_node_ready():
            update_display(state)

var node_id: OpcUaNodeId = null:
    set(value):
        node_id = value
        if is_instance_valid(_binding):
            _binding.node_id = value

var _binding: OpcUaBinding

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
    super._ready()
    update_display(state)

    _binding = OpcUaBinding.new()
    _binding.value_changed.connect(_on_value_changed)

    if node_id != null:
        _binding.node_id = node_id

# ─────────────────────────────────────────────
# Display
# ─────────────────────────────────────────────

func update_display(value: Variant) -> void:
    if is_instance_valid(led_lamp):
        led_lamp.modulate = color_on if bool(value) else color_off

# ─────────────────────────────────────────────
# Signal Handlers
# ─────────────────────────────────────────────

func _on_value_changed(value: Variant) -> void:
    update_display(value)

# ─────────────────────────────────────────────
# Class
# ─────────────────────────────────────────────

func get_widget_class() -> String:
    return "LedIndicatorWidget"

# ─────────────────────────────────────────────
# Edit Mode
# ─────────────────────────────────────────────

func build_properties(builder: WidgetPropertyBuilder) -> void:
    builder.add_color_field( "color_on",  "Color ON",  color_on)
    builder.add_color_field( "color_off", "Color OFF", color_off)

# ─────────────────────────────────────────────
# Serialization
# ─────────────────────────────────────────────

func serialize() -> Dictionary:
    var data := super.serialize()
    data["node_id"]   = node_id.serialize() if node_id != null else null
    data["color_on"]  = { "r": color_on.r,  "g": color_on.g,  "b": color_on.b,  "a": color_on.a  }
    data["color_off"] = { "r": color_off.r, "g": color_off.g, "b": color_off.b, "a": color_off.a }
    return data

func deserialize(data: Dictionary) -> void:
    super.deserialize(data)

    if data.has("node_id") and data["node_id"] != null:
        var n := OpcUaNodeId.new()
        n.deserialize(data["node_id"])
        node_id = n

    if data.has("color_on"):
        var c: Dictionary = data["color_on"]
        color_on = Color(c["r"], c["g"], c["b"], c["a"])

    if data.has("color_off"):
        var c: Dictionary = data["color_off"]
        color_off = Color(c["r"], c["g"], c["b"], c["a"])
