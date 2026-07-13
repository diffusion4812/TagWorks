# PageTabContainer.gd
class_name PageTabContainer
extends TabContainer

const CANVAS_SCENE: PackedScene = preload(
    "res://scenes/canvas/canvas.tscn"
)

var page_tabs: ReactiveDictionary = ReactiveDictionary.new({}, null, "page_tabs")

func _ready() -> void:
    AppState.focused_page.reactive_changed.connect(_on_focused_page_changed)
    AppState.current_project.pages.reactive_changed.connect(_on_pages_changed)
    tab_changed.connect(
        func(_tab: int) -> void:
            var page_id := _get_current_page_id()
            if page_id.is_empty():
                return
            var page: ReactivePage = AppState.current_project.find_page_id(page_id)
            if page != null:
                AppState.active_page.value = page
    )

    get_tab_bar().tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ACTIVE_ONLY
    get_tab_bar().close_with_middle_mouse = true

# ── Pages Change Handler ──────────────────────────────────────────────────────

func _on_pages_changed(_reactive) -> void:
    _rebuild_page_tree()

# ── Page Focus Handler ────────────────────────────────────────────────────────

func _on_focused_page_changed(reactive: ReactiveVariant) -> void:
    var page := reactive.value as ReactivePage
    if page == null:
        return

    if page_tabs.value.has(page.page_id.value):
        _switch_to_tab(page.page_id.value)
    else:
        _create_tab_for_page(page.to_data())

    AppState.active_page.value = page

# ── Tree Rebuild ──────────────────────────────────────────────────────────────

func _rebuild_page_tree() -> void:
    var current_pages: Array = AppState.current_project.pages.value

    # Collect the set of page IDs currently active.
    var current_ids := {}
    for page: ReactivePage in current_pages:
        current_ids[page.page_id.value] = page

    # Remove tabs for pages that no longer exist.
    for page_id: String in page_tabs.value.keys():
        if not current_ids.has(page_id):
            var container: Container = page_tabs.value[page_id]
            if is_instance_valid(container):
                container.queue_free()
            page_tabs.value.erase(page_id)

    # Add tabs for pages that are new.
    for page_id: String in current_ids:
        if not page_tabs.value.has(page_id):
            var page: ReactivePage = current_ids[page_id]
            _create_tab_for_page(page.to_data())

    if page_tabs.value.is_empty():
        hide()
    else:
        show()

# ── Internal Helpers ──────────────────────────────────────────────────────────

func _get_current_page_id() -> String:
    var container := get_child(current_tab)
    for page_id: String in page_tabs.value:
        if page_tabs.value[page_id] == container:
            return page_id
    return ""


func _create_tab_for_page(page_data: PageData) -> void:
    var scroll := ScrollContainer.new()
    scroll.name                   = "Scroll_%s" % page_data.page_id
    scroll.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO

    var canvas: WidgetCanvas = CANVAS_SCENE.instantiate()
    canvas.name                   = "Canvas_%s" % page_data.page_id
    canvas.custom_minimum_size    = Vector2(1920, 1080)
    canvas.size_flags_horizontal  = Control.SIZE_SHRINK_BEGIN
    canvas.size_flags_vertical    = Control.SIZE_SHRINK_BEGIN

    page_tabs.value[page_data.page_id] = scroll

    scroll.add_child(canvas)
    add_child(scroll)

    var tab_index: int = get_tab_count() - 1
    set_tab_title(tab_index, page_data.page_name)

    canvas.load_page(ReactivePage.new(page_data))

    current_tab = tab_index
    show()


func _switch_to_tab(page_id: String) -> void:
    var container: Container = page_tabs.value[page_id]

    if not is_instance_valid(container):
        page_tabs.value.erase(page_id)
        return

    current_tab = container.get_index()

# ── Dirty Indicator ───────────────────────────────────────────────────────────

func _on_canvas_dirty_changed(canvas: WidgetCanvas, dirty: bool) -> void:
    if not is_instance_valid(canvas):
        return

    var tab_index: int = canvas.get_index()
    var title: String  = get_tab_title(tab_index)

    title = title.trim_suffix(" *")
    set_tab_title(tab_index, title + (" *" if dirty else ""))
