# PageTabContainer.gd
class_name PageTabContainer
extends TabContainer

const CANVAS_SCENE: PackedScene = preload(
    "res://scenes/canvas/canvas.tscn"
)

# ── State ─────────────────────────────────────────────────────────────────────

## Maps page_id (String) → WidgetCanvas node.
var page_tabs: ReactiveDictionary = ReactiveDictionary.new({}, null, "page_tabs")

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    EventBus.project_opened.connect(_on_project_opened)
    EventBus.project_closed.connect(_on_project_closed)
    AppState.focused_page.reactive_changed.connect(_on_focused_page_changed)

# ── Page Change Handler ───────────────────────────────────────────────────────

func _on_focused_page_changed(reactive: ReactiveVariant) -> void:
    var page := reactive.value as ReactivePage
    if page == null:
        return

    if page_tabs.value.has(page.page_id.value):
        _switch_to_tab(page.page_id.value)
    else:
        _create_tab_for_page(page.to_data())

    AppState.active_page.value = page

# ── Internal Helpers ──────────────────────────────────────────────────────────

func _create_tab_for_page(page_data: PageData) -> void:
    var scroll := ScrollContainer.new()
    scroll.name                    = "Scroll_%s" % page_data.page_id
    scroll.size_flags_horizontal   = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical     = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode  = ScrollContainer.SCROLL_MODE_AUTO
    scroll.vertical_scroll_mode    = ScrollContainer.SCROLL_MODE_AUTO

    var canvas: WidgetCanvas = CANVAS_SCENE.instantiate()
    canvas.name                    = "Canvas_%s" % page_data.page_id
    canvas.custom_minimum_size     = Vector2(1920, 1080)
    canvas.size_flags_horizontal   = Control.SIZE_SHRINK_BEGIN
    canvas.size_flags_vertical     = Control.SIZE_SHRINK_BEGIN

    page_tabs.value[page_data.page_id] = scroll

    scroll.add_child(canvas)
    add_child(scroll)

    var tab_index: int = get_tab_count() - 1
    set_tab_title(tab_index, page_data.page_name)

    canvas.is_dirty.changed.connect(func(dirty: bool) -> void:
        _on_canvas_dirty_changed(canvas, dirty)
    )

    canvas.load_page(page_data)

    current_tab = tab_index
    show()


func _switch_to_tab(page_id: String) -> void:
    var container: Container = page_tabs.value[page_id]

    if not is_instance_valid(container):
        page_tabs.value.erase(page_id)
        return

    current_tab = container.get_index()

# ── Dirty Indicator ───────────────────────────────────────────────────────────

## Updates the tab title for the given canvas to reflect its dirty state.
## The canvas reference is bound at connection time so no source inspection
## is required — each lambda closure owns exactly one canvas.
func _on_canvas_dirty_changed(canvas: WidgetCanvas, dirty: bool) -> void:
    if not is_instance_valid(canvas):
        return

    var tab_index: int    = canvas.get_index()
    var title: String     = get_tab_title(tab_index)

    # Strip any existing indicator before reapplying to avoid accumulation.
    title = title.trim_suffix(" *")

    set_tab_title(tab_index, title + (" *" if dirty else ""))

# ── Project Lifecycle ─────────────────────────────────────────────────────────

func _on_project_opened(project_data: ProjectData) -> void:
    _clear_all_tabs()

    var initial_page: PageData = project_data.get_default_page()
    if initial_page != null:
        _create_tab_for_page(initial_page)


func _on_project_closed() -> void:
    _clear_all_tabs()
    hide()


## Disconnects all dirty callables, frees all canvas children, and resets
## internal state. Safe to call across project open/close cycles.
func _clear_all_tabs() -> void:
    for container: Container in page_tabs.value.values():
        if is_instance_valid(container):
            container.queue_free()

    page_tabs.value.clear()
