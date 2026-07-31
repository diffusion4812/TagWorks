class_name ReactiveProject
extends ReactiveObject

# ── Constants ─────────────────────────────────────────────────────────────────

const FILE_VERSION: int = 2


## ── Persisted configuration ────────────────────────────────────────────────
var project_name   : ReactiveString
var file_path      : ReactiveString
var opc_ua_servers : ReactiveDictionary  # key: String (server id), value: ReactiveOpcUaServer
var pages          : ReactiveArray

## ── Runtime-only state ──────────────────────────────────────────────────────
var is_loaded      : ReactiveBool

    # ── Init ──────────────────────────────────────────────────────────────────────

func _init(initial_owner: Reactive = null, label: String = "") -> void:
    super._init(null, initial_owner, label)

    project_name   = ReactiveString.new("", self, "project_name")
    file_path      = ReactiveString.new("", self, "file_path")
    opc_ua_servers = ReactiveDictionary.new(
        {}, self, "opc_ua_servers",
        TYPE_STRING, &"", null,
        TYPE_OBJECT, &"Resource", null
    )
    pages          = ReactiveArray.new([], self, "pages")

    is_loaded      = ReactiveBool.new(false, null, "is_loaded")

func _describe_value() -> String:
    if project_name == null:
        return ""
    return project_name.value

# ── Lifecycle ─────────────────────────────────────────────────────────────────

## Resets this project to a fresh, empty state in place. Preserves instance
## identity, so anything bound to this ReactiveProject or its children never
## needs to rebind.
func reset_to_default() -> void:
    project_name.value = ""
    file_path.value    = ""
    opc_ua_servers.clear()
    pages.clear()

# ── Factory ───────────────────────────────────────────────────────────────────

static func validate_payload(payload: Dictionary) -> bool:
    return _validate(payload)

## Deserialises a ReactiveProject from a Dictionary.
## Returns null if the payload is invalid.
static func from_dict(payload: Dictionary) -> ReactiveProject:
    if not _validate(payload):
        return null
    var p: ReactiveProject = ReactiveProject.new()
    p.load_from_dict(payload)
    return p

static func _validate(payload: Dictionary) -> bool:
    if payload.is_empty():
        push_warning("ReactiveProject: Empty payload.")
        return false
    var v: int = payload.get("version", 0)
    if v != FILE_VERSION:
        push_warning("ReactiveProject: Unsupported file version %d." % v)
        return false
    return true

# ── Serialise ─────────────────────────────────────────────────────────────────

func serialize() -> Dictionary:
    var serialised_pages: Array = []
    for item: Variant in pages.values():
        var page: ReactivePage = item as ReactivePage
        if page != null:
            serialised_pages.append(page.serialize())

    var serialised_servers: Array = []
    for server: ReactiveOpcUaServer in opc_ua_servers.values():
        serialised_servers.append(server.serialize())

    return {
        "version":        FILE_VERSION,
        "project_name":   project_name.value,
        "opc_ua_servers": serialised_servers,
        "pages":          serialised_pages,
    }

# ── Deserialise ───────────────────────────────────────────────────────────────

## Replaces this project's contents in place, without changing identity.
## Anything bound to this instance or its children (pages, opc_ua_servers)
## simply observes a "changed" signal — no rebinding required anywhere.
func load_from_dict(payload: Dictionary) -> void:
    project_name.value = payload.get("project_name", "")
    file_path.value    = payload.get("file_path", "")

    opc_ua_servers.clear()
    for server_dict: Dictionary in payload.get("opc_ua_servers", []):
        var server: ReactiveOpcUaServer = ReactiveOpcUaServer.new(server_dict, self, "server")
        add_server(server)

    pages.clear()
    for page_dict: Dictionary in payload.get("pages", []):
        var page: ReactivePage = ReactivePage.from_dict(page_dict, self)
        if page != null:
            pages.append(page)

# ── Server Management ─────────────────────────────────────────────────────────

func get_server(server_id: String) -> ReactiveOpcUaServer:
    return opc_ua_servers.get_entry(server_id, null)

func has_server(server_id: String) -> bool:
    return opc_ua_servers.has_entry(server_id)

