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

var properties  : ReactiveDictionary
var node_id     : ReactiveString
var server_id   : ReactiveString

# ── Init ──────────────────────────────────────────────────────────────────────

func _init(data: WidgetData = null, initial_owner: Reactive = null) -> void:
    super._init(null, initial_owner)

    widget_id   = ReactiveString.new("",                 self)
    widget_type = ReactiveString.new("",                 self)
    widget_name = ReactiveString.new("",                 self)
    position    = ReactiveVector2.new(Vector2.ZERO,      self)
    size        = ReactiveVector2.new(Vector2(100, 100), self)
    z_index     = ReactiveInt.new(0,                     self)
    parent_id   = ReactiveString.new("",                 self)
    properties  = ReactiveDictionary.new({},             self)
    node_id     = ReactiveString.new("",                 self)
    server_id   = ReactiveString.new("",                 self)
    children    = ReactiveArray.new([],                  self)

    if data != null:
        from_data(data)

# ── Sync from WidgetData ──────────────────────────────────────────────────────

func from_data(data: WidgetData) -> void:
    widget_id.value   = data.widget_id
    widget_type.value = data.widget_type
    widget_name.value = data.widget_name
    position.value    = data.position
    size.value        = data.size
    z_index.value     = data.z_index
    parent_id.value   = data.parent_id
    properties.value  = data.properties.duplicate()
    node_id.value     = data.node_id
    server_id.value   = data.server_id

    children.clear()
    for child: WidgetData in data.children:
        children.append(ReactiveWidget.new(child, self))

    value = data

# ── Sync back to WidgetData ───────────────────────────────────────────────────

func to_data() -> WidgetData:
    var data         := WidgetData.new()
    data.widget_id   = widget_id.value
    data.widget_type = widget_type.value
    data.widget_name = widget_name.value
    data.position    = position.value
    data.size        = size.value
    data.z_index     = z_index.value
    data.parent_id   = parent_id.value
    data.properties  = properties.value.duplicate()
    data.node_id     = node_id.value
    data.server_id   = server_id.value

    data.children.clear()
    for item: Variant in children.values():
        var child := item as ReactiveWidget
        if child != null:
            data.children.append(child.to_data())

    return data

# ── Helpers ───────────────────────────────────────────────────────────────────

func is_bound() -> bool:
    return node_id.value != "" and server_id.value != ""


func is_container() -> bool:
    return not children.values().is_empty()
