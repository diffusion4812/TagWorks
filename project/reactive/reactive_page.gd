# reactive/reactive_page.gd
class_name ReactivePage
extends Reactive

# ── Fields ────────────────────────────────────────────────────────────────────

var page_id    : ReactiveString
var page_name  : ReactiveString
var is_default : ReactiveBool
var canvas     : ReactiveDictionary
var children   : ReactiveArray

# ── Init ──────────────────────────────────────────────────────────────────────

func _init(data: PageData = null, initial_owner: Reactive = null, label: String = "ReactivePage") -> void:
    super._init(initial_owner, label)

    page_id    = ReactiveString.new("",    self, "page_id")
    page_name  = ReactiveString.new("",    self, "page_name")
    is_default = ReactiveBool.new(false,   self, "is_default")
    canvas     = ReactiveDictionary.new({},      self, "canvas")
    children   = ReactiveArray.new([],     self, "children")

    if data != null:
        from_data(data)

func _describe_value() -> String:
    return '"%s"' % page_name.value

# ── Sync from PageData ────────────────────────────────────────────────────────

func from_data(data: PageData) -> void:
    page_id.value    = data.page_id
    page_name.value  = data.page_name
    is_default.value = data.is_default
    canvas.value     = data.canvas.duplicate()

    children.clear()
    for child: PageData in data.children:
        children.append(ReactivePage.new(child, self))

# ── Sync back to PageData ─────────────────────────────────────────────────────

func to_data() -> PageData:
    var data        := PageData.new()
    data.page_id    = page_id.value
    data.page_name  = page_name.value
    data.is_default = is_default.value
    data.canvas     = canvas.value.duplicate()

    data.children.clear()
    for item: Variant in children.values():
        var child := item as ReactivePage
        if child != null:
            data.children.append(child.to_data())

    return data

# ── Hierarchy ─────────────────────────────────────────────────────────────────

func add_child_page(page: ReactivePage) -> void:
    page.owner = self
    children.append(page)
    EventBus.page_created.emit(page.to_data())


func remove_child_page(target_id: String) -> bool:
    var items: Array = children.values()
    for i: int in items.size():
        var page := items[i] as ReactivePage
        if page == null:
            continue
        if page.page_id.value == target_id:
            children.remove_at(i)
            EventBus.page_deleted.emit(target_id)
            return true
    return false


func get_child_page(target_id: String) -> ReactivePage:
    for item: Variant in children.values():
        var page := item as ReactivePage
        if page != null and page.page_id.value == target_id:
            return page
    return null


func is_leaf() -> bool:
    return children.values().is_empty()
