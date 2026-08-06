extends Node

# ── Pages ─────────────────────────────────────────────────────────────────────
@warning_ignore("unused_signal")
signal create_page_requested(page_name: String)
@warning_ignore("unused_signal")
signal delete_page_requested(page: ReactivePage)
@warning_ignore("unused_signal")
signal rename_page_requested(page: ReactivePage, new_name: String)

# ── Widgets ───────────────────────────────────────────────────────────────────
@warning_ignore("unused_signal")
signal add_widget_requested(scene: PackedScene)
@warning_ignore("unused_signal")
signal delete_widget_requested(widget: ReactiveWidget)

# ── Servers ───────────────────────────────────────────────────────────────────
@warning_ignore("unused_signal")
signal add_server_requested()
@warning_ignore("unused_signal")
signal delete_server_requested(server: ReactiveOpcUaServer)
@warning_ignore("unused_signal")
signal connect_all_servers()
@warning_ignore("unused_signal")
signal disconnect_all_servers()

# ── Groups ────────────────────────────────────────────────────────────────────
@warning_ignore("unused_signal")
signal add_group_requested()
@warning_ignore("unused_signal")
signal delete_group_requested(server: ReactiveOpcUaSubscription)

# ── Project ───────────────────────────────────────────────────────────────────
@warning_ignore("unused_signal")
signal new_project_requested()
@warning_ignore("unused_signal")
signal open_project_dialog_requested()
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
