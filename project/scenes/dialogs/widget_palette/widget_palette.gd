class_name WidgetPalette
extends PanelContainer

@onready var palette_list: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/PaletteList
@onready var cancel_btn:   Button        = $MarginContainer/VBoxContainer/Button

func _ready() -> void:
    _rebuild_palette()
    AppState.loaded_widget_extensions.connect_self_changed(_on_loaded_widget_extensions_changed)
    cancel_btn.pressed.connect(_on_cancel_pressed)

func _on_loaded_widget_extensions_changed(_extensions: ReactiveDictionary) -> void:
    _rebuild_palette()

func _rebuild_palette() -> void:
    for child: Node in palette_list.get_children():
        child.queue_free()

    var descriptors: Array = AppState.loaded_widget_extensions.value.values()
    descriptors.sort_custom(func(a: WidgetExtensionDescriptor, b: WidgetExtensionDescriptor) -> bool:
        return a.display_name < b.display_name
    )

    for descriptor: WidgetExtensionDescriptor in descriptors:
        if descriptor.host_scene == null:
            continue  # not yet baked into a spawnable scene

        var btn: Button = Button.new()
        btn.text                  = descriptor.display_name
        btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        if descriptor.icon != null:
            btn.icon = descriptor.icon
        btn.pressed.connect(
            func() -> void:
                IntentBus.add_widget_requested.emit(descriptor.host_scene)
        )
        palette_list.add_child(btn)

func _on_cancel_pressed() -> void:
    hide()
