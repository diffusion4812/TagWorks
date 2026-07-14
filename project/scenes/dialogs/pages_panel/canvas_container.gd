# PageTabContainer.gd
class_name PageTabContainer
extends TabContainer

const CANVAS_SCENE: PackedScene = preload(
    "res://scenes/canvas/canvas.tscn"
)

## Maps page_id -> ScrollContainer for active tabs.
var page_tabs: ReactiveDictionary = ReactiveDictionary.new({}, null, "page_tabs")

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    AppState.active_page.reactive_changed.connect(_on_active_page_changed)
    AppState.current_project.reactive_changed.connect(_on_current_project_changed)

    tab_changed.connect(_on_tab_changed)

    get_tab_bar().tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ACTIVE_ONLY
    get_tab_bar().close_with_middle_mouse  = true

# ── Signal Handlers ───────────────────────────────────────────────────────────

func _on_current_project_changed(_reactive) -> void:
    var project := AppState.current_project.value as ReactiveProject
    var is_open := project != null and not project.project_name.value.is_empty()

    if is_open:
        if project.pages.reactive_changed.is_connected(_on_pages_changed):
            project.pages.reactive_changed.disconnect(_on_pages_changed)
        project.pages.reactive_changed.connect(_on_pages_changed)

    _rebuild_tabs()

## Fires when the page hierarchy changes structurally.
## Syncs the tab set to match the current project page list.
func _on_pages_changed(_reactive) -> void:
    _rebuild_tabs()


## Fires when AppState.active_page changes.
## Opens a new tab or switches to an existing one.
func _on_active_page_changed(_reactive) -> void:
    var page := AppState.active_page.value as ReactivePage
    if page == null:
        return

    if page_tabs.value.has(page.page_id.value):
        _switch_to_tab(page.page_id.value)
    else:
        _create_tab_for_page(page)


## Fires when the user manually switches tabs.
## Updates AppState.focused_page to reflect the visible tab.
func _on_tab_changed(_tab: int) -> void:
    var page_id := _get_current_page_id()
    if page_id.is_empty():
        return
    var page: ReactivePage = AppState.current_project.value.find_page_id(page_id)
    if page != null:
        AppState.focused_page.value = page

# ── Tab Management ────────────────────────────────────────────────────────────

## Rebuilds the tab set to match the current project page list.
## Removes tabs for deleted pages and adds tabs for new pages.
func _rebuild_tabs() -> void:
    var current_ids: Dictionary = {}
    for item: Variant in AppState.current_project.value.pages.values():
        var page := item as ReactivePage
        if page != null:
            current_ids[page.page_id.value] = page

    # Remove tabs for pages that no longer exist
    for page_id: String in page_tabs.value.keys().duplicate():
        if not current_ids.has(page_id):
            var container: Container = page_tabs.value[page_id]
            if is_instance_valid(container):
                container.queue_free()
            page_tabs.value.erase(page_id)

    # Add tabs for new pages
    for page_id: String in current_ids:
        if not page_tabs.value.has(page_id):
            _create_tab_for_page(current_ids[page_id] as ReactivePage)

    if page_tabs.value.is_empty():
        hide()
    else:
        show()


## Creates a scroll container, canvas, and tab entry for the given page.
func _create_tab_for_page(page: ReactivePage) -> void:
    var scroll                        := ScrollContainer.new()
    scroll.name                        = "Scroll_%s" % page.page_id.value
    scroll.size_flags_horizontal       = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical         = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode      = ScrollContainer.SCROLL_MODE_AUTO
    scroll.vertical_scroll_mode        = ScrollContainer.SCROLL_MODE_AUTO

    var canvas: WidgetCanvas            = CANVAS_SCENE.instantiate()
    canvas.name                         = "Canvas_%s" % page.page_id.value
    canvas.custom_minimum_size          = Vector2(1920, 1080)
    canvas.size_flags_horizontal        = Control.SIZE_SHRINK_BEGIN
    canvas.size_flags_vertical          = Control.SIZE_SHRINK_BEGIN

    page_tabs.value[page.page_id.value] = scroll

    scroll.add_child(canvas)
    add_child(scroll)

    var tab_index: int = get_tab_count() - 1
    set_tab_title(tab_index, page.page_name.value)

    # Wire dirty indicator before load_page so any initial state is captured
    var reactive_page: ReactivePage = AppState.current_project.value.find_page_id(page.page_id.value)
    if reactive_page != null:
        reactive_page.canvas.is_dirty.changed.connect(
            func() -> void: _on_canvas_dirty_changed(tab_index, reactive_page.canvas.is_dirty.value)
        )

    # Register the page association on the canvas — scene restoration is
    # handled separately by ProjectManager._restore_canvas()
    canvas.load_page(page)

    current_tab = tab_index
    show()


## Switches the visible tab to the one matching the given page_id.
func _switch_to_tab(page_id: String) -> void:
    var container: Container = page_tabs.value[page_id]

    if not is_instance_valid(container):
        page_tabs.value.erase(page_id)
        return

    current_tab = container.get_index()

# ── Internal Helpers ──────────────────────────────────────────────────────────

func _get_current_page_id() -> String:
    if get_tab_count() == 0:
        return ""
    var container := get_child(current_tab)
    for page_id: String in page_tabs.value:
        if page_tabs.value[page_id] == container:
            return page_id
    return ""

# ── Dirty Indicator ───────────────────────────────────────────────────────────

## Updates the tab title with a dirty marker when unsaved changes exist.
func _on_canvas_dirty_changed(tab_index: int, dirty: bool) -> void:
    if tab_index < 0 or tab_index >= get_tab_count():
        return

    var title := get_tab_title(tab_index).trim_suffix(" *")
    set_tab_title(tab_index, title + (" *" if dirty else ""))
