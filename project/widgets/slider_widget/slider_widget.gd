# widgets/slider_widget/slider_widget.gd
class_name SliderWidget
extends BaseWidget

# ─────────────────────────────────────────────
# Exports
# ─────────────────────────────────────────────

@export var min_value:  float  = 0.0
@export var max_value:  float  = 100.0
@export var step:       float  = 0.1
@export var unit:       String = ""      ## Optional unit suffix, e.g. "rpm" or "°C"

# ─────────────────────────────────────────────
# Node references
# ─────────────────────────────────────────────

@onready var label:       Label   = $VBox/Label
@onready var slider:      HSlider = $VBox/HSlider
@onready var value_label: Label   = $VBox/ValueLabel

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
    super._ready()

    # Configure slider range and step.
    slider.min_value = min_value
    slider.max_value = max_value
    slider.step      = step

    # Header label from base widget.
    label.text = widget_label

    # Reflect read-only state: a read-only slider is purely a display gauge.
    #slider.editable = not read_only

    # Populate with whatever the manager already has cached (may be null).
    #var cached: Variant = OpcUaManager.get_tag_value(node_id)
    #if cached != null:
    #    _apply_value(float(cached))

    # Wire signals.
    slider.drag_ended.connect(_on_drag_ended)

    # React to live tag updates from the manager.
    OpcUaManager.tag_value_changed.connect(_on_tag_value_changed)


func _exit_tree() -> void:
    if OpcUaManager.tag_value_changed.is_connected(_on_tag_value_changed):
        OpcUaManager.tag_value_changed.disconnect(_on_tag_value_changed)

# ─────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────

## Called by the base widget or externally to push a new value into the display.
func update_display(value: Variant) -> void:
    _apply_value(float(value))

# ─────────────────────────────────────────────
# Internal helpers
# ─────────────────────────────────────────────

## Update slider position and value label without triggering a write.
func _apply_value(v: float) -> void:
    slider.set_value_no_signal(v)
    _refresh_value_label(v)


## Format and set the value label, including quality tint and optional unit.
func _refresh_value_label(v: float) -> void:
    var suffix: String = (" " + unit) if not unit.is_empty() else ""
    value_label.text = "%.2f%s" % [v, suffix]

    # Dim the label when the tag quality is bad so the operator can tell
    # the displayed value may be stale.
    #if OpcUaManager.is_tag_quality_good(node_id):
    #    value_label.modulate = Color.WHITE
    #else:
    #    value_label.modulate = Color(1.0, 0.6, 0.6)   # soft red tint

# ─────────────────────────────────────────────
# Signal handlers
# ─────────────────────────────────────────────

## Fires when the user releases the slider thumb.
func _on_drag_ended(value_changed: bool) -> void:
    pass
    #if read_only or not value_changed:
    #    return

    #var ok: bool = OpcUaManager.write_tag(node_id, slider.value)
    #if not ok:
    #    push_warning(
    #        "SliderWidget: write failed for node '%s'" % node_id.to_tag_name()
    #    )
        # Roll back slider to the last confirmed server value.
    #    var last: Variant = OpcUaManager.get_tag_value(node_id)
    #    if last != null:
    #        _apply_value(float(last))


## Receives batched tag-change notifications from the manager.
## Ignores updates for tags that do not belong to this widget.
func _on_tag_value_changed(changed_node_id: OpcUaNodeId, value: Variant) -> void:
    #if changed_node_id.to_tag_name() != node_id.to_tag_name():
    #    return
    #_apply_value(float(value))
    pass
