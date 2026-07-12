# PageTabContainer.gd
class_name PageTabContainer
extends TabContainer

const CANVAS_SCENE: PackedScene = preload(
    "res://scenes/canvas/canvas.tscn"
)

# ── State ─────────────────────────────────────────────────────────────────────

## Maps page_id (String) → WidgetCanvas node.
var _page_tabs: Dictionary = {}

## Maps page_id (String) → bound Callable connected to canvas_dirty_changed.
## Stored so each callable can be cleanly disconnected on tab removal.
var _dirty_callables: Dictionary = {}

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    EventBus.page_changed.connect(_on_page_changed)
    EventBus.project_opened.connect(_on_project_opened)
    EventBus.project_closed.connect(_on_project_closed)

# ── Page Change Handler ───────────────────────────────────────────────────────

func _on_page_changed(page_data: PageData) -> void:
    if _page_tabs.has(page_data.page_id):
        _switch_to_tab(page_data.page_id)
    else:
        _create_tab_for_page(page_data)

# ── Internal Helpers ──────────────────────────────────────────────────────────

func _create_tab_for_page(page_data: PageData) -> void:
    # ── ScrollContainer wrapper ───────────────────────────────────────────────
    # Prevents WidgetCanvas from stretching to fill the tab area.
    # The scroll container fills the tab; the canvas retains a fixed size.
    var scroll := ScrollContainer.new()
    scroll.name                              = "Scroll_%s" % page_data.page_id
    scroll.size_flags_horizontal             = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical               = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode           = ScrollContainer.SCROLL_MODE_AUTO
    scroll.vertical_scroll_mode             = ScrollContainer.SCROLL_MODE_AUTO

    var canvas: WidgetCanvas = CANVAS_SCENE.instantiate()
    canvas.name                              = "Canvas_%s" % page_data.page_id

    # Fix the canvas to its designed size — adjust to match your layout.
    canvas.custom_minimum_size               = Vector2(1920, 1080)

    # Prevent the Control layout system from stretching the canvas.
    canvas.size_flags_horizontal             = Control.SIZE_SHRINK_BEGIN
    canvas.size_flags_vertical               = Control.SIZE_SHRINK_BEGIN

    _page_tabs[page_data.page_id]                 = canvas

    scroll.add_child(canvas)
    add_child(scroll)

    var tab_index: int = get_tab_count() - 1
    set_tab_title(tab_index, page_data.page_name)

    var callable := func(dirty: bool) -> void:
        _on_canvas_dirty_changed(canvas, dirty)

    _dirty_callables[page_data.page_id] = callable
    EventBus.canvas_dirty_changed.connect(callable)

    canvas.load_page(page_data)

    current_tab = tab_index
    show()


func _switch_to_tab(page_id: String) -> void:
    var canvas: WidgetCanvas = _page_tabs[page_id]

    if not is_instance_valid(canvas):
        _page_tabs.erase(page_id)
        _disconnect_dirty_callable(page_id)
        return

    current_tab = canvas.get_index()

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


## Disconnects and removes the dirty callable associated with a page_id.
func _disconnect_dirty_callable(page_id: String) -> void:
    if not _dirty_callables.has(page_id):
        return

    var callable: Callable = _dirty_callables[page_id]
    if EventBus.canvas_dirty_changed.is_connected(callable):
        EventBus.canvas_dirty_changed.disconnect(callable)

    _dirty_callables.erase(page_id)

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
    for page_id: String in _page_tabs.keys():
        _disconnect_dirty_callable(page_id)

    for canvas: WidgetCanvas in _page_tabs.values():
        if is_instance_valid(canvas):
            # Free the parent ScrollContainer — canvas is freed with it.
            var scroll := canvas.get_parent()
            if is_instance_valid(scroll):
                scroll.queue_free()
            else:
                canvas.queue_free()

    _page_tabs.clear()
    _dirty_callables.clear()
