class_name ReactiveCanvas
extends Reactive

var widgets  : ReactiveArray      # serialised widget layout
var selected_widget : ReactiveWidget
var is_dirty : ReactiveBool       # unsaved changes

func _init(data: Dictionary = {}, initial_owner: Reactive = null, label: String = "ReactiveCanvas") -> void:
    super._init(initial_owner)

    widgets  = ReactiveArray.new([], self)
    selected_widget = ReactiveWidget.new(null, self)
    is_dirty = ReactiveBool.new(false, self)

    if not data.is_empty():
        from_data(data)


func from_data(data: Dictionary) -> void:
    widgets.clear()
    for widget_data: Dictionary in data.get("widgets", []):
        widgets.append(widget_data)


func to_data() -> Dictionary:
    var result: Array = []
    for item: Variant in widgets.values():
        result.append(item)
    return { "widgets": result }
