# autoloads/intent_bus.gd
extends Node

# ── Project ───────────────────────────────────────────────────────────────────

## Requests the creation of a new, empty project.
## Consumers should prompt for unsaved changes before proceeding.
signal new_project_requested()

## Requests a save of the active project to its current file path.
## Falls back to save_project_as_requested if no path is set.
signal save_project_requested()

## Requests a save of the active project to a new file path chosen by the user.
signal save_project_as_requested()

## Requests that a project be loaded from the given file path.
signal load_project_requested(path: String)

## Requests that the active project be closed.
## Consumers should check for unsaved changes before honouring this request.
signal close_project_requested()

# ── Pages ─────────────────────────────────────────────────────────────────────

## Requests the creation of a new page under the given parent.
## Pass null to create a top-level page.
signal add_page_requested(parent: PageData)

## Requests deletion of the page with the given ID.
## Consumers should guard against deleting the last remaining page.
signal delete_page_requested(page_id: String)

## Requests that a page be renamed to a new value.
signal rename_page_requested(page_id: String, new_name: String)

## Requests that the page tree selection be updated to reflect the given page.
## Does not trigger a canvas load — use page_change_requested for that.
signal select_page_requested(page_data: PageData)

## Requests that a page be moved to a new parent in the hierarchy.
## Pass an empty string as new_parent_id to reparent to the project root.
signal reparent_page_requested(page_id: String, new_parent_id: String)

## Requests a page change on the canvas.
## The canvas will perform a dirty check and show a confirmation dialog
## if unsaved changes are present. The change is only applied if confirmed.
## Subscribe to EventBus.page_changed for the confirmed result.
signal page_change_requested(page: PageData)

# ── Widgets ───────────────────────────────────────────────────────────────────

## Requests that a widget be spawned onto the canvas from the given scene.
signal add_widget_requested(scene: PackedScene)

## Requests deletion of the widget with the given ID.
signal delete_widget_requested(widget_id: String)

## Requests that the given widget become the active selection.
signal select_widget_requested(widget: BaseWidget)

## Requests that the current widget selection be cleared.
signal deselect_widget_requested()

## Requests that a widget be moved to a new position on the canvas.
signal move_widget_requested(widget_id: String, new_position: Vector2)

## Requests that a single property be updated on the given widget.
## The widget identified by widget_id should apply the value and sync its data.
signal change_widget_property_requested(widget_id: String, property: String, value: Variant)

# ── Edit Mode ─────────────────────────────────────────────────────────────────

## Requests a change to the global edit mode state.
## The confirmed state change is broadcast via EventBus.edit_mode_changed.
signal set_edit_mode_requested(enabled: bool)
