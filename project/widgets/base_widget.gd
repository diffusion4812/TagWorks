# widgets/base_widget/base_widget.gd
class_name BaseWidget
extends SelectableControl

const MIN_SIZE: Vector2 = Vector2(10.0, 10.0)
const Z_INDEX_BASE: int = 0

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


## Initialises this widget from a ReactiveWidget data object.
func init(widget_data: ReactiveWidget) -> void:
    data         = widget_data
    _define_default_properties()
    _connect_data_signals()
    widget_label = data.widget_name.value
    position     = data.properties.value["position"].value
    size         = data.properties.value["size"].value
    z_index      = data.z_index.value

    if is_container:
        container_name = data.properties.value.get("container_name", "Container")

    # Keep ReactiveWidget in sync with scene node movement and resizing
    widget_moved.connect(_on_widget_moved)
    widget_resized.connect(_on_widget_resized)

    # React to external reactive data changes
    data.properties.value["position"].connect_self_changed(_on_reactive_position_changed)
    data.properties.value["size"].connect_self_changed(_on_reactive_size_changed)

# ─────────────────────────────────────────────
# Virtuals
# ─────────────────────────────────────────────

func get_widget_class() -> String:
    return "BaseWidget"


func update_display(_value: Variant) -> void:
    pass


## Overridden per concrete widget type. Must only set a property if it
## doesn't already exist, so loaded/saved widgets aren't overwritten.
func _define_default_properties() -> void:
    _ensure_property("size", func() -> ReactiveVector2:
        return ReactiveVector2.new(Vector2(80, 20), data.properties, "size")
    )
    _ensure_property("position", func() -> ReactiveVector2:
        return ReactiveVector2.new(get_parent_area_size() / 2.0 - data.properties.value["size"].value / 2.0, data.properties, "position")
    )

func _ensure_property(id: String, factory: Callable) -> void:
    if not data.properties.value.has(id):
        data.properties.value[id] = factory.call()

func _connect_data_signals() -> void:
    pass # set up per-property reactive_changed listeners if needed


func build_properties(builder: WidgetPropertyBuilder) -> void:
    pass
    #builder.add_float_field("position/x", "Pos X",  widget.properties["position/x"].value)
    #builder.add_float_field("position/y", "Pos Y",  widget.properties["position/y"].value)
    #builder.add_float_field("size/x",     "Size X", widget.properties["size/x"].value)
    #builder.add_float_field("size/y",     "Size Y", widget.properties["size/y"].value)

func _on_property_changed(p: String, v: Variant) -> void:
    pass

func get_drop_target() -> Control:
    return self if is_container else null


func get_protected_controls() -> Array[Control]:
    return []

# ─────────────────────────────────────────────
# Property Changes
# ─────────────────────────────────────────────

func _on_widget_moved(_widget: SelectableControl) -> void:
    data.properties.value["position"].value = position


func _on_widget_resized(_widget: SelectableControl) -> void:
    data.properties.value["position"].value = position
    data.properties.value["size"].value     = size


func _on_reactive_position_changed(reactive_position: ReactiveVector2) -> void:
    position = reactive_position.value


func _on_reactive_size_changed(reactive_size: ReactiveVector2) -> void:
    size = reactive_size.value

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
    for child: Node in root.get_children():
        if child is BaseWidget:
            var child_widget: BaseWidget = child as BaseWidget
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
