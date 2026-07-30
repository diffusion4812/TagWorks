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

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
    super._ready()
    update_display(state)

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

func build_properties(_builder: WidgetPropertyBuilder) -> void:
    pass
   # builder.add_color_field( "color_on",  "Color ON",  color_on)
  #  builder.add_color_field( "color_off", "Color OFF", color_off)

# ─────────────────────────────────────────────
# Serialization
# ─────────────────────────────────────────────

func serialize() -> Dictionary:
    var serialized_data : Dictionary = super.serialize()
    serialized_data["color_on"]  = { "r": color_on.r,  "g": color_on.g,  "b": color_on.b,  "a": color_on.a  }
    serialized_data["color_off"] = { "r": color_off.r, "g": color_off.g, "b": color_off.b, "a": color_off.a }
    return serialized_data

func deserialize(d: Dictionary) -> void:
    super.deserialize(d)

    if d.has("color_on"):
        var c: Dictionary = d["color_on"]
        color_on = Color(c["r"], c["g"], c["b"], c["a"])

    if d.has("color_off"):
        var c: Dictionary = d["color_off"]
        color_off = Color(c["r"], c["g"], c["b"], c["a"])
