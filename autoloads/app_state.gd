# autoloads/app_state.gd
extends Node

# ── Edit Mode ─────────────────────────────────────────────────────────────────

var _is_edit_mode: bool = false

var is_edit_mode: bool:
    get:
        return _is_edit_mode
    set(value):
        if value == _is_edit_mode:
            return
        _is_edit_mode = value
        EventBus.edit_mode_changed.emit(value)

# ── Selected Widget ───────────────────────────────────────────────────────────

var _selected_widget: BaseWidget = null

var selected_widget: BaseWidget:
    get:
        return _selected_widget
    set(value):
        if value == _selected_widget:
            return
        _selected_widget = value
        if value == null:
            EventBus.widget_deselected.emit()
        else:
            EventBus.widget_selected.emit(value)

# ── Active Project ────────────────────────────────────────────────────────────

var _current_project: ProjectData = null

var current_project: ProjectData:
    get:
        return _current_project
    set(value):
        if value == _current_project:
            return
        _current_project = value
        if value == null:
            EventBus.project_closed.emit()
        else:
            EventBus.project_opened.emit(value)

# ── Active Page ───────────────────────────────────────────────────────────────

var _current_page: PageData = null

var current_page: PageData:
    get:
        return _current_page
    set(value):
        if value == _current_page:
            return
        _current_page = value
        EventBus.page_changed.emit(value)

# ── Helpers ───────────────────────────────────────────────────────────────────

func has_active_project() -> bool:
    return _current_project != null


func has_active_page() -> bool:
    return _current_page != null


func clear() -> void:
    current_page     = null
    selected_widget  = null
    is_edit_mode     = false
    current_project  = null
