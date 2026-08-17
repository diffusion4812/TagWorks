class_name PluginWidgetHost
extends BaseWidget

@export var plugin_id: String = ""  # baked at registration time — see below

var _content: Control = null

func get_widget_class() -> String:
    return plugin_id

func init(widget_data: ReactiveWidget) -> void:
    var descriptor: WidgetExtensionDescriptor = AppState.loaded_widget_extensions.get_entry(plugin_id)
    if descriptor != null:
        is_container = descriptor.is_container
        widget_label = descriptor.display_name

    super.init(widget_data)
    _instantiate_content(descriptor)
    AppState.edit_mode.connect_self_changed(_on_edit_mode_changed)
    _update_content_input_mode(AppState.edit_mode.value)

func _instantiate_content(descriptor: WidgetExtensionDescriptor) -> void:
    if descriptor == null or descriptor.content_scene == null:
        push_error("PluginWidgetHost: no valid descriptor for '%s'." % plugin_id)
        return
    _content = descriptor.content_scene.instantiate() as Control
    _content.set_anchors_preset(Control.PRESET_FULL_RECT)
    %ContentSlot.add_child(_content)
    if _content.has_method("on_widget_ready"):
        _content.call("on_widget_ready", data)
    if _content.has_method("on_edit_mode_changed"):
        AppState.edit_mode.connect_self_changed(func(edit_mode: ReactiveBool) -> void: _content.call("on_edit_mode_changed", edit_mode.value))

func build_properties(builder: WidgetPropertyBuilder) -> void:
    if _content != null and _content.has_method("build_properties"):
        _content.call("build_properties", builder)

func get_drop_target() -> Control:
    if is_container and _content != null and _content.has_method("get_content_drop_target"):
        return _content.call("get_content_drop_target")
    return super.get_drop_target()

func _on_edit_mode_changed(edit_mode: ReactiveBool) -> void:
    _update_content_input_mode(edit_mode.value)

func _update_content_input_mode(edit_mode: bool) -> void:
    if _content != null:
        _content.mouse_filter = Control.MOUSE_FILTER_IGNORE if edit_mode else Control.MOUSE_FILTER_STOP
