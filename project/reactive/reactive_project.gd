# reactive/reactive_project.gd
class_name ReactiveProject
extends ReactiveObject

# ── Constants ─────────────────────────────────────────────────────────────────

const FILE_VERSION := 2

# ── Fields ────────────────────────────────────────────────────────────────────

var project_name   : ReactiveString
var file_path      : ReactiveString
var opc_ua_servers : ReactiveArray
var pages          : ReactiveArray

# ── Init ──────────────────────────────────────────────────────────────────────

func _init(initial_owner: Reactive = null, label: String = "") -> void:
    super._init(null, initial_owner, label)

    project_name   = ReactiveString.new("",     self, "project_name")
    file_path      = ReactiveString.new("",     self, "file_path")
    opc_ua_servers = ReactiveArray.new([],      self, "opc_ua_servers")
    pages          = ReactiveArray.new([],      self, "pages")

func _describe_value() -> String:
    if project_name == null:
        return ""
    return project_name.value

# ── Factory ───────────────────────────────────────────────────────────────────

## Returns a new, empty ReactiveProject.
static func create_empty() -> ReactiveProject:
    return ReactiveProject.new()


## Deserialises a ReactiveProject from a Dictionary.
## Returns null if the payload is invalid.
static func from_dict(payload: Dictionary) -> ReactiveProject:
    if not _validate(payload):
        return null
    var p := ReactiveProject.new()
    p._deserialize(payload)
    return p

# ── Serialise ─────────────────────────────────────────────────────────────────

func serialize() -> Dictionary:
    var serialised_pages: Array = []
    for item: Variant in pages.values():
        var page := item as ReactivePage
        if page != null:
            serialised_pages.append(page.serialize())

    return {
        "version":        FILE_VERSION,
        "project_name":   project_name.value,
        "opc_ua_servers": opc_ua_servers.value.duplicate(),
        "pages":          serialised_pages,
    }

# ── Deserialise ───────────────────────────────────────────────────────────────

func _deserialize(payload: Dictionary) -> void:
    project_name.value   = payload.get("project_name",   "")
    opc_ua_servers.value = payload.get("opc_ua_servers", {})

    pages.clear()
    for page_dict: Dictionary in payload.get("pages", []):
        var page := ReactivePage.from_dict(page_dict, self)
        if page != null:
            pages.append(page)


static func _validate(payload: Dictionary) -> bool:
    if payload.is_empty():
        push_warning("ReactiveProject: Empty payload.")
        return false
    var v: int = payload.get("version", 0)
    if v != FILE_VERSION:
        push_warning("ReactiveProject: Unsupported file version %d." % v)
        return false
    return true

# ── Page Management ───────────────────────────────────────────────────────────

func add_page(page: ReactivePage) -> void:
    page.owner = self
    pages.append(page)

func remove_page(target_id: String) -> bool:
    return _remove_recursive(target_id, pages)


func _remove_recursive(target_id: String, array: ReactiveArray) -> bool:
    var items: Array = array.values()
    for i: int in items.size():
        var page := items[i] as ReactivePage
        if page == null:
            continue
        if page.page_id.value == target_id:
            array.remove_at(i)
            return true
        if _remove_recursive(target_id, page.children):
            return true
    return false


func move_page(page_id: String, target: ReactivePage, drop_mode: int) -> bool:
    if drop_mode == 2 or drop_mode == -100:
        push_warning("ReactiveProject: Invalid drop mode '%s'." % drop_mode)
        return false
    if page_id == target.page_id.value or _is_ancestor(page_id, target):
        push_warning("ReactiveProject: Cannot move '%s' into itself or a descendant." % page_id)
        return false

    var page := _detach_recursive(page_id, pages)
    if page == null:
        push_warning("ReactiveProject: Could not detach page '%s'." % page_id)
        return false

    match drop_mode:
        0:
            page.owner = target
            target.children.insert(0, page)
        -1:
            _insert_sibling(page, target, 0)
        1:
            _insert_sibling(page, target, 1)

    return true


func find_page_id(target_id: String) -> ReactivePage:
    return _find_recursive_id(target_id, pages)


