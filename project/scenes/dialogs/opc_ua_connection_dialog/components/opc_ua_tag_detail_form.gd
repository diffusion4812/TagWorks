# ui/components/opc_ua_tag_detail_form.gd
class_name OpcUaTagDetailForm
extends VBoxContainer

signal edited
signal browse_requested

@onready var node_id_edit:      LineEdit = %NodeIdEdit
@onready var browse_tag_button: Button   = %BrowseTagButton
@onready var tag_name_edit:     LineEdit = %TagNameEdit
@onready var is_active_check:   CheckBox = %IsActiveCheck
@onready var sampling_spin:     SpinBox  = %SamplingSpin
@onready var deadband_spin:     SpinBox  = %DeadbandSpin

var _loading: bool = false

func _ready() -> void:
    # node_id is populated exclusively via Browse — read-only by design,
    # consistent with the property-panel tag_edit pattern.
    node_id_edit.editable = false

    browse_tag_button.pressed.connect(_on_browse_tag_pressed)
    tag_name_edit.focus_exited.connect(_emit_edited)
    is_active_check.toggled.connect(_emit_edited.unbind(1))
    sampling_spin.value_changed.connect(_emit_edited.unbind(1))
    deadband_spin.value_changed.connect(_emit_edited.unbind(1))


func _emit_edited() -> void:
    if _loading:
        return
    edited.emit()


func _on_browse_tag_pressed() -> void:
    browse_requested.emit()

# ── Public API ─────────────────────────────────────────────────────────────

func load_config(tag: ReactiveOpcUaTag) -> void:
    _loading = true
    node_id_edit.text               = tag.node_id.value if tag.node_id.value != "" else "(none)"
    tag_name_edit.text               = tag.display_name.value
    is_active_check.button_pressed   = tag.is_active.value
    sampling_spin.value               = tag.sampling_ms.value
    deadband_spin.value                = tag.deadband.value
    _loading = false


func commit_to(tag: ReactiveOpcUaTag) -> void:
    # node_id is committed separately via apply_picked_node_id(), since it's
    # not directly editable in this form.
    tag.node_id.value        = node_id_edit.text
    tag.display_name.value   = tag_name_edit.text.strip_edges()
    tag.is_active.value      = is_active_check.button_pressed
    tag.sampling_ms.value    = sampling_spin.value
    tag.deadband.value       = deadband_spin.value


## Called by the parent dialog's browse callback once a node is picked.
func apply_picked_node_id(node_id: OpcUaNodeId) -> void:
    node_id_edit.text = node_id.to_tag_name()
    edited.emit()
