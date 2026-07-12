# autoloads/event_bus.gd
extends Node

# ── Project ───────────────────────────────────────────────────────────────────

## Emitted when a project has been successfully opened and is ready for use.
signal project_opened(project_data: ProjectData)

## Emitted when the active project has been closed and unloaded.
signal project_closed()

## Emitted when the active project has been successfully saved to disk.
signal project_saved(path: String)

## Emitted when a project operation fails. Carries a human-readable message.
signal project_error(message: String)

# ── Pages ─────────────────────────────────────────────────────────────────────

## Emitted when a new page has been added to the project hierarchy.
signal page_created(page_data: PageData)

## Emitted when a page has been removed from the project hierarchy.
signal page_deleted(page_id: String)

## Emitted when a page has been renamed.
signal page_renamed(page_id: String, new_name: String)

## Emitted by the canvas after a page change request has been confirmed,
## the dirty check passed, and the new page has been fully loaded.
## Consumers should use this — not page_selected — to react to active page changes.
signal page_changed(page_data: PageData)

## Emitted when a page is selected in the page tree UI.
## Does not imply the canvas has loaded the page — await page_changed for that.
signal page_selected(page_data: PageData)

## Emitted when the page hierarchy has been structurally modified,
## such as after a drag-and-drop reorder.
signal page_hierarchy_changed()

# ── Widgets ───────────────────────────────────────────────────────────────────

## Emitted when a new widget has been spawned onto the canvas.
signal widget_added(widget_data: WidgetData)

## Emitted when a widget has been removed from the canvas.
signal widget_deleted(widget_id: String)

## Emitted when a widget has been selected on the canvas.
signal widget_selected(widget: BaseWidget)

## Emitted when the active widget selection has been cleared.
signal widget_deselected()

## Emitted when a widget has been moved to a new position.
signal widget_moved(widget_id: String, new_position: Vector2)

## Emitted when a single property on a widget has been changed.
## Consumers should filter by widget_id before applying the value.
signal widget_property_changed(widget_id: String, property: String, value: Variant)

# ── Edit Mode ─────────────────────────────────────────────────────────────────

## Emitted when the global edit mode state has been confirmed and applied.
## All nodes requiring edit mode awareness should subscribe to this signal.
signal edit_mode_changed(enabled: bool)
