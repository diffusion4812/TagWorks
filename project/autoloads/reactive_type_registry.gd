extends Node

## Maps a Reactive class's global_name (e.g. "ReactiveDynamicField") to its Script.
## This registry only grows when a NEW KIND OF REACTIVE FIELD is introduced —
## never when a new widget is added. Widgets simply compose existing entries.
var _registry: Dictionary = {}

func _ready() -> void:
    register("ReactiveString",          ReactiveString)
    register("ReactiveInt",             ReactiveInt)
    register("ReactiveBool",            ReactiveBool)
    register("ReactiveFloat",           ReactiveFloat)
    register("ReactiveVariant",         ReactiveVariant)
    register("ReactiveVector2",         ReactiveVector2)
    register("ReactiveDictionary",      ReactiveDictionary)
    register("ReactiveDynamicField",    ReactiveDynamicField)
    register("ReactiveActionBinding",   ReactiveActionBinding)
    register("ReactiveOpcUaTagBinding", ReactiveOpcUaTagBinding)
    register("ReactiveOpcUaWriteTarget",ReactiveOpcUaWriteTarget)

func register(type_name: String, script: Script) -> void:
    _registry[type_name] = script

func create(type_name: String) -> Reactive:
    if not _registry.has(type_name):
        push_error("ReactiveTypeRegistry: unknown reactive type '%s'" % type_name)
        return null
    return _registry[type_name].new() as Reactive
