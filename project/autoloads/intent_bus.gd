extends Node

# ── Pages ─────────────────────────────────────────────────────────────────────
@warning_ignore("unused_signal")
signal create_page_requested(page_name: String)
@warning_ignore("unused_signal")
signal delete_page_requested(page_id: String)
@warning_ignore("unused_signal")
signal rename_page_requested(page_id: String, new_name: String)

# ── Widgets ───────────────────────────────────────────────────────────────────
@warning_ignore("unused_signal")
signal add_widget_requested(scene: PackedScene)
@warning_ignore("unused_signal")
signal delete_widget_requested(widget_id: String)
@warning_ignore("unused_signal")
signal rename_widget_requested(widget_id: String, new_name: String)
@warning_ignore("unused_signal")
signal change_widget_property_requested(widget_id: String, property: String, value: Variant)

# ── Project ───────────────────────────────────────────────────────────────────
@warning_ignore("unused_signal")
signal new_project_requested()
@warning_ignore("unused_signal")
signal save_project_requested()
@warning_ignore("unused_signal")
signal save_project_as_requested(path: String)
@warning_ignore("unused_signal")
signal open_project_requested(path: String)
@warning_ignore("unused_signal")
signal close_project_requested()
@warning_ignore("unused_signal")
signal rename_project_requested(new_name: String)
