class_name ReactiveCanvas
extends Reactive

var widgets  : ReactiveArray      # serialised widget layout
var is_dirty : ReactiveBool       # unsaved changes

func _init(data: Dictionary = {}, initial_owner: Reactive = null, label: String = "ReactiveCanvas") -> void:
    super._init(initial_owner, label)

    widgets  = ReactiveArray.new([], self, "widgets")
    is_dirty = ReactiveBool.new(false, self, "is_dirty")

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
