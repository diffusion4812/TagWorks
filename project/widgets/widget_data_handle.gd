class_name WidgetDataHandle
extends RefCounted

var _reactive_widget: ReactiveWidget

func _init(reactive_widget: ReactiveWidget) -> void:
    _reactive_widget = reactive_widget

var widget_id: String:
    get:
        return _reactive_widget.widget_id.value

## The reactive property container. Content scripts pass this as the
## parent reference when constructing Reactive* property instances,
## e.g. ReactiveDynamicField.new("Button", data.properties, "label").
var properties: Variant:
    get:
        return _reactive_widget.properties

func has_property(name: String) -> bool:
    return _reactive_widget.properties.value.has(name)

func get_property(name: String) -> Variant:
    return _reactive_widget.properties.value.get(name)
