extends Node

const SAVE_PATH: String = "user://recent_projects.json"
const MAX_ENTRIES: int = 10

var entries: Array[Dictionary] = []

func _ready() -> void:
    _load()

func add(path: String, display_name: String) -> void:
    entries = entries.filter(func(e): return e.file_path != path)
    entries.push_front({
        "file_path": path,
        "display_name": display_name,
        "last_opened": Time.get_unix_time_from_system(),
    })
    if entries.size() > MAX_ENTRIES:
        entries.resize(MAX_ENTRIES)
    _save()

func remove(path: String) -> void:
    entries = entries.filter(func(e): return e.file_path != path)
    _save()

func _save() -> void:
    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file == null:
        push_warning("RecentProjects: failed to open '%s' for writing (error %s)." % [SAVE_PATH, FileAccess.get_open_error()])
        return
    file.store_string(JSON.stringify(entries, "\t"))

func _load() -> void:
    if not FileAccess.file_exists(SAVE_PATH):
        return
    var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if file == null:
        push_warning("RecentProjects: failed to open '%s' for reading (error %s)." % [SAVE_PATH, FileAccess.get_open_error()])
        return
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if parsed is Array:
        entries.assign(parsed)
    else:
        push_warning("RecentProjects: '%s' contained invalid data — ignoring." % SAVE_PATH)
