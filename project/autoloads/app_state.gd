extends Node

# ── Edit Mode ─────────────────────────────────────────────────────────────────

var is_edit_mode    : ReactiveBool    = ReactiveBool.new(false)

# ── Selected Widget ───────────────────────────────────────────────────────────

var selected_widget : ReactiveObject  = ReactiveObject.new(null)

# ── Active Project ────────────────────────────────────────────────────────────

var current_project : ReactiveProject = ReactiveProject.new()

# ── Active Page ───────────────────────────────────────────────────────────────

var current_page    : ReactivePage    = ReactivePage.new()

# ── Initialization ────────────────────────────────────────────────────────────

func _init() -> void:
    is_edit_mode.reactive_changed.connect(_on_edit_mode_changed)
    selected_widget.reactive_changed.connect(_on_selected_widget_changed)
    current_project.reactive_changed.connect(_on_current_project_changed)
    current_page.reactive_changed.connect(_on_current_page_changed)

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


func _on_current_page_changed(_reactive: Reactive) -> void:
    EventBus.page_changed.emit(current_page.value)

# ── Helpers ───────────────────────────────────────────────────────────────────

func has_active_project() -> bool:
    return current_project.value != null


func has_active_page() -> bool:
    return current_page.value != null


func clear() -> void:
    current_page    = ReactivePage.new()
    selected_widget = ReactiveObject.new(null)
    is_edit_mode.value = false
    current_project = ReactiveProject.new()
