# autoloads/app_state.gd
extends Node

# ── Edit Mode ─────────────────────────────────────────────────────────────────

var is_edit_mode: ReactiveBool = ReactiveBool.new(false)

# ── Selected Widget ───────────────────────────────────────────────────────────

var selected_widget: ReactiveProperty = ReactiveProperty.new(null)

# ── Active Project ────────────────────────────────────────────────────────────

var current_project: ReactiveProperty = ReactiveProperty.new(null)

# ── Active Page ───────────────────────────────────────────────────────────────

var current_page: ReactiveProperty = ReactiveProperty.new(null)

# ── Initialization ────────────────────────────────────────────────────────────

func _init() -> void:
    is_edit_mode.changed.connect(_on_edit_mode_changed)
    selected_widget.changed.connect(_on_selected_widget_changed)
    current_project.changed.connect(_on_current_project_changed)
    current_page.changed.connect(_on_current_page_changed)

# ── Handlers ──────────────────────────────────────────────────────────────────

func _on_edit_mode_changed(value: bool) -> void:
    EventBus.edit_mode_changed.emit(value)


func _on_selected_widget_changed(value: BaseWidget) -> void:
    if value == null:
        EventBus.widget_deselected.emit()
    else:
        EventBus.widget_selected.emit(value)


func _on_current_project_changed(value: ProjectData) -> void:
    if value == null:
        EventBus.project_closed.emit()
    else:
        EventBus.project_opened.emit(value)


func _on_current_page_changed(value: PageData) -> void:
    EventBus.page_changed.emit(value)

# ── Helpers ───────────────────────────────────────────────────────────────────

func has_active_project() -> bool:
    return current_project.value != null


func has_active_page() -> bool:
    return current_page.value != null


func clear() -> void:
    current_page.value    = null
    selected_widget.value = null
    is_edit_mode.value    = false
    current_project.value = null
