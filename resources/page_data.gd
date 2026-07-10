# resources/page_data.gd
class_name PageData
extends Resource

# ── Properties ────────────────────────────────────────────────────────────────

## Unique identifier for this page. Generated once on creation.
@export var page_id: String = ""

## Display name shown in the PageTree.
@export var page_name: String = "New Page"

## Serialised widget canvas state for this page.
## Populated from WidgetCanvas.serialize() on save.
@export var canvas: Dictionary = {}

## Child pages — forms the hierarchy displayed in the PageTree.
@export var children: Array[PageData] = []

## When true, this page is loaded first when the project is opened.
## Only one page per project should carry this flag at any time.
## Use ProjectData.set_default_page() to change it safely.
@export var is_default: bool = false

# ── Factory ───────────────────────────────────────────────────────────────────

## Creates a new PageData instance with a unique ID and default name.
static func create(name: String = "New Page") -> PageData:
    var data          := PageData.new()
    data.page_id      =  _generate_id()
    data.page_name    = name
    return data


## Creates a PageData instance from a serialised Dictionary.
## Returns null if the payload is invalid.
static func from_dict(payload: Dictionary) -> PageData:
    var data := PageData.new()
    if not data.deserialize(payload):
        return null
    return data

# ── Hierarchy ─────────────────────────────────────────────────────────────────

## Appends a child page to this page's children list.
func add_child_page(page: PageData) -> void:
    if not children.has(page):
        children.append(page)
        EventBus.page_created.emit(page)


## Removes a child page by ID. Does not recurse into grandchildren.
## For deep removal use ProjectData.remove_page().
func remove_child_page(page_id: String) -> bool:
    for i: int in children.size():
        if children[i].page_id == page_id:
            children.remove_at(i)
            EventBus.page_deleted.emit(page_id)
            return true
    return false


## Returns a direct child page by ID, or null if not found.
func get_child_page(page_id: String) -> PageData:
    for child: PageData in children:
        if child.page_id == page_id:
            return child
    return null


## Returns true if this page has no children.
func is_leaf() -> bool:
    return children.is_empty()

# ── Serialise ─────────────────────────────────────────────────────────────────

func serialize() -> Dictionary:
    var serialised_children: Array = []
    for child: PageData in children:
        serialised_children.append(child.serialize())

    return {
        "page_id":    page_id,
        "page_name":  page_name,
        "is_default": is_default,
        "canvas":     canvas,
        "children":   serialised_children,
    }

# ── Deserialise ───────────────────────────────────────────────────────────────
func deserialize(payload: Dictionary) -> bool:
    if not _validate(payload):
        return false

    page_id    = payload.get("page_id",    _generate_id())
    page_name  = payload.get("page_name",  "New Page")
    is_default = payload.get("is_default", false)
    canvas     = payload.get("canvas",     {})

    children.clear()
    for child_data: Dictionary in payload.get("children", []):
        var child := PageData.from_dict(child_data)
        if child != null:
            children.append(child)

    return true


func _validate(payload: Dictionary) -> bool:
    if payload.is_empty():
        push_warning("PageData: Empty payload passed to deserialize().")
        return false
    if not payload.has("page_id"):
        push_warning("PageData: Missing required field 'page_id'.")
        return false
    return true

# ── Helpers ───────────────────────────────────────────────────────────────────

static func _generate_id() -> String:
    return "%s-%s" % [
        Time.get_unix_time_from_system(),
        randi() % 0xFFFF
    ]
