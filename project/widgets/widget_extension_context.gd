# widget_extension_context.gd
class_name WidgetExtensionContext
extends RefCounted

var _registry:     WeakRef
var _descriptor_id: String
var _install_path:  String

func _init(registry: Node, descriptor_id: String = "", install_path: String = "") -> void:
    _registry      = weakref(registry)
    _descriptor_id = descriptor_id
    _install_path  = install_path

## Absolute path to this extension's extracted install directory,
## for loading auxiliary resources (e.g. resources/default_theme.tres).
func get_install_path() -> String:
    return _install_path

## The id declared in this extension's own manifest.json.
func get_extension_id() -> String:
    return _descriptor_id

## Allows a single package to register additional widget types beyond
## its primary entry_scene (e.g. a "Forms" pack registering several
## related widgets from one plugin.gd).
func register_additional_widget(descriptor: WidgetExtensionDescriptor) -> bool:
    var registry: Node = _registry.get_ref()
    if registry == null:
        return false
    return registry.call("_register_descriptor", descriptor)

## Scoped logging so extension diagnostics are identifiable in the console.
func log_info(message: String) -> void:
    print("[Extension:%s] %s" % [_descriptor_id, message])

func log_warning(message: String) -> void:
    push_warning("[Extension:%s] %s" % [_descriptor_id, message])
