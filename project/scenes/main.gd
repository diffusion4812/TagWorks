# main.gd
extends Control

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
@onready var connection_dialog:   OpcUaConnectionDialog = $Dialogs/OpcUaConnectionDialog
@onready var file_dialog:         FileDialog            = $Dialogs/FileDialog
@onready var status_dialog:       OpcUaStatusDialog     = $Dialogs/OpcUaStatusDialog

var active_theme: Theme
@onready var base_theme: Theme = preload("res://resources/base_theme.tres")
@onready var dark_theme: Theme = preload("res://resources/dark_theme.tres")
@onready var light_theme: Theme = preload("res://resources/light_theme.tres")

# ── Constants ─────────────────────────────────────────────────────────────────

## Number of static items in the server menu that precede the dynamic
## server list. Used to avoid removing fixed entries during a rebuild.
const SERVER_MENU_FIXED_ITEM_COUNT: int = 1

# ── State ─────────────────────────────────────────────────────────────────────

## Tracks dynamically created server submenus keyed by server_id.
## Enables clean teardown and rebuild when the server list changes.
var _server_submenus: Dictionary = {}

## Tracks the actual ReactiveProject we're currently bound to, so we can
## unbind cleanly (and avoid dangling references) when the project changes.
var _bound_project: ReactiveProject = null
var _servers_changed_callable: Callable = Callable()

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    _set_scaling()
    _connect_signals()

## Scales the UI relative to the screen DPI so the layout is consistent
## across devices with different pixel densities.
func _set_scaling() -> void:
    var screen_dpi: int = DisplayServer.screen_get_dpi()
    var scale_factor: float = maxf(screen_dpi / 130.0, 1.0)
    get_tree().root.content_scale_factor = scale_factor


func _connect_signals() -> void:
    # ── System ────────────────────────────────────────────────────────────────
    DisplayServer.set_system_theme_change_callback(_on_os_theme_changed)
    _on_os_theme_changed()

    # ── Menu bar ──────────────────────────────────────────────────────────────
    file_menu.id_pressed.connect(_on_file_menu_pressed)
    edit_menu.id_pressed.connect(_on_edit_menu_pressed)
    server_menu.id_pressed.connect(_on_server_menu_pressed)
    server_status_timer.timeout.connect(_on_server_status_timeout)
    edit_mode_toggle.toggled.connect(_on_mode_toggled)

    # ── Server registry (now sourced from the reactive project) ──────────────
    _bind_project_servers()
    _rebuild_server_menu()

    # ── OPC UA connection state ───────────────────────────────────────────────
    OpcUaManager.connected.connect(_on_connection_state_changed.unbind(1))
    OpcUaManager.connection_lost.connect(_on_connection_state_changed.unbind(1))
    OpcUaManager.connection_failed.connect(_on_connection_state_changed.unbind(1))

    # ── File dialog ───────────────────────────────────────────────────────────
    file_dialog.file_selected.connect(_on_file_dialog_selected)

    # ── AppState ──────────────────────────────────────────────────────────────
    AppState.current_project.connect_self_changed(_on_current_project_changed)
    AppState.edit_mode.connect_self_changed(
        func(edit_mode: ReactiveBool) -> void:
            edit_mode_toggle.set_pressed_no_signal(edit_mode.value)
            inspector_container.visible = edit_mode.value
    )

# ── System ────────────────────────────────────────────────────────────────────

func deep_merge_themes(base: Theme, modifier: Theme) -> Theme:
    var result: Theme = base.duplicate(true)

    for type_name: String in modifier.get_type_list():
        for style_name: String in modifier.get_stylebox_list(type_name):
            var mod_sb: StyleBox = modifier.get_stylebox(style_name, type_name)

            if mod_sb is StyleBoxFlat and result.has_stylebox(style_name, type_name):
                var base_sb: StyleBox = result.get_stylebox(style_name, type_name)
                if base_sb is StyleBoxFlat:
                    base_sb.bg_color = mod_sb.bg_color
                    base_sb.border_color = mod_sb.border_color
                    base_sb.shadow_color = mod_sb.shadow_color
            else:
                result.set_stylebox(style_name, type_name, mod_sb)

        for color_name: String in modifier.get_color_list(type_name):
            result.set_color(color_name, type_name, modifier.get_color(color_name, type_name))

    return result

