extends PanelContainer

@export var recent_project_row_scene: PackedScene
@export_file("*.tscn") var main_scene_path: String

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

## True while a new/open/recent-open operation is pending, so we don't
## allow overlapping requests or launch the main scene prematurely.
var _project_operation_pending: bool = false

func _ready() -> void:
    _close_button.pressed.connect(func() -> void: get_tree().quit(0))
    _new_project_button.pressed.connect(_on_new_project_pressed)
    _open_project_button.pressed.connect(_on_open_project_pressed)
    _runtime_only_check_button.toggled.connect(func(toggled: bool) -> void: AppState.runtime_only.value = toggled)
    AppState.runtime_only.connect_self_changed(func(runtime_only: ReactiveBool) -> void: _new_project_button.disabled = runtime_only.value)

    _populate_language_options()
    _language_option.item_selected.connect(_on_language_option_selected)
    _refresh_recent_list()

    # ── Project lifecycle ────────────────────────────────────────────────────
    AppState.current_project.is_loaded.connect_self_changed(_on_project_loaded_changed)
    ProjectManager.last_error.connect_self_changed(_on_project_error_changed)

    ResourceLoader.load_threaded_request(main_scene_path)

func _on_project_loaded_changed(is_loaded: ReactiveBool) -> void:
    if is_loaded.value:
        _launch_main_scene()

func _on_project_error_changed(error: ReactiveString) -> void:
    if not error.value.is_empty():
        push_warning("SplashScreen: %s" % error.value)

func _on_project_busy_changed(busy: ReactiveBool) -> void:
    _new_project_button.disabled = busy.value or AppState.runtime_only.value
    _open_project_button.disabled = busy.value

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
        {"code": "de", "label": "Deutsch"},
        {"code": "fr", "label": "français"}
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

## Waits (if necessary) for the threaded main-scene load to finish, then
## performs the actual scene switch.
func _launch_main_scene() -> void:
    var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(main_scene_path)

    while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
        await get_tree().process_frame
        status = ResourceLoader.load_threaded_get_status(main_scene_path)

    if status != ResourceLoader.THREAD_LOAD_LOADED:
        push_error("SplashScreen: Failed to load main scene (status: %d)" % status)
        return

    var packed_scene: PackedScene = ResourceLoader.load_threaded_get(main_scene_path)
    get_tree().change_scene_to_packed(packed_scene)

## Called once ProjectManager confirms a project was successfully
## created or opened — the only trigger point for leaving the splash screen.
func _on_project_ready() -> void:
    _launch_main_scene()

## Called if ProjectManager reports a failed open attempt (missing file,
## corrupt JSON, etc.). Re-enables the UI so the user can retry.
func _on_project_open_failed(reason: String) -> void:
    push_warning("SplashScreen: Project open failed — %s" % reason)
    _set_operation_pending(false)

func _set_operation_pending(pending: bool) -> void:
    _project_operation_pending = pending
    _new_project_button.disabled = pending or AppState.runtime_only.value
    _open_project_button.disabled = pending

func _on_new_project_pressed() -> void:
    IntentBus.new_project_requested.emit()

func _on_open_project_pressed() -> void:
    IntentBus.open_project_dialog_requested.emit()

func _on_recent_project_open_requested(file_path: String) -> void:
    IntentBus.open_project_requested.emit(file_path)

func _on_recent_project_remove_requested(file_path: String) -> void:
    RecentProjects.remove(file_path)
    _refresh_recent_list()
