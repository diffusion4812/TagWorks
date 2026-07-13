# reactive/reactive_project.gd
class_name ReactiveProject
extends ReactiveObject

# ── Fields ────────────────────────────────────────────────────────────────────

var project_name   : ReactiveString
var file_path      : ReactiveString
var opc_ua_servers : ReactiveDictionary
var canvas         : ReactiveCanvas
var pages          : ReactiveArray

# ── Init ──────────────────────────────────────────────────────────────────────

func _init(data: ProjectData = null, initial_owner: Reactive = null) -> void:
    super._init(null, initial_owner)

    project_name   = ReactiveString.new("",      self)
    file_path      = ReactiveString.new("",      self)
    opc_ua_servers = ReactiveDictionary.new({},  self)
    canvas         = ReactiveCanvas.new({},      self)
    pages          = ReactiveArray.new([],       self)

    if data != null:
        from_data(data)

# ── Sync from ProjectData ─────────────────────────────────────────────────────

func from_data(data: ProjectData) -> void:
    project_name.value   = data.project_name
    file_path.value      = data.file_path
    canvas.from_data(data.canvas)

    pages.clear()
    for page: PageData in data.pages:
        pages.append(ReactivePage.new(page, self))

    value = data

# ── Sync back to ProjectData ──────────────────────────────────────────────────

func to_data() -> ProjectData:
    var data            := ProjectData.new()
    data.project_name   = project_name.value
    data.file_path      = file_path.value
    data.canvas         = canvas.to_data()

    data.pages.clear()
    for item: Variant in pages.values():
        var page := item as ReactivePage
        if page != null:
            data.pages.append(page.to_data())

    return data

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
            EventBus.page_deleted.emit(target_id)
            return true
        if _remove_recursive(target_id, page.children):
            return true
    return false


## Moves a page to a new position in the hierarchy.
## drop_mode matches Godot's Tree drop section constants:
##  -1 = insert above target
##   0 = insert as first child of target
##   1 = insert below target
func move_page(page_id: String, target: ReactivePage, drop_mode: int) -> bool:
    if drop_mode == 2 or drop_mode == -100:
        push_warning("ReactiveProject: Cannot move page with an invalid drop mode '%s'." % drop_mode)
        return false
    # Prevent dropping a page onto itself or its own descendant
    if page_id == target.page_id.value or _is_ancestor(page_id, target):
        push_warning("ReactiveProject: Cannot move page '%s' into itself or a descendant." % page_id)
        return false

    var page := _detach_recursive(page_id, pages)
    if page == null:
        push_warning("ReactiveProject: Could not detach page '%s' for move." % page_id)
        return false

    match drop_mode:
        0:
            page.owner = target
            target.children.insert(0, page)
        -1:
            _insert_sibling(page, target, 0)
        1:
            _insert_sibling(page, target, 1)

    EventBus.page_hierarchy_changed.emit()
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
    return _set_default_recursive(target_id, pages)


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

## Removes and returns a page from anywhere in the hierarchy without emitting
## page_deleted — the page is being relocated, not destroyed.
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


## Inserts page immediately before (offset 0) or after (offset 1) the target
## within the target's parent array.
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


## Returns the ReactiveArray that directly contains the page with target_id.
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


## Returns the ReactivePage that directly owns target_id, or null if top-level.
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


## Returns true if ancestor_id is a direct or indirect parent of target.
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
