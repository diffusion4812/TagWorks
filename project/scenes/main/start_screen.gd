extends PanelContainer

@export var recent_project_row_scene: PackedScene
@export var main_scene: PackedScene

@onready var _close_button              : Button = %CloseButton
@onready var _title_label               : Label = %TitleLabel
@onready var _recent_list               : VBoxContainer = %RecentProjectsList
@onready var _new_project_button        : Button = %NewProjectButton
@onready var _open_project_button       : Button = %OpenProjectButton
@onready var _recent_projects_label     : Label = %RecentProjectsLabel
@onready var _runtime_only_check_button : CheckButton = %RuntimeOnlyCheckButton
@onready var _runtime_only_label        : Label = %RuntimeOnlyLabel
@onready var _version_label             : Label = %VersionLabel
@onready var _language_option           : OptionButton = %LanguageOptionButton

var _dragging: bool = false
var _drag_offset: Vector2i

func _ready() -> void:
    _close_button.pressed.connect(func() -> void: get_tree().quit(0))
    _new_project_button.pressed.connect(_on_new_project_pressed)
    _open_project_button.pressed.connect(_on_open_project_pressed)
    _runtime_only_check_button.toggled.connect(func(toggled: bool) -> void: AppState.runtime_only.value = toggled)
    AppState.runtime_only.connect_self_changed(func(runtime_only: ReactiveBool) -> void: _new_project_button.disabled = runtime_only.value)

    _populate_language_options()
    _language_option.item_selected.connect(_on_language_option_selected)
    _refresh_recent_list()

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            _dragging = true
            _drag_offset = DisplayServer.mouse_get_position() - get_window().position
        else:
            _dragging = false

func _process(_delta: float) -> void:
    if _dragging:
        get_window().position = DisplayServer.mouse_get_position() - _drag_offset

func _notification(what : int) -> void:
    if what == NOTIFICATION_TRANSLATION_CHANGED:
        if not is_node_ready():
            await ready # Needed because this also triggers on init
        _title_label.text = tr("SPLASH_TITLE")
        _new_project_button.text = tr("SPLASH_NEW_PROJECT")
        _open_project_button.text = tr("SPLASH_OPEN_PROJECT")
        _recent_projects_label.text = tr("SPLASH_RECENT_PROJECTS")
        _runtime_only_label.text = tr("SPLASH_RUNTIME_ONLY")
        _version_label.text = tr("Version {version}").format({"version" = ProjectSettings.get_setting("application/config/version", "")})
        _refresh_recent_list()

func _populate_language_options() -> void:
    var locales: Array[Dictionary] = [
        {"code": "en", "label": "English"},
        {"code": "de", "label": "Deutsch"}
    ]
    for i: int in locales.size():
        _language_option.add_item(locales[i]["label"])
        _language_option.set_item_metadata(i, locales[i]["code"])

    var current: String = AppSettings.preferred_locale.value
    for i: int in _language_option.item_count:
        if _language_option.get_item_metadata(i) == current:
            _language_option.select(i)
            break

func _on_language_option_selected(index: int) -> void:
    var locale: String = _language_option.get_item_metadata(index)
    TranslationServer.set_locale(locale)
    AppSettings.preferred_locale.value = locale

func _refresh_recent_list() -> void:
    for child: Node in _recent_list.get_children():
        child.queue_free()

    var entries: Array[Dictionary] = RecentProjects.entries

    for entry: Dictionary in entries:
        var row: RecentProjectRow = recent_project_row_scene.instantiate()
        _recent_list.add_child(row)

        var row_data: Dictionary = entry.duplicate()
        row_data["exists"] = FileAccess.file_exists(entry.get("file_path", ""))

        row.setup(row_data)
        row.open_requested.connect(_on_recent_project_open_requested)
        row.remove_requested.connect(_on_recent_project_remove_requested)

func _launch_main_scene() -> void:
    get_tree().change_scene_to_packed(main_scene)

func _on_new_project_pressed() -> void:
    _launch_main_scene()
    IntentBus.new_project_requested.emit()

func _on_open_project_pressed() -> void:
    _launch_main_scene()
    IntentBus.open_project_dialog_requested.emit()

func _on_recent_project_open_requested(file_path: String) -> void:
    _launch_main_scene()
    IntentBus.open_project_requested.emit(file_path)

func _on_recent_project_remove_requested(file_path: String) -> void:
    _refresh_recent_list()
    RecentProjects.remove(file_path)
