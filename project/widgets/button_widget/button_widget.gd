# widgets/button_widget/button_widget.gd
class_name ButtonWidget
extends BaseWidget

@onready var button: Button = $MarginContainer/ContentSlot/Button

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
    super._ready()

    # Sync + wire anything that touches actual view nodes here,
    # since @onready vars are only guaranteed valid after this point.
    var label_field: ReactiveDynamicField = data.properties.value["label"]
    button.text = str(label_field.resolved.value)

    if not button.pressed.is_connected(_on_button_pressed):
        button.pressed.connect(_on_button_pressed)

    AppState.edit_mode.connect_self_changed(_on_edit_mode_changed)
    _on_edit_mode_changed(AppState.edit_mode)

func _define_default_properties() -> void:
    super._define_default_properties()
    _ensure_property("label", func() -> ReactiveDynamicField:
        return ReactiveDynamicField.new("Button", data.properties, "label")
    )
    _ensure_property("on_click", func() -> ReactiveActionBinding:
        return ReactiveActionBinding.new({}, data.properties, "on_click")
    )

func _connect_data_signals() -> void:
    # Safe to run early — this only registers a listener; the callback
    # itself won't fire until later, by which point button is valid.
    var label_field: ReactiveDynamicField = data.properties.value["label"]
    label_field.set_context_provider(_build_script_context)
    label_field.resolved.connect_self_changed(func(r: ReactiveVariant) -> void:
        if is_instance_valid(button):
            button.text = str(r.value)
    )

func _build_script_context() -> Dictionary:
    return { "id": data.widget_id.value }

func _on_button_pressed() -> void:
    var action: ReactiveActionBinding = data.properties.value["on_click"]
    action.execute({ "widget_id": data.widget_id.value })

func build_properties(builder: WidgetPropertyBuilder) -> void:
    super.build_properties(builder)
    builder.add_dynamic_field("label", "Label", data.properties)
    builder.add_action_field("on_click", "On Click", data.properties)

# ─────────────────────────────────────────────
# Signal Handlers
# ─────────────────────────────────────────────

func _on_value_changed(value: Variant) -> void:
    update_display(value)

func _on_edit_mode_changed(enabled: ReactiveBool) -> void:
    button.disabled     = enabled.value
    button.mouse_filter = Control.MOUSE_FILTER_IGNORE if enabled.value else Control.MOUSE_FILTER_STOP

# ─────────────────────────────────────────────
# Class
# ─────────────────────────────────────────────

func get_widget_class() -> String:
    return "ButtonWidget"

# ─────────────────────────────────────────────
# Serialization
# ─────────────────────────────────────────────

func serialize() -> Dictionary:
    var serialized_data: Dictionary = super.serialize()
    return serialized_data

func deserialize(serialized_data: Dictionary) -> void:
    super.deserialize(serialized_data)
