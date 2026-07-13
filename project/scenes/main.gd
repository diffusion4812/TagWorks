# main.gd
extends Node

# ── Child references ──────────────────────────────────────────────────────────
@onready var file_menu:           PopupMenu             = %FileMenu
@onready var edit_menu:           PopupMenu             = %EditMenu
@onready var server_menu:         PopupMenu             = %ServerMenu
@onready var server_status_timer: Timer                 = %ServerStatusTimer
@onready var edit_mode_toggle:    Button                = %EditModeButton

@onready var canvas_container:    TabContainer          = %CanvasContainer
@onready var inspector_container: VSplitContainer       = %InspectorContainer
@onready var widget_palette:      WidgetPalette         = $SafeAreaContainer/RootLayout/WorkArea/InspectorContainer/WidgetPalette
@onready var property_panel:      PropertyPanel         = $SafeAreaContainer/RootLayout/WorkArea/InspectorContainer/PropertyPanel
@onready var status_bar:          AppStatusBar          = $SafeAreaContainer/RootLayout/StatusBar
@onready var connection_dialog:   OpcUaConnectionDialog = $Dialogs/OpcUaConnectionDialog
@onready var file_dialog:         FileDialog            = $Dialogs/FileDialog
@onready var status_dialog:       OpcUaStatusDialog     = $Dialogs/OpcUaStatusDialog

# ── Constants ─────────────────────────────────────────────────────────────────
## Number of static items in the server menu that precede the dynamic
## server list. Used to avoid removing fixed entries during a rebuild.
const SERVER_MENU_FIXED_ITEM_COUNT: int = 1

# ── State ─────────────────────────────────────────────────────────────────────
## Tracks dynamically created server submenus keyed by server_id.
## Enables clean teardown and rebuild when the server list changes.
var _server_submenus: Dictionary = {}

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    _set_scaling()
    _connect_signals()
    status_bar.set_disconnected()


## Scales the UI relative to the screen DPI so the layout is consistent
## across devices with different pixel densities.
func _set_scaling() -> void:
    var screen_dpi   := DisplayServer.screen_get_dpi()
    var scale_factor := maxf(screen_dpi / 130.0, 1.0)
    get_tree().root.content_scale_factor = scale_factor


func _connect_signals() -> void:
    # ── Menu bar ──────────────────────────────────────────────────────────────
    file_menu.id_pressed.connect(_on_file_menu_pressed)
    edit_menu.id_pressed.connect(_on_edit_menu_pressed)
    server_menu.id_pressed.connect(_on_server_menu_pressed)
    server_status_timer.timeout.connect(_on_server_status_timeout)
    edit_mode_toggle.toggled.connect(_on_mode_toggled)

    # ── Server registry ───────────────────────────────────────────────────────
    # Full rebuild only when the server list changes structurally.
    ProjectManager.opc_ua_registry.configs_changed.connect(_rebuild_server_menu)
    _rebuild_server_menu()

    # ── OPC UA connection state ───────────────────────────────────────────────
    OpcUaManager.connected.connect(_on_opcua_connected)
    OpcUaManager.connection_lost.connect(_on_opcua_connection_lost)
    OpcUaManager.connection_failed.connect(_on_opcua_connection_failed)

    # Lightweight server menu refresh on any connection state change.
    OpcUaManager.connected.connect(_on_connection_state_changed.unbind(1))
    OpcUaManager.connection_lost.connect(_on_connection_state_changed.unbind(1))
    OpcUaManager.connection_failed.connect(_on_connection_state_changed.unbind(1))

    # ── File dialog ───────────────────────────────────────────────────────────
    file_dialog.file_selected.connect(_on_file_dialog_selected)

    # ── EventBus — project lifecycle ──────────────────────────────────────────
    EventBus.project_opened.connect(_on_project_opened)
    EventBus.project_closed.connect(_on_project_closed)
    EventBus.project_saved.connect(_on_project_saved)

# ── Edit Mode ─────────────────────────────────────────────────────────────────

func _on_mode_toggled(is_edit: bool) -> void:
    AppState.is_edit_mode.value = is_edit

# ── Menu Handlers ─────────────────────────────────────────────────────────────

func _on_file_menu_pressed(id: int) -> void:
    match id:
        0: IntentBus.new_project_requested.emit()
        1: _open_load_dialog()
        2: _request_save()
        3: _open_save_dialog()
        4: IntentBus.close_project_requested.emit()
        6: get_tree().quit()


func _on_edit_menu_pressed(_id: int) -> void:
    pass


func _on_server_menu_pressed(id: int) -> void:
    match id:
        0: connection_dialog.popup_centered(Vector2i(800, 520))


