# reactive/reactive_widget.gd
class_name ReactiveWidget
extends ReactiveObject

# ── Identity ──────────────────────────────────────────────────────────────────

var widget_id   : ReactiveString
var widget_type : ReactiveString
var widget_name : ReactiveString

# ── Layout ────────────────────────────────────────────────────────────────────

var position    : ReactiveVector2
var size        : ReactiveVector2
var z_index     : ReactiveInt

# ── Hierarchy ─────────────────────────────────────────────────────────────────

var parent_id   : ReactiveString
var children    : ReactiveArray

# ── Properties & Binding ──────────────────────────────────────────────────────

var properties  : ReactiveDictionary # String -> ReactiveVariant
var node_id     : ReactiveString
var server_id   : ReactiveString

# ── Init ──────────────────────────────────────────────────────────────────────

func _init(initial_value: Variant = null, initial_owner: Reactive = null, label: String = "") -> void:
    super._init(initial_value, initial_owner, label)

    widget_id   = ReactiveString.new("",                 self, "widget_id")
    widget_type = ReactiveString.new("",                 self, "widget_type")
    widget_name = ReactiveString.new("",                 self, "widget_name")
    z_index     = ReactiveInt.new(0,                     self, "z_index")
    parent_id   = ReactiveString.new("",                 self, "parent_id")
    properties  = ReactiveDictionary.new({},             self, "properties")
    node_id     = ReactiveString.new("",                 self, "node_id")
    server_id   = ReactiveString.new("",                 self, "server_id")
    children    = ReactiveArray.new([],                  self, "children")

func _describe_value() -> String:
    return ""

# ── Factory ───────────────────────────────────────────────────────────────────

## Creates a new ReactiveWidget with a generated ID and the given type.
static func create(type: String, name: String = "", initial_value: Variant = null, initial_owner: Reactive = null) -> ReactiveWidget:
    var id : String = _generate_id()
    var w: ReactiveWidget = ReactiveWidget.new(initial_value, initial_owner, type+"_"+id)
    w.widget_id.value     = id
    w.widget_type.value   = type
    w.widget_name.value   = name if name != "" else type
    return w


## Deserialises a ReactiveWidget from a Dictionary.
## Returns null if the payload is invalid.
static func from_dict(payload: Dictionary) -> ReactiveWidget:
    if not _validate(payload):
        return null
    var w: ReactiveWidget = ReactiveWidget.new()
    w.from_data(payload)
    return w

# ── Serialize ─────────────────────────────────────────────────────────────────

func to_data() -> Dictionary:
    var serialised_children: Array = []
    for item: Variant in children.values():
        var child: ReactiveWidget = item as ReactiveWidget
        if child != null:
            serialised_children.append(child.serialize())

    return {
        "widget_id":   widget_id.value,
        "widget_type": widget_type.value,
        "widget_name": widget_name.value,
        "z_index":     z_index.value,
        "parent_id":   parent_id.value,
        "node_id":     node_id.value,
        "server_id":   server_id.value,
        "properties":  properties.serialize(),  # ReactiveDictionary handles recursion itself
        "children":    serialised_children,
    }

# ── Deserialise ───────────────────────────────────────────────────────────────

func from_data(payload: Dictionary) -> void:
    widget_id.value   = payload.get("widget_id",   _generate_id())
    widget_type.value = payload.get("widget_type", "")
    widget_name.value = payload.get("widget_name", widget_type.value)
    z_index.value     = payload.get("z_index",     0)
    parent_id.value   = payload.get("parent_id",   "")
    node_id.value     = payload.get("node_id",     "")
    server_id.value   = payload.get("server_id",   "")
    properties.deserialize(payload.get("properties"))

    children.clear()
    for child_dict: Dictionary in payload.get("children", []):
        var child: ReactiveWidget = ReactiveWidget.from_dict(child_dict)
        if child != null:
            child.owner = self
            children.append(child)


static func _validate(payload: Dictionary) -> bool:
    if payload.is_empty():
        push_warning("ReactiveWidget: Empty payload passed to from_dict().")
        return false
    if not payload.has("widget_type"):
        push_warning("ReactiveWidget: Missing required field 'widget_type'.")
        return false
    return true

# ── Helpers ───────────────────────────────────────────────────────────────────

func is_bound() -> bool:
    return node_id.value != "" and server_id.value != ""


func is_container() -> bool:
    return not children.values().is_empty()


static func _generate_id() -> String:
    return "%s-%s" % [
        Time.get_unix_time_from_system(),
        randi() % 0xFFFF
    ]
