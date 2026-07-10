# widgets/base_widget/base_widget.gd
class_name BaseWidget
extends SelectableControl

const MIN_SIZE     := Vector2(10.0, 10.0)
const Z_INDEX_BASE := 0

# ─────────────────────────────────────────────
# Exports
# ─────────────────────────────────────────────

@export var widget_label: String = "Widget"

## When true, this widget behaves as a container:
## it manages child elevation and serialises nested children.
@export var is_container: bool = false

# ─────────────────────────────────────────────
# Widget Data
# ─────────────────────────────────────────────

## The serialisable data resource associated with this widget instance.
## Initialised on spawn via init() or populated during deserialize().
var data: WidgetData = null

# ─────────────────────────────────────────────
# Container Properties
# Only meaningful when is_container = true
# ─────────────────────────────────────────────

var container_name: String = "Container":
    set(value):
        container_name = value
        if data != null:
            data.properties["container_name"] = value

# ─────────────────────────────────────────────
# Canvas Reference
# Injected by WidgetCanvas._subscribe_widget()
# ─────────────────────────────────────────────

## Reference to the root WidgetCanvas that owns this widget.
var _root_canvas: WidgetCanvas = null

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
    add_to_group("widgets")
    _raw_position = position

    if is_container:
        z_index = Z_INDEX_BASE

    EventBus.widget_property_changed.connect(_on_widget_property_changed)


## Initialises this widget from a WidgetData resource.
## Called by WidgetCanvas when spawning a new widget.
func init(widget_data: WidgetData) -> void:
    data          = widget_data
    widget_label  = data.widget_name
    position      = data.position
    size          = data.size
    z_index       = data.z_index

    if is_container:
        container_name = data.properties.get("container_name", "Container")

    _apply_properties(data.properties)

# ─────────────────────────────────────────────
# Virtuals
# ─────────────────────────────────────────────

## Override in subclasses to return a unique type identifier.
func get_widget_class() -> String:
    return "BaseWidget"


## Called by child widgets to update their visual display.
func update_display(_value: Variant) -> void:
    pass


## Override to expose widget-specific properties in the property panel.
func build_properties(builder: WidgetPropertyBuilder) -> void:
    builder.add_float_field("position/x", "Pos X", position.x)
    builder.add_float_field("position/y", "Pos Y", position.y)
    builder.add_float_field("size/x",     "Size X", size.x)
    builder.add_float_field("size/y",     "Size Y", size.y)

    if is_container:
        builder.add_string_field("container_name", "Name", container_name)


## Override to provide the Control that accepts dropped children.
## Returns self for containers, null for leaf widgets.
func get_drop_target() -> Control:
    return self if is_container else null


## Override in container subclasses to protect internal structural controls
## and their entire subtrees from the mouse filter sweep.
func get_protected_controls() -> Array[Control]:
    return []


## Override in subclasses to apply widget-specific properties from a Dictionary.
## Called during init() and when a property change is received from the EventBus.
func _apply_properties(props: Dictionary) -> void:
    pass

# ─────────────────────────────────────────────
# Property Changes
# ─────────────────────────────────────────────

## Receives property change events from the EventBus.
## Ignores events not targeting this widget instance.
func _on_widget_property_changed(widget_id: String, property: String, value: Variant) -> void:
    if data == null or data.widget_id != widget_id:
        return
    apply_property(property, value)


## Applies a single property change to both the data resource and the widget display.
func apply_property(property: String, value: Variant) -> void:
    if data == null:
        return

    # Handle reserved layout properties explicitly
    match property:
        "position/x":
            position.x    = value
            data.position = position
        "position/y":
            position.y    = value
            data.position = position
        "size/x":
            size.x    = value
            data.size = size
        "size/y":
            size.y    = value
            data.size = size
        "container_name":
            container_name = value
        _:
            # All other properties are delegated to the subclass
            data.properties[property] = value
            _apply_properties({ property: value })

# ─────────────────────────────────────────────
# Container Behaviour
# ─────────────────────────────────────────────

## Elevates a newly added child above this container's z-index.
func _elevate_child(child: Control) -> void:
    if is_container:
        child.z_index = z_index + 1

