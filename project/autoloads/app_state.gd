extends Node

var is_edit_mode    : ReactiveBool    = ReactiveBool.new(false, null, "is_edit_mode")
var current_project : ReactiveProject = ReactiveProject.new()
var focused_page    : ReactiveVariant = ReactiveVariant.new(null, null, "focused_page")
var active_page     : ReactiveVariant = ReactiveVariant.new(null, null, "active_page")

# ── Initialization ────────────────────────────────────────────────────────────

func _init() -> void:
    current_project.reactive_changed.connect(_on_current_project_changed)

func _on_current_project_changed(_reactive: Reactive) -> void:
    if current_project.value == null:
        EventBus.project_closed.emit()
    else:
        EventBus.project_opened.emit(current_project.value)

# ── Helpers ───────────────────────────────────────────────────────────────────

func has_active_project() -> bool:
    return current_project.value != null

func clear() -> void:
    is_edit_mode.value = false
    current_project = ReactiveProject.new()
