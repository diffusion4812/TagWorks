# widgets/button_widget/button_widget.gd
class_name ButtonWidget
extends BaseWidget

@onready var button: Button = $MarginContainer/ContentSlot/Button

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
    super._ready()
    button.text = data.properties.value["label"].value

    AppState.edit_mode.connect_self_changed(_on_edit_mode_changed)
    _on_edit_mode_changed(AppState.edit_mode)

func _define_default_properties() -> void:
    super._define_default_properties()
    _ensure_property("label", func() -> ReactiveString:
        return ReactiveString.new("Button", data.properties, "label")
    )
    _ensure_property("node_id", func() -> ReactiveOpcUaTagBinding:
        return ReactiveOpcUaTagBinding.new({}, data.properties, "node_id")
    )

func _connect_data_signals() -> void:
    data.properties.value["label"].connect_self_changed(
        func(s: ReactiveString) -> void:
            button.text = s.value
    )

# ─────────────────────────────────────────────
# Signal Handlers
# ─────────────────────────────────────────────

func _on_value_changed(value: Variant) -> void:
    update_display(value)

func _on_edit_mode_changed(enabled: ReactiveBool) -> void:
    button.disabled     = enabled.value
    button.mouse_filter = Control.MOUSE_FILTER_IGNORE if enabled.value else Control.MOUSE_FILTER_STOP

func _on_property_changed(p: String, v: Variant) -> void:
    data.properties.value[p].value = v

# ─────────────────────────────────────────────
# Class
# ─────────────────────────────────────────────

func get_widget_class() -> String:
    return "ButtonWidget"

# ─────────────────────────────────────────────
# Edit Mode
# ─────────────────────────────────────────────

func build_properties(builder: WidgetPropertyBuilder) -> void:
    super.build_properties(builder)
    builder.add_string_field("label", "Label",  data.properties)
    builder.add_node_field("node_id", "Node ID",  data.properties)

# ─────────────────────────────────────────────
# Serialization
# ─────────────────────────────────────────────

func serialize() -> Dictionary:
    var serialized_data: Dictionary = super.serialize()
    return serialized_data

func deserialize(serialized_data: Dictionary) -> void:
    super.deserialize(serialized_data)