# ─────────────────────────────────────────────
# Drag and Drop
# ─────────────────────────────────────────────

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
    if not is_edit_mode:
        return false
    if not is_container:
        return false
    if not data is Dictionary or not data.has("widget"):
        return false

    var widget := data["widget"] as BaseWidget
    if widget == null or widget == self:
        return false

    return not _is_ancestor_of(widget)


func _drop_data(at_position: Vector2, data: Variant) -> void:
    var widget := data["widget"] as BaseWidget
    if widget == null:
        return
    if not is_instance_valid(_root_canvas):
        push_warning("BaseWidget: _root_canvas is not set on '%s', cannot reparent." % name)
        return

    var drop_target := get_drop_target()
    if drop_target == null:
        return

    _root_canvas._reparent_widget(widget, drop_target, at_position)


## Returns true if this node is an ancestor of the given node.
func _is_ancestor_of(node: Node) -> bool:
    var current := node.get_parent()
    while current != null:
        if current == self:
            return true
        current = current.get_parent()
    return false

# ─────────────────────────────────────────────
# Edit Mode
# ─────────────────────────────────────────────

func _on_edit_mode_changed(enabled: bool) -> void:
    if is_container:
        mouse_filter = MOUSE_FILTER_PASS
    else:
        mouse_filter = MOUSE_FILTER_STOP if enabled else MOUSE_FILTER_PASS
    _set_children_mouse_filter(enabled)
    if not enabled and _is_selected:
        deselect()


func _set_children_mouse_filter(edit_mode: bool) -> void:
    var filter    := MOUSE_FILTER_IGNORE if edit_mode else MOUSE_FILTER_STOP
    var protected := get_protected_controls()

    for child in find_children("*", "Control", true, false):
        if child is ResizeHandleContainer or child is ResizeHandle:
            continue
        if child is WidgetCanvas:
            continue
        if _is_under_protected(child, protected):
            continue
        child.mouse_filter = filter


## Returns true if the given node is, or is a descendant of, any protected control.
func _is_under_protected(node: Node, protected: Array[Control]) -> bool:
    var current := node
    while current != null:
        if current in protected:
            return true
        current = current.get_parent()
    return false

# ─────────────────────────────────────────────
# Input
# ─────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
    if is_container and event is InputEventMouseButton \
            and event.button_index == MOUSE_BUTTON_RIGHT:
        return
    super._gui_input(event)

# ─────────────────────────────────────────────
# Selection
# ─────────────────────────────────────────────

func _apply_selected_style(active: bool) -> void:
    modulate = Color(1.2, 1.2, 1.2) if active else Color.WHITE

# ─────────────────────────────────────────────
# Serialisation
# ─────────────────────────────────────────────

## Syncs the current scene state back into the WidgetData resource
## and returns the serialised Dictionary.
func serialize() -> Dictionary:
    if data == null:
        data = WidgetData.create(get_widget_class(), widget_label)

    data.widget_type  = get_widget_class()
    data.widget_name  = widget_label
    data.position     = position
    data.size         = size
    data.z_index      = z_index

    if is_container:
        data.properties["container_name"] = container_name
        data.children                     = _serialize_children(self)

    return data.serialize()


func _serialize_children(root: Control) -> Array[WidgetData]:
    var result: Array[WidgetData] = []
    for child in root.get_children():
        if child is BaseWidget:
            var child_widget := child as BaseWidget
            child_widget.serialize()          # Sync child data first
            if child_widget.data != null:
                result.append(child_widget.data)
    return result


## Restores widget state from a serialised Dictionary via WidgetData.
func deserialize(payload: Dictionary) -> void:
    super.deserialize(payload)

    data = WidgetData.from_dict(payload)
    if data == null:
        push_warning("BaseWidget: Failed to deserialize WidgetData for '%s'." % name)
        return

    widget_label = data.widget_name
    position     = data.position
    size         = data.size
    z_index      = data.z_index

    if is_container:
        container_name = data.properties.get("container_name", "Container")

    _apply_properties(data.properties)
