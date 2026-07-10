# widgets/label_widget/label_widget.gd
class_name LabelWidget
extends BaseWidget

@onready var label_node: Label = $MarginContainer/ContentSlot/Label

# ─────────────────────────────────────────────
# Properties
# ─────────────────────────────────────────────

var text: String = "Label":
    set(value):
        text = value
        if is_node_ready():
            label_node.text = value

var font_size: int = 16:
    set(value):
        font_size = value
        if is_node_ready():
            label_node.add_theme_font_size_override("font_size", value)

var font_color: Color = Color.WHITE:
    set(value):
        font_color = value
        if is_node_ready():
            label_node.add_theme_color_override("font_color", value)

var horizontal_alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT:
    set(value):
        horizontal_alignment = value
        if is_node_ready():
            label_node.horizontal_alignment = value

var vertical_alignment: VerticalAlignment = VERTICAL_ALIGNMENT_CENTER:
    set(value):
        vertical_alignment = value
        if is_node_ready():
            label_node.vertical_alignment = value

var autowrap: bool = false:
    set(value):
        autowrap = value
        if is_node_ready():
            label_node.autowrap_mode = \
                TextServer.AUTOWRAP_WORD_SMART if value else TextServer.AUTOWRAP_OFF

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
    super._ready()
    label_node.text                    = text
    label_node.horizontal_alignment    = horizontal_alignment
    label_node.vertical_alignment      = vertical_alignment
    label_node.autowrap_mode           = \
        TextServer.AUTOWRAP_WORD_SMART if autowrap else TextServer.AUTOWRAP_OFF
    label_node.add_theme_font_size_override("font_size", font_size)
    label_node.add_theme_color_override("font_color", font_color)

# ─────────────────────────────────────────────
# Display
# ─────────────────────────────────────────────

## Accepts any Variant and displays it as a string.
## Allows this widget to be bound to an OPC-UA node if needed.
func update_display(value: Variant) -> void:
    text = str(value)

# ─────────────────────────────────────────────
# Class
# ─────────────────────────────────────────────

func get_widget_class() -> String:
    return "LabelWidget"

# ─────────────────────────────────────────────
# Edit Mode
# ─────────────────────────────────────────────

func build_properties(builder: WidgetPropertyBuilder) -> void:
    builder.add_string_field("text",                "Text",                 text)
    builder.add_int_field(   "font_size",            "Font Size",            font_size)
    builder.add_color_field( "font_color",           "Font Color",           font_color)
    builder.add_int_field(   "horizontal_alignment", "Horizontal Alignment", horizontal_alignment)
    builder.add_int_field(   "vertical_alignment",   "Vertical Alignment",   vertical_alignment)
    builder.add_bool_field(  "autowrap",             "Autowrap",             autowrap)

# ─────────────────────────────────────────────
# Serialization
# ─────────────────────────────────────────────

func serialize() -> Dictionary:
    var data := super.serialize()
    data["text"]                 = text
    data["font_size"]            = font_size
    data["font_color"]           = { "r": font_color.r, "g": font_color.g, "b": font_color.b, "a": font_color.a }
    data["horizontal_alignment"] = horizontal_alignment
    data["vertical_alignment"]   = vertical_alignment
    data["autowrap"]             = autowrap
    return data


func deserialize(data: Dictionary) -> void:
    super.deserialize(data)
    text                 = data.get("text",                 "Label")
    font_size            = data.get("font_size",            16)
    horizontal_alignment = data.get("horizontal_alignment", HORIZONTAL_ALIGNMENT_LEFT)
    vertical_alignment   = data.get("vertical_alignment",   VERTICAL_ALIGNMENT_CENTER)
    autowrap             = data.get("autowrap",             false)

    if data.has("font_color"):
        var c: Dictionary = data["font_color"]
        font_color = Color(c["r"], c["g"], c["b"], c["a"])
