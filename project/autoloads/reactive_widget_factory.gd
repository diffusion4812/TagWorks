extends Node

func _ready() -> void:
    pass
    #register("button", ButtonWidget)
    #register("label",  LabelWidget)

## Registry mapping widget_type string → GDScript Script (the class to instantiate).
## Populate this once at startup (e.g. in an autoload's _ready()).
var _registry: Dictionary = {}

func register(widget_type: String, script: Script) -> void:
    _registry[widget_type] = script

func create(data: Dictionary) -> ReactiveWidget:
    var widget_type: String = data.get("widget_type", "")
    if not _registry.has(widget_type):
        push_error("ReactiveWidgetFactory: no registered class for widget_type '%s'" % widget_type)
        return null

    var script: Script = _registry[widget_type]
    var instance: ReactiveWidget = script.new() as ReactiveWidget
    instance.deserialize(data)
    return instance
