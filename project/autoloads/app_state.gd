extends Node

var is_edit_mode    : ReactiveBool    = ReactiveBool.new(false)
var selected_widget : ReactiveObject  = ReactiveObject.new(null)
var current_project : ReactiveProject = ReactiveProject.new()
var focused_page    : ReactiveVariant = ReactiveVariant.new(null, null, "focused_page")
var active_page     : ReactiveVariant = ReactiveVariant.new(null, null, "active_page")

# ── Initialization ────────────────────────────────────────────────────────────

func _init() -> void:
    is_edit_mode.reactive_changed.connect(_on_edit_mode_changed)
    selected_widget.reactive_changed.connect(_on_selected_widget_changed)
    current_project.reactive_changed.connect(_on_current_project_changed)

# ── Handlers ──────────────────────────────────────────────────────────────────

func _on_edit_mode_changed(_reactive: Reactive) -> void:
    EventBus.edit_mode_changed.emit(is_edit_mode.value)


func _on_selected_widget_changed(_reactive: Reactive) -> void:
    var widget := selected_widget.value as BaseWidget
    if widget == null:
        EventBus.widget_deselected.emit()
    else:
        EventBus.widget_selected.emit(widget)


func _on_current_project_changed(_reactive: Reactive) -> void:
    if current_project.value == null:
        EventBus.project_closed.emit()
    else:
        EventBus.project_opened.emit(current_project.value)

# ── Helpers ───────────────────────────────────────────────────────────────────

func has_active_project() -> bool:
    return current_project.value != null

func clear() -> void:
    selected_widget = ReactiveObject.new(null)
    is_edit_mode.value = false
    current_project = ReactiveProject.new()
