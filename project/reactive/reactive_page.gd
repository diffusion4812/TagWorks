# reactive/reactive_page.gd
class_name ReactivePage
extends Reactive

# ── Fields ────────────────────────────────────────────────────────────────────

var page_id    : ReactiveString
var page_name  : ReactiveString
var is_default : ReactiveBool
var canvas     : ReactiveCanvas
var children   : ReactiveArray

# ── Init ──────────────────────────────────────────────────────────────────────

func _init(initial_owner: Reactive = null, label: String = "ReactivePage") -> void:
    super._init(initial_owner, label)

    page_id    = ReactiveString.new("",    self, "page_id")
    page_name  = ReactiveString.new("",    self, "page_name")
    is_default = ReactiveBool.new(false,   self, "is_default")
    canvas     = ReactiveCanvas.new({},    self, "canvas")
    children   = ReactiveArray.new([],     self, "children")


func _describe_value() -> String:
    return '"%s"' % page_name.value

# ── Factory ───────────────────────────────────────────────────────────────────

## Creates a new ReactivePage with a generated ID and the given name.
static func create(name: String = "New Page", initial_owner: Reactive = null, label: String = "ReactivePage") -> ReactivePage:
    var p: ReactivePage = ReactivePage.new(initial_owner, label)
    p.page_id.value  = _generate_id()
    p.page_name.value = name
    return p


## Deserialises a ReactivePage from a Dictionary.
## Returns null if the payload is invalid.
static func from_dict(payload: Dictionary, initial_owner: Reactive = null) -> ReactivePage:
    if not _validate(payload):
        return null
    var p: ReactivePage = ReactivePage.new(initial_owner)
    p._deserialize(payload)
    return p

# ── Serialise ─────────────────────────────────────────────────────────────────

func serialize() -> Dictionary:
    var serialised_children: Array = []
    for item: Variant in children.values():
        var child: ReactivePage = item as ReactivePage
        if child != null:
            serialised_children.append(child.serialize())

    return {
        "page_id":    page_id.value,
        "page_name":  page_name.value,
        "is_default": is_default.value,
        "canvas":     canvas.to_data(),
        "children":   serialised_children,
    }

# ── Deserialise ───────────────────────────────────────────────────────────────

func _deserialize(payload: Dictionary) -> void:
    page_id.value    = payload.get("page_id",    _generate_id())
    page_name.value  = payload.get("page_name",  "New Page")
    is_default.value = payload.get("is_default", false)
    canvas.from_data(payload.get("canvas", {}))

    children.clear()
    for child_dict: Dictionary in payload.get("children", []):
        var child: ReactivePage = ReactivePage.from_dict(child_dict, self)
        if child != null:
            children.append(child)


static func _validate(payload: Dictionary) -> bool:
    if payload.is_empty():
        push_warning("ReactivePage: Empty payload passed to from_dict().")
        return false
    if not payload.has("page_id"):
        push_warning("ReactivePage: Missing required field 'page_id'.")
        return false
    return true

# ── Hierarchy ─────────────────────────────────────────────────────────────────

func add_child_page(page: ReactivePage) -> void:
    page.owner = self
    children.append(page)


func remove_child_page(target_id: String) -> bool:
    var items: Array = children.values()
    for i: int in items.size():
        var page: ReactivePage = items[i] as ReactivePage
        if page == null:
            continue
        if page.page_id.value == target_id:
            children.remove_at(i)
            return true
    return false


func get_child_page(target_id: String) -> ReactivePage:
    for item: Variant in children.values():
        var page: ReactivePage= item as ReactivePage
        if page != null and page.page_id.value == target_id:
            return page
    return null


func is_leaf() -> bool:
    return children.values().is_empty()

# ── Helpers ───────────────────────────────────────────────────────────────────

static func _generate_id() -> String:
    return "%s-%s" % [
        Time.get_unix_time_from_system(),
        randi() % 0xFFFF
    ]
