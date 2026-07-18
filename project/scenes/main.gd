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

    # ── Server registry ───────────────────────────────────────────────────────
    ProjectManager.opc_ua_registry.configs_changed.connect(_rebuild_server_menu)
    _rebuild_server_menu()

    # ── OPC UA connection state ───────────────────────────────────────────────
    OpcUaManager.connected.connect(_on_connection_state_changed.unbind(1))
    OpcUaManager.connection_lost.connect(_on_connection_state_changed.unbind(1))
    OpcUaManager.connection_failed.connect(_on_connection_state_changed.unbind(1))

    # ── File dialog ───────────────────────────────────────────────────────────
    file_dialog.file_selected.connect(_on_file_dialog_selected)

    # ── AppState ──────────────────────────────────────────────────────────────
    AppState.current_project.changed.connect(_on_current_project_changed)
    AppState.edit_mode.reactive_changed.connect(
        func(edit_mode: ReactiveBool) -> void:
            edit_mode_toggle.set_pressed_no_signal(edit_mode.value)
            inspector_container.visible = edit_mode.value
    )

# ── System ────────────────────────────────────────────────────────────────────

func deep_merge_themes(base: Theme, modifier: Theme) -> Theme:
    var result: Theme = base.duplicate(true)
    
    for type_name: String in modifier.get_type_list():
        # Merge StyleBoxes intelligently instead of overwriting them
        for style_name: String in modifier.get_stylebox_list(type_name):
            var mod_sb: StyleBox = modifier.get_stylebox(style_name, type_name)
            
            if mod_sb is StyleBoxFlat and result.has_stylebox(style_name, type_name):
                var base_sb: StyleBox = result.get_stylebox(style_name, type_name)
                if base_sb is StyleBoxFlat:
                    # Explicitly copy color data over the base layout geometry
                    base_sb.bg_color = mod_sb.bg_color
                    base_sb.border_color = mod_sb.border_color
                    base_sb.shadow_color = mod_sb.shadow_color
            else:
                # Fallback if the base doesn't have it or it's a texture/empty stylebox
                result.set_stylebox(style_name, type_name, mod_sb)

        # Colors, Fonts, Constants merge perfectly with the default engine methods
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


## Tears down all dynamic server menu entries and rebuilds them from
## the current registry state. Called when the server list changes structurally.
func _rebuild_server_menu() -> void:
    for submenu: PopupMenu in _server_submenus.values():
        if is_instance_valid(submenu):
            submenu.free()
    _server_submenus.clear()

    while server_menu.item_count > SERVER_MENU_FIXED_ITEM_COUNT:
        server_menu.remove_item(server_menu.item_count - 1)

    var configs: Array[OpcUaServerConfig] = ProjectManager.opc_ua_registry.get_all_configs()
    if configs.is_empty():
        return

    server_menu.add_separator()

    for cfg: OpcUaServerConfig in configs:
        var submenu: PopupMenu = PopupMenu.new()
        submenu.name  = "sub_%s" % cfg.id
        submenu.add_item("Connect",    0)
        submenu.add_item("Disconnect", 1)
        submenu.add_item("Status",     2)
        submenu.id_pressed.connect(
            func(id: int) -> void: _on_server_submenu_pressed(cfg.id, id)
        )
        server_menu.add_child(submenu)
        _server_submenus[cfg.id] = submenu

        var prefix: String = "● " if OpcUaManager.is_server_connected(cfg.id) else "○ "
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
    var configs: Array[OpcUaServerConfig] = ProjectManager.opc_ua_registry.get_all_configs()

    for i: int in configs.size():
        var cfg        : OpcUaServerConfig = configs[i]
        var menu_index : int               = SERVER_MENU_FIXED_ITEM_COUNT + i + 1

        if menu_index >= server_menu.item_count:
            break

        var connected: bool = OpcUaManager.is_server_connected(cfg.id)
        var prefix: String  = "● " if connected else "○ "
        server_menu.set_item_text(menu_index, prefix + cfg.display_name)

        var submenu: PopupMenu = _server_submenus.get(cfg.id, null)
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
func _on_current_project_changed() -> void:
    var project: ReactiveProject = AppState.current_project.value
    var is_open: bool = not project.file_path.value.is_empty() \
                or not project.project_name.value.is_empty()

    if is_open:
        inspector_container.show()
        canvas_container.show()
    else:
        canvas_container.hide()
        inspector_container.hide()
