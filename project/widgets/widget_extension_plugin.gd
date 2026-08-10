class_name WidgetExtensionPlugin
extends RefCounted

## Called once after manifest validation and file extraction succeed.
func on_load(_context: WidgetExtensionContext) -> void:
    pass

## Called when the extension is removed/disabled at runtime.
func on_unload(_context: WidgetExtensionContext) -> void:
    pass
