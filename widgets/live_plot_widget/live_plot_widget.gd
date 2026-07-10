# widgets/live_plot_widget/live_plot_widget.gd
class_name LivePlotWidget
extends BaseWidget

@onready var live_plot: LivePlot = $MarginContainer/ContentSlot/LivePlot

# ─────────────────────────────────────────────
# Properties
# ─────────────────────────────────────────────

var node_id: OpcUaNodeId = null:
    set(value):
        node_id = value
        if is_instance_valid(_binding):
            _binding.node_id = value

var signal_name: String = "Signal":
    set(value):
        signal_name = value

var signal_color: Color = Color.CYAN:
    set(value):
        signal_color = value
        if is_node_ready():
            live_plot.set_signal_color(signal_name, value)

var signal_axis: int = 0:
    set(value):
        signal_axis = value
        if is_node_ready():
            live_plot.set_signal_axis(signal_name, value)

var _binding: OpcUaBinding

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
    super._ready()

    live_plot.add_signal(signal_name, signal_color, signal_axis)

    _binding = OpcUaBinding.new()
    _binding.value_changed.connect(_on_value_changed)
    add_child(_binding)

    if node_id != null:
        _binding.node_id = node_id

# ─────────────────────────────────────────────
# Signal Handlers
# ─────────────────────────────────────────────

func _on_value_changed(value: Variant) -> void:
    if value == null:
        return
    var f: float = value
    live_plot.push_data(signal_name, f)

func _on_edit_mode_changed(enabled: bool) -> void:
    super._on_edit_mode_changed(enabled)

# ─────────────────────────────────────────────
# Class
# ─────────────────────────────────────────────

func get_widget_class() -> String:
    return "LivePlotWidget"

# ─────────────────────────────────────────────
# Edit Mode
# ─────────────────────────────────────────────

func build_properties(builder: WidgetPropertyBuilder) -> void:
    builder.add_node_field(  "node_id",      "Node ID",      node_id)
    builder.add_string_field("signal_name",  "Signal Name",  signal_name)
    builder.add_color_field( "signal_color", "Signal Color", signal_color)
    builder.add_int_field(   "signal_axis",  "Axis",         signal_axis)

# ─────────────────────────────────────────────
# Serialization
# ─────────────────────────────────────────────

func serialize() -> Dictionary:
    var data := super.serialize()
    data["signal"] = {
        "node_id":      node_id.to_tag_name() if node_id != null else null,
        "signal_name":  signal_name,
        "signal_color": {
            "r": signal_color.r,
            "g": signal_color.g,
            "b": signal_color.b,
            "a": signal_color.a
        },
        "signal_axis":  signal_axis
    }
    return data

func deserialize(data: Dictionary) -> void:
    super.deserialize(data)
    var s: Dictionary = data.get("signal", {})
    node_id      = OpcUaNodeId.parse(s["node_id"]) if s.get("node_id") != null else null
    signal_name  = s.get("signal_name",  signal_name)
    signal_color = Color(
        s.get("signal_color", {}).get("r", 0.0),
        s.get("signal_color", {}).get("g", 1.0),
        s.get("signal_color", {}).get("b", 1.0),
        s.get("signal_color", {}).get("a", 1.0)
    )
    signal_axis  = s.get("signal_axis", signal_axis)
