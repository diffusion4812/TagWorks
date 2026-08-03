# autoloads/app_state.gd
extends Node

# ── Project State ─────────────────────────────────────────────────────────────

## The active project. Always a valid, non-null ReactiveProject instance —
## never reassigned after _ready(). Loading/closing a project mutates this
## instance's contents in place (see ReactiveProject.load_from_dict /
## reset_to_default), so anything bound to current_project or its children
## (pages, opc_ua_servers, etc.) never needs to rebind due to a project swap.
var current_project : ReactiveProject

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
    current_project  = ReactiveProject.new(null, "app_state.current_project")
    focused_page     = ReactiveVariant.new(null, null, "app_state.focused_page")
    active_page      = ReactiveVariant.new(null, null, "app_state.active_page")
    selected_widget  = ReactiveVariant.new(null, null, "app_state.selected_widget")
    edit_mode        = ReactiveBool.new(false, null,   "app_state.edit_mode")
    last_error       = ReactiveString.new("", null,    "app_state.last_error")
    last_saved_path  = ReactiveString.new("", null,    "app_state.last_saved_path")

    active_page.connect_self_changed(
        func(_active_page: ReactiveVariant) -> void:
            edit_mode.value = false
    )

    current_project.is_loaded.connect_self_changed(
        func(is_loaded: ReactiveBool) -> void:
            if is_loaded.value:
                active_page.value = AppState.current_project.get_default_page()
    )

# ── Project Lifecycle ─────────────────────────────────────────────────────────

## Loads project data into the existing current_project instance in place.
## Returns false (and leaves current_project untouched) if payload is invalid.
func load_project(payload: Dictionary) -> bool:
    if not ReactiveProject.validate_payload(payload):
        last_error.value = "Invalid project file."
        return false

    current_project.load_from_dict(payload)
    _reset_selection_state()
    current_project.is_loaded.value = true
    return true

## Resets current_project to a fresh, empty project (e.g. "File > New").
func new_project() -> void:
    current_project.reset_to_default()
    last_saved_path.value = ""
    _reset_selection_state()
    current_project.is_loaded.value = true

## Closes the current project, returning to the default empty state.
func close_project() -> void:
    current_project.reset_to_default()
    last_saved_path.value = ""
    _reset_selection_state()
    current_project.is_loaded.value = false

func _reset_selection_state() -> void:
    focused_page.value    = null
    active_page.value     = null
    selected_widget.value = null
    edit_mode.value        = false