func _on_os_theme_changed() -> void:
    active_theme = deep_merge_themes(base_theme, dark_theme if DisplayServer.is_dark_mode() else light_theme)
    theme = active_theme


# ── Edit Mode ─────────────────────────────────────────────────────────────────

func _on_mode_toggled(is_edit: bool) -> void:
    AppState.edit_mode.value = is_edit

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

# ── Server Menu — Reactive Binding ─────────────────────────────────────────────

## Rebinds to the current project's `servers` array, so that any structural
## change (add/remove/reorder) triggers a menu rebuild, even though
## AppState.current_project.value itself did not change. Explicitly unbinds
## from the previously bound project first to avoid dangling references.
func _bind_project_servers() -> void:
    if _bound_project != null and _servers_changed_callable.is_valid():
        _bound_project.servers.disconnect_self_changed(_servers_changed_callable)

    _bound_project = null
    _servers_changed_callable = Callable()

    var project: ReactiveProject = AppState.current_project.value
    if project == null:
        return

    _servers_changed_callable = func(_origin: ReactiveArray) -> void:
        _rebuild_server_menu()

    project.opc_ua_servers.connect_self_changed(_servers_changed_callable)
    _bound_project = project


## Tears down all dynamic server menu entries and rebuilds them from
## the current project's server list. Called when the server list changes
## structurally, or when the bound project itself changes.
func _rebuild_server_menu() -> void:
    for submenu: PopupMenu in _server_submenus.values():
        if is_instance_valid(submenu):
            submenu.free()
    _server_submenus.clear()

    while server_menu.item_count > SERVER_MENU_FIXED_ITEM_COUNT:
        server_menu.remove_item(server_menu.item_count - 1)

    var project: ReactiveProject = _bound_project
    if project == null:
        return

    var servers: Array = project.opc_ua_servers.value
    if servers.is_empty():
        return

    server_menu.add_separator()

    for cfg: ReactiveOpcUaServer in servers:
        var server_id: String = cfg.id.value

        var submenu: PopupMenu = PopupMenu.new()
        submenu.name = "sub_%s" % server_id
        submenu.add_item("Connect",    0)
        submenu.add_item("Disconnect", 1)
        submenu.add_item("Status",     2)
        submenu.id_pressed.connect(
            func(id: int) -> void: _on_server_submenu_pressed(server_id, id)
        )
        server_menu.add_child(submenu)
        _server_submenus[server_id] = submenu

        var prefix: String = "● " if OpcUaManager.is_server_connected(server_id) else "○ "
        server_menu.add_submenu_node_item(prefix + cfg.display_name.value, submenu)

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
    var project: ReactiveProject = _bound_project
    if project == null:
        return

    var servers: Array = project.opc_ua_servers.value

    for i: int in servers.size():
        var cfg: ReactiveOpcUaServer = servers[i]
        var server_id: String        = cfg.id.value
        var menu_index: int          = SERVER_MENU_FIXED_ITEM_COUNT + i + 1

        if menu_index >= server_menu.item_count:
            break

        var connected: bool = OpcUaManager.is_server_connected(server_id)
        var prefix: String  = "● " if connected else "○ "
        server_menu.set_item_text(menu_index, prefix + cfg.display_name.value)

        var submenu: PopupMenu = _server_submenus.get(server_id, null)
        if submenu == null:
            continue

        submenu.set_item_disabled(0, connected)
        submenu.set_item_disabled(1, not connected)


func _on_connection_state_changed() -> void:
    _on_server_status_timeout()

# ── Project Management ────────────────────────────────────────────────────────

## Emits a save intent. If no project is active, falls back to the save dialog.
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
            IntentBus.save_project_as_requested.emit(path)
        FileDialog.FILE_MODE_OPEN_FILE:
            IntentBus.open_project_requested.emit(path)

# ── AppState — Project Handlers ───────────────────────────────────────────────

## Fires whenever AppState.current_project changes.
## An empty name and path indicates a closed or unloaded project.
func _on_current_project_changed(_project: ReactiveVariant) -> void:
    _bind_project_servers()
    _rebuild_server_menu()

    var project: ReactiveProject = AppState.current_project.value
    var is_open: bool = project != null and (
        not project.file_path.value.is_empty() \
        or not project.project_name.value.is_empty()
    )

    if is_open:
        inspector_container.show()
        canvas_container.show()
    else:
        canvas_container.hide()
        inspector_container.hide()