func _find_recursive_id(target_id: String, array: ReactiveArray) -> ReactivePage:
    for item: Variant in array.values():
        var page := item as ReactivePage
        if page == null:
            continue
        if page.page_id.value == target_id:
            return page
        var found: ReactivePage = _find_recursive_id(target_id, page.children)
        if found != null:
            return found
    return null


func find_page_name(target_name: String) -> ReactivePage:
    return _find_recursive_name(target_name, pages)


func _find_recursive_name(target_name: String, array: ReactiveArray) -> ReactivePage:
    for item: Variant in array.values():
        var page := item as ReactivePage
        if page == null:
            continue
        if page.page_name.value == target_name:
            return page
        var found: ReactivePage = _find_recursive_name(target_name, page.children)
        if found != null:
            return found
    return null


func get_default_page() -> ReactivePage:
    var marked: ReactivePage = _find_default_recursive(pages)
    if marked != null:
        return marked
    var all: Array = pages.values()
    return all[0] as ReactivePage if not all.is_empty() else null


func _find_default_recursive(array: ReactiveArray) -> ReactivePage:
    for item: Variant in array.values():
        var page := item as ReactivePage
        if page == null:
            continue
        if page.is_default.value:
            return page
        var found: ReactivePage = _find_default_recursive(page.children)
        if found != null:
            return found
    return null


func set_default_page(target_id: String) -> bool:
    var found := _set_default_recursive(target_id, pages)
    if not found:
        push_warning("ReactiveProject: set_default_page() — page_id '%s' not found." % target_id)
    return found


func _set_default_recursive(target_id: String, array: ReactiveArray) -> bool:
    var found: bool = false
    for item: Variant in array.values():
        var page := item as ReactivePage
        if page == null:
            continue
        page.is_default.value = (page.page_id.value == target_id)
        if page.is_default.value:
            found = true
        if _set_default_recursive(target_id, page.children):
            found = true
    return found

# ── Move Helpers ──────────────────────────────────────────────────────────────

func _detach_recursive(target_id: String, array: ReactiveArray) -> ReactivePage:
    var items: Array = array.values()
    for i: int in items.size():
        var page := items[i] as ReactivePage
        if page == null:
            continue
        if page.page_id.value == target_id:
            array.remove_at(i)
            return page
        var found := _detach_recursive(target_id, page.children)
        if found != null:
            return found
    return null


func _insert_sibling(page: ReactivePage, target: ReactivePage, offset: int) -> void:
    var parent_array := _find_parent_array(target.page_id.value, pages)
    if parent_array == null:
        push_warning("ReactiveProject: Could not find parent array for target '%s'." % target.page_id.value)
        return

    var items: Array = parent_array.values()
    for i: int in items.size():
        var item := items[i] as ReactivePage
        if item != null and item.page_id.value == target.page_id.value:
            page.owner = _find_parent_page(target.page_id.value)
            parent_array.insert(i + offset, page)
            return


func _find_parent_array(target_id: String, array: ReactiveArray) -> ReactiveArray:
    for item: Variant in array.values():
        var page := item as ReactivePage
        if page == null:
            continue
        if page.page_id.value == target_id:
            return array
        var found := _find_parent_array(target_id, page.children)
        if found != null:
            return found
    return null


func _find_parent_page(target_id: String) -> ReactivePage:
    return _find_parent_page_recursive(target_id, pages, null)


func _find_parent_page_recursive(
    target_id : String,
    array     : ReactiveArray,
    parent    : ReactivePage
) -> ReactivePage:
    for item: Variant in array.values():
        var page := item as ReactivePage
        if page == null:
            continue
        if page.page_id.value == target_id:
            return parent
        var found := _find_parent_page_recursive(target_id, page.children, page)
        if found != null:
            return found
    return null


func _is_ancestor(ancestor_id: String, target: ReactivePage) -> bool:
    return _is_ancestor_recursive(ancestor_id, target.children)


func _is_ancestor_recursive(ancestor_id: String, array: ReactiveArray) -> bool:
    for item: Variant in array.values():
        var page := item as ReactivePage
        if page == null:
            continue
        if page.page_id.value == ancestor_id:
            return true
        if _is_ancestor_recursive(ancestor_id, page.children):
            return true
    return false
