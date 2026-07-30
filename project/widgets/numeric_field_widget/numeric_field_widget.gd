# widgets/numeric_field_widget/numeric_field_widget.gd
class_name NumericFieldWidget
extends BaseWidget

@onready var line_edit: LineEdit = $MarginContainer/ContentSlot/LineEdit

# ─────────────────────────────────────────────
# Property Management
# ─────────────────────────────────────────────

var properties: WidgetProperties = WidgetProperties.new()

# ─────────────────────────────────────────────
# Local State
# ─────────────────────────────────────────────

var _decimal_places: int        = 2
var _unit:           String     = ""
var _server_id:      String     = ""
var _group_id:       String     = ""
var _node_id:        OpcUaNodeId = null

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
    super._ready()
    line_edit.text_submitted.connect(_on_text_submitted)
    line_edit.focus_entered.connect(_on_focus_entered)


    _register_properties()
    _apply_binding()


func _register_properties() -> void:
    properties.register("decimal_places",  _decimal_places, _set_decimal_places)
    properties.register("unit",            _unit,           _set_unit)
    properties.register("node_id/server_id", _server_id,   _set_server_id)
    properties.register("node_id/group_id",  _group_id,    _set_group_id)
    properties.register("node_id/node_id",   _node_id,     _set_node_id)

# ─────────────────────────────────────────────
# Setters
# ─────────────────────────────────────────────

func _set_decimal_places(value: int) -> void:
    _decimal_places = value
    update_display(line_edit.text)


func _set_unit(value: String) -> void:
    _unit = value
    update_display(line_edit.text)


func _set_server_id(value: String) -> void:
    _server_id = value


func _set_group_id(value: String) -> void:
    _group_id = value


func _set_node_id(value: OpcUaNodeId) -> void:
    _node_id = value
    _apply_binding()

# ─────────────────────────────────────────────
# Binding
# ─────────────────────────────────────────────

func _apply_binding() -> void:
    if not is_node_ready():
        return
    if _server_id == "" or _group_id == "" or _node_id == null:
        return

# ─────────────────────────────────────────────
# Display
# ─────────────────────────────────────────────

func update_display(value: Variant) -> void:
    if not line_edit.has_focus():
        if value == null:
            line_edit.text = "— %s" % _unit
            return
        var f: float = float(value)
        line_edit.text = "%.*f %s" % [_decimal_places, f, _unit]

# ─────────────────────────────────────────────
# Signal Handlers
# ─────────────────────────────────────────────

func _on_focus_entered() -> void:
    DisplayServer.virtual_keyboard_show(
        line_edit.text,
        Rect2(),
        DisplayServer.KEYBOARD_TYPE_NUMBER_DECIMAL
    )

func _on_text_submitted(_text: String) -> void:
    line_edit.release_focus()
    DisplayServer.virtual_keyboard_hide()

func _on_value_changed(value: Variant) -> void:
    update_display(value)


func _on_edit_mode_changed(enabled: ReactiveBool) -> void:
    line_edit.editable = not enabled

# ─────────────────────────────────────────────
# Class
# ─────────────────────────────────────────────

func get_widget_class() -> String:
    return "NumericFieldWidget"

# ─────────────────────────────────────────────
# Edit Mode
# ─────────────────────────────────────────────

func build_properties(_builder: WidgetPropertyBuilder) -> void:
    pass
   # super.build_properties(builder)
   # builder.add_node_field(  "node_id",        "Node ID",        _node_id, _server_id, _group_id)
   # builder.add_int_field(   "decimal_places",  "Decimal Places", _decimal_places)
   # builder.add_string_field("unit",            "Unit",           _unit)

# ─────────────────────────────────────────────
# Serialization
# ─────────────────────────────────────────────

func serialize() -> Dictionary:
    var serialized_data: Dictionary = super.serialize()
    serialized_data["server_id"]      = _server_id
    serialized_data["group_id"]       = _group_id
    serialized_data["node_id"]        = _node_id.to_tag_name() if _node_id != null else ""
    serialized_data["decimal_places"] = _decimal_places
    serialized_data["unit"]           = _unit
    return serialized_data


func deserialize(serialized_data: Dictionary) -> void:
    super.deserialize(serialized_data)
    # Apply non-binding properties immediately
    properties.apply("decimal_places",    serialized_data.get("decimal_places", 2))
    properties.apply("unit",              serialized_data.get("unit", ""))
    # Apply binding fields last — _apply_binding() fires once node_id is set
    properties.apply("node_id/server_id", serialized_data.get("server_id", ""))
    properties.apply("node_id/group_id",  serialized_data.get("group_id",  ""))
    properties.apply("node_id/node_id",
        OpcUaNodeId.parse(serialized_data["node_id"]) if serialized_data.get("node_id") != "" else null
    )
