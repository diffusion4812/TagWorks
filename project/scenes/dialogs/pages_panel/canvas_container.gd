# PageTabContainer.gd
class_name PageTabContainer
extends TabContainer

const CANVAS_SCENE: PackedScene = preload(
    "res://scenes/canvas/canvas.tscn"
)

const META_PAGE_ID: String = "page_id"

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    AppState.active_page.connect_self_changed(_on_active_page_changed)

    # AppState.current_project is a permanent instance — bind to its pages
    # array once, forever. _rebuild_tabs() reconciles against whatever
    # pages currently contains, so this single binding naturally handles
    # page add/remove/move AND project load/close (an empty pages array
    # after reset_to_default() simply reconciles down to zero tabs).
    AppState.current_project.pages.connect_self_changed(_on_pages_changed)

    tab_changed.connect(_on_tab_changed)

    # Connect to the internal TabBar's signal instead of the TabContainer itself
    var tab_bar: TabBar = get_tab_bar()
    tab_bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ACTIVE_ONLY
    tab_bar.close_with_middle_mouse  = true
    tab_bar.tab_close_pressed.connect(_on_tab_close_pressed)

    # Sync against whatever state current_project is already in — covers
    # the case where a project was loaded before this node existed (e.g.
    # scene reload), since connect_self_changed only captures future changes.
    _rebuild_tabs()

# ── Signal Handlers ───────────────────────────────────────────────────────────

## Fires when the close button on a tab or middle mouse button is pressed.
func _on_tab_close_pressed(tab_index: int) -> void:
    if tab_index < 0 or tab_index >= get_child_count():
        return

    var tab_node: Node = get_child(tab_index)
    if tab_node.is_queued_for_deletion():
        return

    # Retrieve the page ID from metadata before destroying the node
    if tab_node.has_meta(META_PAGE_ID):
        var closed_page_id: String = tab_node.get_meta(META_PAGE_ID)

        # If the closed tab was the active/focused one, update AppState
        if AppState.active_page.value != null and AppState.active_page.value.page_id.value == closed_page_id:
            AppState.active_page.value = null
        if AppState.focused_page.value != null and AppState.focused_page.value.page_id.value == closed_page_id:
            AppState.focused_page.value = null

    # Safely destroy the tab
    tab_node.queue_free()

    # Update visibility dynamically based on remaining active children
    _update_visibility_deferred()


func _on_pages_changed(_reactive: ReactiveArray) -> void:
    _rebuild_tabs()


func _on_active_page_changed(active_page: ReactiveVariant) -> void:
    if active_page.value == null:
        return

    var page_id: String = active_page.value.page_id.value if active_page.value.page_id else ""

    if page_id.is_empty():
        return

    if _find_tab_by_page_id(page_id) != null:
        _switch_to_tab(page_id)
    else:
        _create_tab_for_page(active_page.value as ReactivePage)


func _on_tab_changed(_tab: int) -> void:
    var page_id: String = _get_current_page_id()
    if page_id.is_empty():
        return
    var page: ReactivePage = AppState.current_project.find_page_id(page_id)
    if page != null:
        AppState.active_page.value = page

# ── Tab Management ────────────────────────────────────────────────────────────

func _rebuild_tabs() -> void:
    var current_ids: Dictionary = {}
    for item: Variant in AppState.current_project.pages.values():
        var page: ReactivePage = item as ReactivePage
        if page != null:
            current_ids[page.page_id.value] = page

    for tab: Node in get_children():
        if tab.has_meta(META_PAGE_ID):
            var page_id: String = tab.get_meta(META_PAGE_ID)
            if not current_ids.has(page_id):
                tab.queue_free()

    for page_id: String in current_ids:
        if _find_tab_by_page_id(page_id) == null:
            _create_tab_for_page(current_ids[page_id] as ReactivePage)

    _update_visibility_deferred()


func _create_tab_for_page(page: ReactivePage) -> void:
    var scroll: ScrollContainer        = ScrollContainer.new()
    scroll.name                        = "Scroll_%s" % page.page_id.value
    scroll.size_flags_horizontal       = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical         = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode      = ScrollContainer.SCROLL_MODE_AUTO
    scroll.vertical_scroll_mode        = ScrollContainer.SCROLL_MODE_AUTO

    scroll.set_meta(META_PAGE_ID, page.page_id.value)

    var canvas: WidgetCanvas            = CANVAS_SCENE.instantiate()
    canvas.name                         = "Canvas_%s" % page.page_id.value
    canvas.custom_minimum_size          = Vector2(600, 600)
    canvas.size_flags_horizontal        = Control.SIZE_SHRINK_BEGIN
    canvas.size_flags_vertical          = Control.SIZE_SHRINK_BEGIN
    canvas.data                         = page.canvas

    scroll.add_child(canvas)
    add_child(scroll)

    var tab_index: int = get_tab_count() - 1
    set_tab_title(tab_index, page.page_name.value)

    var reactive_page: ReactivePage = AppState.current_project.find_page_id(page.page_id.value)
    if reactive_page != null:
        reactive_page.canvas.is_dirty.changed.connect(
            func() -> void: _on_canvas_dirty_changed(tab_index, reactive_page.canvas.is_dirty.value)
        )

    canvas.load_page(page)

    current_tab = tab_index
    show()


func _switch_to_tab(page_id: String) -> void:
    var container: ScrollContainer = _find_tab_by_page_id(page_id)
    if container != null:
        current_tab = container.get_index()

# ── Internal Helpers ──────────────────────────────────────────────────────────

func _get_current_page_id() -> String:
    if get_tab_count() == 0 or current_tab >= get_child_count():
        return ""
    var container: Node = get_child(current_tab)
    if container.has_meta(META_PAGE_ID):
        return container.get_meta(META_PAGE_ID)
    return ""


func _find_tab_by_page_id(page_id: String) -> ScrollContainer:
    for tab: Node in get_children():
        if tab.is_queued_for_deletion():
            continue
        if tab.has_meta(META_PAGE_ID) and tab.get_meta(META_PAGE_ID) == page_id:
            return tab as ScrollContainer
    return null


## Checks remaining children to determine if the container should hide
func _update_visibility_deferred() -> void:
    # Call deferred ensures queued_free nodes are processed correctly if checked on the next frame
    _check_visibility.call_deferred()

func _check_visibility() -> void:
    var active_tab_count: int = get_children().filter(func(node: Node) -> bool: return not node.is_queued_for_deletion()).size()
    if active_tab_count == 0:
        hide()
    else:
        show()

# ── Dirty Indicator ───────────────────────────────────────────────────────────

func _on_canvas_dirty_changed(tab_index: int, dirty: bool) -> void:
    if tab_index < 0 or tab_index >= get_tab_count():
        return

    var title: String = get_tab_title(tab_index).trim_suffix(" *")
    set_tab_title(tab_index, title + (" *" if dirty else ""))
