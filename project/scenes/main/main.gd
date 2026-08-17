# main.gd
extends Control

# ── Child references ──────────────────────────────────────────────────────────

@onready var menu_bar_container :  HBoxContainer         = %MenuBarContainer
@onready var file_menu :           PopupMenu             = %FileMenu
@onready var edit_menu :           PopupMenu             = %EditMenu
@onready var server_menu :         PopupMenu             = %ServerMenu
@onready var edit_mode_toggle :    Button                = %EditModeButton

@onready var page_container :            VSplitContainer       = %PageContainer
@onready var canvas_container :          PageTabContainer      = %CanvasContainer
@onready var inspector_container :       VSplitContainer       = %InspectorContainer

var active_theme : Theme
@onready var base_theme : Theme = preload("res://resources/base_theme.tres")
@onready var dark_theme : Theme = preload("res://resources/dark_theme.tres")
@onready var light_theme : Theme = preload("res://resources/light_theme.tres")

# ── Constants ─────────────────────────────────────────────────────────────────

## Number of static items in the server menu that precede the dynamic
## server list. Used to avoid removing fixed entries during a rebuild.
const SERVER_MENU_FIXED_ITEM_COUNT: int = 1

## Reserved IDs for the dynamic "Connect All" / "Disconnect All" items.
## Kept out of the range used by fixed static items to avoid collisions.
const CONNECT_ALL_ID: int = 1000
const DISCONNECT_ALL_ID: int = 1001

# ── State ─────────────────────────────────────────────────────────────────────

## Tracks dynamically created server submenus keyed by server_id.
## Enables clean teardown and rebuild when the server list changes.
var _server_submenus: Dictionary = {}

## Tracks per-server connection_status bindings keyed by server_id, so each
## can be individually connected/disconnected as the server menu is rebuilt.
## { server_id: { "cfg": ReactiveOpcUaServer, "callable": Callable } }
var _status_bindings: Dictionary = {}

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    _setup_window()
    _set_scaling()
    _connect_signals()

## Restores normal window behavior after the borderless splash screen.
func _setup_window() -> void:
    var window: Window = get_window()
    window.borderless = false
    window.unresizable = false
    window.min_size = Vector2i(800, 600)
    window.size = Vector2i(1024, 720)
    window.move_to_center()

## Scales the UI relative to the screen DPI so the layout is consistent
## across devices with different pixel densities.
func _set_scaling() -> void:
    var screen_dpi: int = DisplayServer.screen_get_dpi()
    var scale_factor: float = maxf(screen_dpi / 120.0, 1.0)
    get_tree().root.content_scale_factor = scale_factor

func _connect_signals() -> void:
    # ── System ────────────────────────────────────────────────────────────────
    DisplayServer.set_system_theme_change_callback(_on_os_theme_changed)
    _on_os_theme_changed()

    # ── Menu bar ──────────────────────────────────────────────────────────────
    file_menu.id_pressed.connect(_on_file_menu_pressed)
    edit_menu.id_pressed.connect(_on_edit_menu_pressed)
    server_menu.id_pressed.connect(_on_server_menu_pressed)
    edit_mode_toggle.toggled.connect(_on_mode_toggled)

    # ── Startup ───────────────────────────────────────────────────────────────
    IntentBus.open_project_dialog_requested.connect(func() -> void: _open_load_dialog())

    # ── Server registry ────────────────────────────────────────────────────────
    AppState.current_project.opc_ua_servers.connect_self_changed(
        func(_origin: Reactive) -> void:
            _rebuild_server_menu()
    )

    # ── AppState (named handlers so we can call them directly) ────────────────
    AppState.edit_mode.connect_self_changed(_on_edit_mode_changed)
    AppState.current_project.project_name.connect_self_changed(_on_project_name_changed)

    # UI visibility depends on BOTH runtime_only and is_loaded — a single
    # handler keeps the combined rule consistent regardless of which one
    # changes.
    AppState.runtime_only.connect_self_changed(_update_ui_visibility)
    AppState.current_project.is_loaded.connect_self_changed(_update_ui_visibility)

    # ── Sync current state ─────────────────────────────────────────────────────
    # connect_self_changed only fires on FUTURE changes. If the project was
    # created/opened by the splash screen before this scene existed, we must
    # manually apply the current values now, or the UI stays stale.
    _sync_state()


func _sync_state() -> void:
    _on_edit_mode_changed(AppState.edit_mode)
    _on_project_name_changed(AppState.current_project.project_name)
    _update_ui_visibility()
    _rebuild_server_menu()

func _on_edit_mode_changed(edit_mode: ReactiveBool) -> void:
    edit_mode_toggle.set_pressed_no_signal(edit_mode.value)


func _on_project_name_changed(new_name: ReactiveString) -> void:
    get_window().title = new_name.value


## Single source of truth for UI visibility. Reacts to changes in either
## runtime_only or is_loaded, since inspector visibility depends on both.
##
## - menu_bar_container : depends only on runtime_only
## - inspector_container: depends on is_loaded AND NOT runtime_only
## - page_container      : depends only on is_loaded
## - canvas_container     : depends only on is_loaded
func _update_ui_visibility(_origin: Reactive = null) -> void:
    var runtime_only: bool = AppState.runtime_only.value
    var is_loaded: bool = AppState.current_project.is_loaded.value

    menu_bar_container.visible = not runtime_only
    inspector_container.visible = is_loaded and not runtime_only
    page_container.visible = is_loaded
    canvas_container.visible = is_loaded

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
        1: IntentBus.open_project_dialog_requested.emit()
        2: _request_save()
        3: _open_save_dialog("projects/", AppState.current_project.file_path.value)
        4: IntentBus.close_project_requested.emit()
        6: get_tree().quit()

