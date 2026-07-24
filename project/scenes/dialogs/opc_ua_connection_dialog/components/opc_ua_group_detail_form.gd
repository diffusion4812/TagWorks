# ui/components/opc_ua_group_detail_form.gd
class_name OpcUaGroupDetailForm
extends VBoxContainer

signal edited

@onready var group_name_edit:     LineEdit = %GroupNameEdit
@onready var group_interval_spin: SpinBox  = %GroupIntervalSpin

var _loading: bool = false

func _ready() -> void:
    group_name_edit.focus_exited.connect(_emit_edited)
    group_interval_spin.value_changed.connect(_emit_edited.unbind(1))


func _emit_edited() -> void:
    if _loading:
        return
    edited.emit()

# ── Public API ─────────────────────────────────────────────────────────────

func load_config(group: ReactiveOpcUaGroup) -> void:
    _loading = true
    group_name_edit.text      = group.display_name.value
    group_interval_spin.value = group.pub_interval_ms.value
    _loading = false


func commit_to(group: ReactiveOpcUaGroup) -> void:
    group.display_name.value    = group_name_edit.text.strip_edges()
    group.pub_interval_ms.value = group_interval_spin.value
