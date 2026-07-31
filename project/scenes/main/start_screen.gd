extends CenterContainer

@export var recent_project_row_scene: PackedScene

@onready var _recent_section: VBoxContainer = %RecentProjectsSection
@onready var _recent_list: VBoxContainer = %RecentProjectsList
@onready var _new_project_button: Button = %NewProjectButton
@onready var _open_project_button: Button = %OpenProjectButton

func _ready() -> void:
    _new_project_button.pressed.connect(_on_new_project_pressed)
    _open_project_button.pressed.connect(_on_open_project_pressed)
    _refresh_recent_list()

func _refresh_recent_list() -> void:
    for child: Node in _recent_list.get_children():
        child.queue_free()

    var entries: Array[Dictionary] = RecentProjects.entries
    _recent_section.visible = not entries.is_empty()

    for entry: Dictionary in entries:
        var row: RecentProjectRow = recent_project_row_scene.instantiate()
        _recent_list.add_child(row)

        var row_data: Dictionary = entry.duplicate()
        row_data["exists"] = FileAccess.file_exists(entry.get("file_path", ""))

        row.setup(row_data)
        row.open_requested.connect(_on_recent_project_open_requested)
        row.remove_requested.connect(_on_recent_project_remove_requested)

func _on_new_project_pressed() -> void:
    # Hand off to your existing new-project flow (dialog, wizard, etc.)
    IntentBus.new_project_requested.emit()

func _on_open_project_pressed() -> void:
    # Hand off to your existing file-picker flow
    IntentBus.open_project_dialog_requested.emit()

func _on_recent_project_open_requested(file_path: String) -> void:
    IntentBus.open_project_requested.emit(file_path)

func _on_recent_project_remove_requested(file_path: String) -> void:
    RecentProjects.remove(file_path)
    _refresh_recent_list()
