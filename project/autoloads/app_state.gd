# autoloads/app_state.gd
extends Node

# ── Project State ─────────────────────────────────────────────────────────────

## The currently active project.
var current_project : ReactiveVariant

# ── Page State ────────────────────────────────────────────────────────────────

## Reference to the page currently highlighted in the page tree.
## Changes on every tree selection — does not imply the canvas has changed.
## Value is a ReactivePage instance owned by current_project, or null.
var focused_page    : ReactiveVariant

## Reference to the page currently displayed in the canvas.
## Only changes when a page is explicitly opened or loaded.
## Value is a ReactivePage instance owned by current_project, or null.
var active_page     : ReactiveVariant

# ── Widget State ──────────────────────────────────────────────────────────────

## Reference to the currently selected widget scene node.
## Value is a BaseWidget instance, or null when nothing is selected.
var selected_widget : ReactiveVariant

# ── Edit Mode ─────────────────────────────────────────────────────────────────

## Whether the application is currently in edit mode.
var edit_mode       : ReactiveBool

# ── Operation State ───────────────────────────────────────────────────────────

## Set when a project operation fails. Carries a human-readable message.
var last_error      : ReactiveString

## The path of the most recently saved project file.
var last_saved_path : ReactiveString

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    current_project = ReactiveVariant.new(null, null, "app_state.current_project")
    focused_page    = ReactiveVariant.new(null, null, "app_state.focused_page")
    active_page     = ReactiveVariant.new(null, null, "app_state.active_page")
    selected_widget = ReactiveVariant.new(null, null, "app_state.selected_widget")
    edit_mode       = ReactiveBool.new(false, null,   "app_state.edit_mode")
    last_error      = ReactiveString.new("", null,    "app_state.last_error")
    last_saved_path = ReactiveString.new("", null,    "app_state.last_saved_path")

    current_project.connect_self_changed(
        func(_current_project: ReactiveVariant) -> void:
            focused_page.value    = null
            active_page.value     = null
            selected_widget.value = null
            edit_mode.value        = false
    )

    active_page.connect_self_changed(
        func(_active_page: ReactiveVariant) -> void:
            edit_mode.value = false
    )