func remove_server(server_id: String) -> bool:
    return opc_ua_servers.erase_entry(server_id)

func add_server(server: ReactiveOpcUaServer) -> void:
    var key: String = server.id.value
    if opc_ua_servers.has_entry(key):
        push_warning("ReactiveProject: duplicate opc_ua_server id '%s' — overwriting." % key)
    opc_ua_servers.set_entry(key, server)

# ── Page Management ───────────────────────────────────────────────────────────

func add_page(page: ReactivePage) -> void:
    page.owner = self
    pages.append(page)

func remove_page(target_id: String) -> bool:
    return _remove_recursive(target_id, pages)


func _remove_recursive(target_id: String, array: ReactiveArray) -> bool:
    var items: Array = array.values()
    for i: int in items.size():
        var page: ReactivePage = items[i] as ReactivePage
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

    var page: ReactivePage = _detach_recursive(page_id, pages)
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
        var page: ReactivePage = item as ReactivePage
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
        var page: ReactivePage = item as ReactivePage
        if page == null:
            continue
        if page.page_name.value == target_name:
            return page
        var found: ReactivePage = _find_recursive_name(target_name, page.children)
        if found != null:
            return found
    return null


func get_default_page(default_first: bool = false) -> ReactivePage:
    var marked: ReactivePage = _find_default_recursive(pages)
    if marked != null:
        return marked
    if default_first:
        var all: Array = pages.values()
        return all[0] as ReactivePage if not all.is_empty() else null
    return null


func _find_default_recursive(array: ReactiveArray) -> ReactivePage:
    for item: Variant in array.values():
        var page: ReactivePage = item as ReactivePage
        if page == null:
            continue
        if page.is_default.value:
            return page
        var found: ReactivePage = _find_default_recursive(page.children)
        if found != null:
            return found
    return null


func set_default_page(target_id: String) -> bool:
    var found: bool = _set_default_recursive(target_id, pages)
    if not found:
        push_warning("ReactiveProject: set_default_page() — page_id '%s' not found." % target_id)
    return found


func _set_default_recursive(target_id: String, array: ReactiveArray) -> bool:
    var found: bool = false
    for item: Variant in array.values():
        var page: ReactivePage = item as ReactivePage
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
        var page: ReactivePage = items[i] as ReactivePage
        if page == null:
            continue
        if page.page_id.value == target_id:
            array.remove_at(i)
            return page
        var found: ReactivePage = _detach_recursive(target_id, page.children)
        if found != null:
            return found
    return null


func _insert_sibling(page: ReactivePage, target: ReactivePage, offset: int) -> void:
    var parent_array: ReactiveArray = _find_parent_array(target.page_id.value, pages)
    if parent_array == null:
        push_warning("ReactiveProject: Could not find parent array for target '%s'." % target.page_id.value)
        return

    var items: Array = parent_array.values()
    for i: int in items.size():
        var item: ReactivePage = items[i] as ReactivePage
        if item != null and item.page_id.value == target.page_id.value:
            page.owner = _find_parent_page(target.page_id.value)
            parent_array.insert(i + offset, page)
            return


func _find_parent_array(target_id: String, array: ReactiveArray) -> ReactiveArray:
    for item: Variant in array.values():
        var page: ReactivePage = item as ReactivePage
        if page == null:
            continue
        if page.page_id.value == target_id:
            return array
        var found: ReactiveArray = _find_parent_array(target_id, page.children)
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
        var page: ReactivePage = item as ReactivePage
        if page == null:
            continue
        if page.page_id.value == target_id:
            return parent
        var found: ReactivePage = _find_parent_page_recursive(target_id, page.children, page)
        if found != null:
            return found
    return null


func _is_ancestor(ancestor_id: String, target: ReactivePage) -> bool:
    return _is_ancestor_recursive(ancestor_id, target.children)


func _is_ancestor_recursive(ancestor_id: String, array: ReactiveArray) -> bool:
    for item: Variant in array.values():
        var page: ReactivePage = item as ReactivePage
        if page == null:
            continue
        if page.page_id.value == ancestor_id:
            return true
        if _is_ancestor_recursive(ancestor_id, page.children):
            return true
    return false
