# resources/project_data.gd
class_name ProjectData
extends Resource

const FILE_VERSION := 2

@export var project_name  : String          = ""
var file_path             : String          = ""
var opc_ua_servers        : Array           = []
var canvas                : Dictionary      = {}
var version               : int             = FILE_VERSION

@export var pages: Array[PageData] = []

# ── Page Management ───────────────────────────────────────────────────────────

## Adds a top-level page to the project and notifies listeners.
func add_page(page: PageData) -> void:
    pages.append(page)
    EventBus.page_created.emit(page)

## Removes a page from anywhere in the hierarchy by ID.
func remove_page(page_id: String) -> bool:
    return _remove_recursive(page_id, pages)

## Returns the first page found with is_default = true anywhere in the
## full page hierarchy. Falls back to the first top-level page if none
## is explicitly marked. Returns null if no pages exist.
func get_default_page() -> PageData:
    var marked := _find_default_recursive(pages)
    if marked != null:
        return marked
    return pages[0] if not pages.is_empty() else null


func _find_default_recursive(list: Array[PageData]) -> PageData:
    for page: PageData in list:
        if page.is_default:
            return page
        var found := _find_default_recursive(page.children)
        if found != null:
            return found
    return null


## Marks the page with the given ID as default anywhere in the full hierarchy,
## clearing the flag on every other page in the tree.
## Returns true if the target page was found and marked.
func set_default_page(page_id: String) -> bool:
    var found := _set_default_recursive(page_id, pages)
    if not found:
        push_warning("ProjectData: set_default_page() — page_id '%s' not found." % page_id)
    return found


func _set_default_recursive(page_id: String, list: Array[PageData]) -> bool:
    var found := false
    for page: PageData in list:
        if page.page_id == page_id:
            page.is_default = true
            found = true
        else:
            page.is_default = false
        # Always recurse to clear flags on all descendants
        if _set_default_recursive(page_id, page.children):
            found = true
    return found

func _remove_recursive(page_id: String, list: Array[PageData]) -> bool:
    for i: int in list.size():
        if list[i].page_id == page_id:
            list.remove_at(i)
            EventBus.page_deleted.emit(page_id)
            return true
        if _remove_recursive(page_id, list[i].children):
            return true
    return false


## Finds a page anywhere in the hierarchy by ID.
func find_page(page_id: String) -> PageData:
    return _find_recursive(page_id, pages)


func _find_recursive(page_id: String, list: Array[PageData]) -> PageData:
    for page: PageData in list:
        if page.page_id == page_id:
            return page
        var found := _find_recursive(page_id, page.children)
        if found != null:
            return found
    return null

# ── Serialise ─────────────────────────────────────────────────────────────────

func serialize() -> Dictionary:
    var serialised_pages: Array = []
    for page: PageData in pages:
        serialised_pages.append(page.serialize())

    return {
        "version":        FILE_VERSION,
        "project_name":   project_name,
        "opc_ua_servers": opc_ua_servers,
        "canvas":         canvas,
        "pages":          serialised_pages,
    }


func deserialize(payload: Dictionary) -> bool:
    if not _validate(payload):
        return false

    version        = payload.get("version",        FILE_VERSION)
    project_name   = payload.get("project_name",   "")
    opc_ua_servers = payload.get("opc_ua_servers", [])
    canvas         = payload.get("canvas",         {})

    pages.clear()
    for page_dict: Dictionary in payload.get("pages", []):
        var page := PageData.from_dict(page_dict)
        if page != null:
            pages.append(page)

    return true


func _validate(payload: Dictionary) -> bool:
    if payload.is_empty():
        return false
    var v: int = payload.get("version", 0)
    if v != FILE_VERSION:
        push_warning("ProjectData: Unsupported file version %d" % v)
        return false
    return true

# ── Factory ───────────────────────────────────────────────────────────────────

static func create_empty() -> ProjectData:
    var data        := ProjectData.new()
    data.pages       = []
    data.opc_ua_servers = []
    data.canvas      = {}
    return data


static func from_dict(payload: Dictionary) -> ProjectData:
    var data := ProjectData.new()
    if not data.deserialize(payload):
        return null
    return data
