class_name ReactiveCanvas
extends Reactive

var widgets  : ReactiveArray      # serialised widget layout
var is_dirty : ReactiveBool       # unsaved changes

func _init(data: Dictionary = {}, initial_owner: Reactive = null, label: String = "ReactiveCanvas") -> void:
    super._init(initial_owner, label)

    widgets  = ReactiveArray.new([], self, "widgets")
    is_dirty = ReactiveBool.new(false, self, "is_dirty")

    widgets.reactive_changed.connect(
        func(_widgets: ReactiveArray) -> void:
            is_dirty.value = true
    )

    if not data.is_empty():
        from_data(data)


func from_data(data: Dictionary) -> void:
    widgets.clear()
    for widget_data: Dictionary in data.get("widgets", []):
        var widget: ReactiveWidget = ReactiveWidget.from_dict(widget_data)
        widgets.append(widget)


func to_data() -> Dictionary:
    var result: Array = []
    for item: Variant in widgets.values():
        if item is ReactiveWidget:
            result.append(item.to_data())
        else:
            push_warning("ReactiveCanvas: item in widgets is not a BaseWidget — skipping.")
    return { "widgets": result }