## Tears down all dynamic server menu entries and rebuilds them from
## the current registry state. Called when the server list changes structurally.
func _rebuild_server_menu() -> void:
    # Use free() rather than queue_free() so submenus are fully removed
    # before new ones are added in the same frame.
    for submenu: PopupMenu in _server_submenus.values():
        if is_instance_valid(submenu):
            submenu.free()
    _server_submenus.clear()

    while server_menu.item_count > SERVER_MENU_FIXED_ITEM_COUNT:
        server_menu.remove_item(server_menu.item_count - 1)

    var configs := ProjectManager.opc_ua_registry.get_all_configs()
    if configs.is_empty():
        return

    server_menu.add_separator()

    for cfg: OpcUaServerConfig in configs:
        var submenu  := PopupMenu.new()
        submenu.name  = "sub_%s" % cfg.id
        submenu.add_item("Connect",    0)
        submenu.add_item("Disconnect", 1)
        submenu.add_item("Status",     2)
        submenu.id_pressed.connect(
            func(id: int) -> void: _on_server_submenu_pressed(cfg.id, id)
        )
        server_menu.add_child(submenu)
        _server_submenus[cfg.id] = submenu

        var prefix := "● " if OpcUaManager.is_server_connected(cfg.id) else "○ "
        server_menu.add_submenu_node_item(prefix + cfg.display_name, submenu)

    _on_server_status_timeout()


func _on_server_submenu_pressed(server_id: String, id: int) -> void:
    match id:
        0: OpcUaManager.connect_server(server_id)
        1: OpcUaManager.disconnect_server(server_id)
        2:
            status_dialog.focus_server(server_id)
            status_dialog.show()


## Refreshes server menu dot indicators and submenu item states
## without triggering a full structural rebuild.
func _on_server_status_timeout() -> void:
    var configs := ProjectManager.opc_ua_registry.get_all_configs()

    for i: int in configs.size():
        var cfg        : OpcUaServerConfig = configs[i]
        var menu_index : int               = SERVER_MENU_FIXED_ITEM_COUNT + i + 1

        if menu_index >= server_menu.item_count:
            break

        var connected := OpcUaManager.is_server_connected(cfg.id)
        var prefix    := "● " if connected else "○ "
        server_menu.set_item_text(menu_index, prefix + cfg.display_name)

        var submenu: PopupMenu = _server_submenus.get(cfg.id, null)
        if submenu == null:
            continue

        submenu.set_item_disabled(0, connected)     # Connect
        submenu.set_item_disabled(1, not connected) # Disconnect


func _on_connection_state_changed() -> void:
    _on_server_status_timeout()

# ── Project Management ────────────────────────────────────────────────────────

## Emits a save intent. If no project is active, falls back to the save dialog
## so the user can choose a path first.
func _request_save() -> void:
    if ProjectManager.has_active_project():
        IntentBus.save_project_requested.emit()
    else:
        _open_save_dialog()


func _open_save_dialog() -> void:
    file_dialog.file_mode   = FileDialog.FILE_MODE_SAVE_FILE
    file_dialog.access      = FileDialog.ACCESS_USERDATA
    file_dialog.filters     = PackedStringArray(["*.json ; Project Files"])
    file_dialog.current_dir = "projects/"
    if ProjectManager.has_active_project():
        file_dialog.current_file = ProjectManager.get_current_project_path().get_file()
    file_dialog.popup_centered(Vector2i(800, 600))


func _open_load_dialog() -> void:
    file_dialog.file_mode   = FileDialog.FILE_MODE_OPEN_FILE
    file_dialog.access      = FileDialog.ACCESS_USERDATA
    file_dialog.filters     = PackedStringArray(["*.json ; Project Files"])
    file_dialog.current_dir = "projects/"
    file_dialog.popup_centered(Vector2i(800, 600))


func _on_file_dialog_selected(path: String) -> void:
    match file_dialog.file_mode:
        FileDialog.FILE_MODE_SAVE_FILE:
            IntentBus.save_project_as_requested.emit()
        FileDialog.FILE_MODE_OPEN_FILE:
            IntentBus.load_project_requested.emit(path)

# ── EventBus — Project event handlers ────────────────────────────────────────

func _on_project_opened(project_data: ProjectData) -> void:
    AppState.is_edit_mode.value = false
    inspector_container.show()

func _on_project_saved(path: String) -> void:
    status_bar.show_message("Project saved: %s" % path.get_file())


func _on_project_closed() -> void:
    AppState.is_edit_mode.value = false
    canvas_container.hide()
    inspector_container.hide()
    status_bar.show_message("Project closed.")

# ── OPC UA ────────────────────────────────────────────────────────────────────
func _on_opcua_connected(server_id: String) -> void:
    var cfg   := ProjectManager.opc_ua_registry.get_config(server_id)
    var label := cfg.display_name if cfg else server_id
    status_bar.set_connected("%s — connected" % label)


func _on_opcua_connection_lost(server_id: String) -> void:
    var cfg   := ProjectManager.opc_ua_registry.get_config(server_id)
    var label := cfg.display_name if cfg else server_id
    status_bar.show_message("%s — connection lost." % label)
    _update_status_bar_connectivity()


func _on_opcua_connection_failed(server_id: String) -> void:
    var cfg   := ProjectManager.opc_ua_registry.get_config(server_id)
    var label := cfg.display_name if cfg else server_id
    status_bar.show_message("%s — connection failed." % label)
    _update_status_bar_connectivity()


## Sets the status bar to disconnected only when no servers remain connected.
func _update_status_bar_connectivity() -> void:
    for cfg: OpcUaServerConfig in ProjectManager.opc_ua_registry.get_all_configs():
        if OpcUaManager.is_server_connected(cfg.id):
            return
    status_bar.set_disconnected()
