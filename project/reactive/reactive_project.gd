# reactive/reactive_project.gd
class_name ReactiveProject
extends ReactiveObject

# ── Fields ────────────────────────────────────────────────────────────────────

var project_name   : ReactiveString
var file_path      : ReactiveString
var opc_ua_servers : ReactiveDict
var canvas         : ReactiveDict
var pages          : ReactiveArray

# ── Init ──────────────────────────────────────────────────────────────────────

func _init(data: ProjectData = null, initial_owner: Reactive = null) -> void:
    super._init(null, initial_owner)

    project_name   = ReactiveString.new("", self)
    file_path      = ReactiveString.new("", self)
    opc_ua_servers = ReactiveDict.new({},   self)
    canvas         = ReactiveDict.new({},   self)
    pages          = ReactiveArray.new([],  self)

    if data != null:
        from_data(data)

# ── Sync from ProjectData ─────────────────────────────────────────────────────

func from_data(data: ProjectData) -> void:
    project_name.value   = data.project_name
    file_path.value      = data.file_path
    canvas.value         = data.canvas.duplicate()

    pages.clear()
    for page: PageData in data.pages:
        pages.append(ReactivePage.new(page, self))

    value = data

# ── Sync back to ProjectData ──────────────────────────────────────────────────

func to_data() -> ProjectData:
    var data            := ProjectData.new()
    data.project_name   = project_name.value
    data.file_path      = file_path.value
    data.canvas         = canvas.value.duplicate()

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
    EventBus.page_created.emit(page.to_data())


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


func find_page(target_id: String) -> ReactivePage:
    return _find_recursive(target_id, pages)


func _find_recursive(target_id: String, array: ReactiveArray) -> ReactivePage:
    for item: Variant in array.values():
        var page := item as ReactivePage
        if page == null:
            continue
        if page.page_id.value == target_id:
            return page
        var found: ReactivePage = _find_recursive(target_id, page.children)
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
