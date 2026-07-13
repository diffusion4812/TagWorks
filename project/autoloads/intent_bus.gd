extends Node

# ── Pages ─────────────────────────────────────────────────────────────────────
signal add_page_requested(page_name: String)
signal delete_page_requested(page_id: String)
signal rename_page_requested(page_id: String, new_name: String)

# ── Widgets ───────────────────────────────────────────────────────────────────
signal add_widget_requested(scene: PackedScene)
signal delete_widget_requested(widget_id: String)
signal rename_widget_requested(widget_id: String, new_name: String)

# ── Project ───────────────────────────────────────────────────────────────────
signal new_project_requested()
signal save_project_requested()
signal save_project_as_requested()
signal open_project_requested()
signal close_project_requested()
signal rename_project_requested(new_name: String)
