class_name RecentProjectRow
extends PanelContainer

signal open_requested(file_path: String)
signal remove_requested(file_path: String)

@onready var _name_label: Label = %NameLabel
@onready var _path_label: Label = %PathLabel
@onready var _time_label: Label = %TimeLabel
@onready var _warning_icon: TextureRect = %WarningIcon

var _file_path: String = ""
var _exists: bool = true
var _hover_style: StyleBoxFlat
var _default_style: StyleBoxFlat

func _ready() -> void:
    _default_style = StyleBoxFlat.new()
    _default_style.bg_color = Color(0, 0, 0, 0)  # transparent by default
    _default_style.content_margin_left = 8
    _default_style.content_margin_right = 8
    _default_style.content_margin_top = 6
    _default_style.content_margin_bottom = 6

    _hover_style = _default_style.duplicate()
    _hover_style.bg_color = Color(1, 1, 1, 0.06)  # subtle light highlight
    _hover_style.corner_radius_top_left = 6
    _hover_style.corner_radius_top_right = 6
    _hover_style.corner_radius_bottom_left = 6
    _hover_style.corner_radius_bottom_right = 6

    add_theme_stylebox_override("panel", _default_style)

    mouse_filter = Control.MOUSE_FILTER_STOP
    gui_input.connect(_on_gui_input)
    mouse_entered.connect(_on_mouse_entered)
    mouse_exited.connect(_on_mouse_exited)

func setup(entry: Dictionary) -> void:
    _file_path = entry.get("file_path", "")
    _exists = entry.get("exists", true)

    _name_label.text = entry.get("display_name", "Untitled Project")
    _path_label.text = _file_path
    _time_label.text = _format_relative_time(entry.get("last_opened", 0))

    _warning_icon.visible = not _exists
    modulate = Color(1, 1, 1, 1.0 if _exists else 0.6)

func _on_mouse_entered() -> void:
    add_theme_stylebox_override("panel", _hover_style)

func _on_mouse_exited() -> void:
    add_theme_stylebox_override("panel", _default_style)

func _on_gui_input(event: InputEvent) -> void:
    if not (event is InputEventMouseButton and event.pressed):
        return
    if event.button_index == MOUSE_BUTTON_LEFT:
        if event.double_click:
            if _exists:
                open_requested.emit(_file_path)
    elif event.button_index == MOUSE_BUTTON_RIGHT:
        _show_context_menu(DisplayServer.mouse_get_position())

func _show_context_menu(at_position: Vector2) -> void:
    var menu : PopupMenu = PopupMenu.new()
    menu.add_item("Open", 0)
    menu.set_item_disabled(0, not _exists)
    menu.add_item("Open Containing Folder", 1)
    menu.add_item("Copy Path", 2)
    menu.add_separator()
    menu.add_item("Remove from List", 3)
    menu.id_pressed.connect(_on_context_menu_id_pressed)
    add_child(menu)
    menu.position = at_position
    menu.popup()
    menu.popup_hide.connect(menu.queue_free)

func _on_context_menu_id_pressed(id: int) -> void:
    match id:
        0: open_requested.emit(_file_path)
        1: OS.shell_show_in_file_manager(ProjectSettings.globalize_path(_file_path))
        2: DisplayServer.clipboard_set(_file_path)
        3: remove_requested.emit(_file_path)

func _format_relative_time(unix_time: int) -> String:
    if unix_time <= 0:
        return ""
    var delta: int = int(Time.get_unix_time_from_system()) - unix_time
    if delta < 60: return "Just now"
    @warning_ignore("integer_division")
    if delta < 3600: return "%d min ago" % [delta / 60]
    @warning_ignore("integer_division")
    if delta < 86400: return "%d hr ago" % [delta / 3600]
    @warning_ignore("integer_division")
    if delta < 604800: return "%d days ago" % [delta / 86400]
    return Time.get_date_string_from_unix_time(unix_time)
