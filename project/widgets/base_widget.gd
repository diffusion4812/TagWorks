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
# Reactive Data
# ─────────────────────────────────────────────

## The reactive data object backing this widget instance.
var data: ReactiveWidget = null

# ─────────────────────────────────────────────
# Container Properties
# ─────────────────────────────────────────────

var container_name: String = "Container":
    set(value):
        container_name = value
        if data != null:
            data.properties.value["container_name"] = value

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
    add_to_group("widgets")
    _raw_position = position

    if is_container:
        z_index = Z_INDEX_BASE

    # React to property change intents targeting this widget
    IntentBus.change_widget_property_requested.connect(_on_change_widget_property_requested)


## Initialises this widget from a ReactiveWidget data object.
func init(widget_data: ReactiveWidget) -> void:
    data         = widget_data
    widget_label = data.widget_name.value
    position     = data.position.value
    size         = data.size.value
    z_index      = data.z_index.value

    if is_container:
        container_name = data.properties.value.get("container_name", "Container")

    _apply_properties(data.properties.value)

    # Keep ReactiveWidget in sync with scene node movement and resizing
    widget_moved.connect(_on_widget_moved)
    widget_resized.connect(_on_widget_resized)

    # React to external reactive data changes
    data.position.reactive_changed.connect(_on_reactive_position_changed)
    data.size.reactive_changed.connect(_on_reactive_size_changed)

# ─────────────────────────────────────────────
# Virtuals
# ─────────────────────────────────────────────

func get_widget_class() -> String:
    return "BaseWidget"


func update_display(_value: Variant) -> void:
    pass


func build_properties(builder: WidgetPropertyBuilder) -> void:
    builder.add_float_field("position/x", "Pos X", position.x)
    builder.add_float_field("position/y", "Pos Y", position.y)
    builder.add_float_field("size/x",     "Size X", size.x)
    builder.add_float_field("size/y",     "Size Y", size.y)

    if is_container:
        builder.add_string_field("container_name", "Name", container_name)


func get_drop_target() -> Control:
    return self if is_container else null


func get_protected_controls() -> Array[Control]:
    return []


func _apply_properties(props: Dictionary) -> void:
    pass

# ─────────────────────────────────────────────
# Property Changes
# ─────────────────────────────────────────────

## Receives property change intents from IntentBus.
## Ignores intents not targeting this widget instance.
func _on_change_widget_property_requested(widget_id: String, property: String, value: Variant) -> void:
    if data == null or data.widget_id.value != widget_id:
        return
    _apply_property(property, value)

func _on_widget_moved(_control: SelectableControl) -> void:
    data.position.value = position


func _on_widget_resized(_control: SelectableControl) -> void:
    data.position.value = position
    data.size.value     = size


func _on_reactive_position_changed(_reactive) -> void:
    position = data.position.value


func _on_reactive_size_changed(_reactive) -> void:
    size = data.size.value

## Applies a single property change to the reactive data object and
## updates the live scene display. The mutation on data propagates
## automatically via the reactive changed signal.
func _apply_property(property: String, value: Variant) -> void:
    if data == null:
        return

    match property:
        "position/x":
            position.x          = value
            data.position.value = position
        "position/y":
            position.y          = value
            data.position.value = position
        "size/x":
            size.x          = value
            data.size.value = size
        "size/y":
            size.y          = value
            data.size.value = size
        "container_name":
            container_name = value
        _:
            data.properties.value[property] = value
            _apply_properties({ property: value })

# ─────────────────────────────────────────────
# Container Behaviour
# ─────────────────────────────────────────────

func _elevate_child(child: Control) -> void:
    if is_container:
        child.z_index = z_index + 1

# ─────────────────────────────────────────────
# Selection
# ─────────────────────────────────────────────

func _apply_selected_style(active: bool) -> void:
    modulate = Color(1.2, 1.2, 1.2) if active else Color.WHITE

# ─────────────────────────────────────────────
# Serialisation
# ─────────────────────────────────────────────

func serialize() -> Dictionary:
    if data == null:
        data = ReactiveWidget.create(get_widget_class(), widget_label)

    data.widget_type.value = get_widget_class()
    data.widget_name.value = widget_label
    data.position.value    = position
    data.size.value        = size
    data.z_index.value     = z_index

    if is_container:
        data.properties.value["container_name"] = container_name
        data.children.clear()
        for child_data: ReactiveWidget in _serialize_children(self):
            data.children.append(child_data)

    return data.serialize()


func _serialize_children(root: Control) -> Array[ReactiveWidget]:
    var result: Array[ReactiveWidget] = []
    for child in root.get_children():
        if child is BaseWidget:
            var child_widget := child as BaseWidget
            child_widget.serialize()
            if child_widget.data != null:
                result.append(child_widget.data)
    return result


func deserialize(payload: Dictionary) -> void:
    super.deserialize(payload)

    data = ReactiveWidget.from_dict(payload)
    if data == null:
        push_warning("BaseWidget: Failed to deserialize ReactiveWidget for '%s'." % name)
        return

    widget_label = data.widget_name.value
    position     = data.position.value
    size         = data.size.value
    z_index      = data.z_index.value

    if is_container:
        container_name = data.properties.value.get("container_name", "Container")

    _apply_properties(data.properties.value)