func _on_edit_menu_pressed(_id: int) -> void:
    pass

func _on_server_menu_pressed(id: int) -> void:
    match id:
        0:
            WindowManager.open_window("opc_ua_connection_dialog", {
                "size": Vector2i(900, 720)
            })
        CONNECT_ALL_ID:       IntentBus.connect_all_servers.emit()
        DISCONNECT_ALL_ID:    IntentBus.disconnect_all_servers.emit()

# ── Server Menu — Reactive Rebuild ────────────────────────────────────────────

## Tears down all dynamic server menu entries (and their status bindings)
## and rebuilds them from the current project's server list. Called on
## any structural change to opc_ua_servers (add/remove/reorder).
func _rebuild_server_menu() -> void:
    _unbind_all_status()

    for submenu: PopupMenu in _server_submenus.values():
        if is_instance_valid(submenu):
            submenu.free()
    _server_submenus.clear()

    while server_menu.item_count > SERVER_MENU_FIXED_ITEM_COUNT:
        server_menu.remove_item(server_menu.item_count - 1)

    if AppState.current_project.opc_ua_servers.value.is_empty():
        return

    server_menu.add_item("Connect All",    CONNECT_ALL_ID)
    server_menu.add_item("Disconnect All", DISCONNECT_ALL_ID)
    server_menu.add_separator()

    for cfg: ReactiveOpcUaServer in AppState.current_project.opc_ua_servers.values():
        var server_id: String = cfg.id.value

        var submenu: PopupMenu = PopupMenu.new()
        submenu.name = "sub_%s" % server_id
        submenu.add_item("Connect",    0)
        submenu.add_item("Disconnect", 1)
        submenu.id_pressed.connect(
            func(id: int) -> void:
                match id:
                    0: OpcUaManager.connect_server(server_id)
                    1: OpcUaManager.disconnect_server(server_id)
        )
        server_menu.add_child(submenu)
        _server_submenus[server_id] = submenu

        var menu_item_index: int = server_menu.item_count
        server_menu.add_submenu_node_item(_status_prefix(cfg) + cfg.display_name.value, submenu)

        _bind_status(cfg, menu_item_index, submenu)


# ── Per-server status binding ────────────────────────────────────────────────

## Binds directly to a server's reactive connection_status field, updating
## its menu row prefix and submenu item states immediately on any
## transition — no polling required.
func _bind_status(cfg: ReactiveOpcUaServer, menu_item_index: int, submenu: PopupMenu) -> void:
    var server_id: String = cfg.id.value

    var callback: Callable = func(_origin: Reactive) -> void:
        _on_server_status_changed(cfg, menu_item_index, submenu)

    cfg.connection_status.connect_self_changed(callback)
    _status_bindings[server_id] = { "cfg": cfg, "callable": callback }


func _unbind_all_status() -> void:
    for binding: Dictionary in _status_bindings.values():
        var cfg: ReactiveOpcUaServer = binding.get("cfg")
        var callback: Callable = binding.get("callable")
        if cfg != null and callback.is_valid():
            cfg.connection_status.reactive_changed.disconnect(callback)
    _status_bindings.clear()

func _on_server_status_changed(cfg: ReactiveOpcUaServer, menu_item_index: int, _submenu: PopupMenu) -> void:
    if menu_item_index < server_menu.item_count:
        server_menu.set_item_text(menu_item_index, _status_prefix(cfg) + cfg.display_name.value)

func _status_prefix(cfg: ReactiveOpcUaServer) -> String:
    match cfg.connection_status.value:
        ReactiveOpcUaServer.ConnectionStatus.CONNECTED:
            return "● "
        ReactiveOpcUaServer.ConnectionStatus.CONNECTING:
            return "◐ "
        ReactiveOpcUaServer.ConnectionStatus.CONNECTION_FAILED:
            return "✕ "
        _:
            return "○ "

# ── Project Management ────────────────────────────────────────────────────────

## Emits a save intent. If no project is active, falls back to the save dialog.
func _request_save() -> void:
    if AppState.current_project.file_path.value.is_empty():
        _open_save_dialog("projects/", AppState.current_project.file_path.value)
    else:
        IntentBus.save_project_requested.emit()

func _open_load_dialog() -> void:
    WindowManager.open_window("filedialog", {
        "params": {
            "title": "Open Project",
            "file_mode": FileDialog.FILE_MODE_OPEN_FILE,
            "access": FileDialog.ACCESS_FILESYSTEM,
            "filters": PackedStringArray(["*.json ; Project Files"])
        },
        "callbacks": {
            "file_selected": _on_load_dialog_selected
        }
    })

## Opens the "Save Project As" dialog.
##
## current_dir  : Default directory to display when no project file is set.
## current_path : Pre-fills the filename field if a path is already known
##                (e.g. the project was previously saved).
func _open_save_dialog(current_dir: String = "", current_path: String = "") -> void:
    var params: Dictionary = {
        "title": "Save Project As",
        "file_mode": FileDialog.FILE_MODE_SAVE_FILE,
        "access": FileDialog.ACCESS_FILESYSTEM,
        "filters": PackedStringArray(["*.json ; Project Files"])
    }

    if not current_path.is_empty():
        params["current_path"] = current_path
    elif not current_dir.is_empty():
        params["current_dir"] = current_dir

    WindowManager.open_window("filedialog", {
        "params": params,
        "callbacks": {
            "file_selected": _on_save_dialog_selected
        }
    })

func _on_load_dialog_selected(path: String) -> void:
    IntentBus.open_project_requested.emit(path)

func _on_save_dialog_selected(path: String) -> void:
    IntentBus.save_project_as_requested.emit(path)
