# scenes/page_manager/page_data_handler.gd
class_name PageDataHandler
extends Node

# ─────────────────────────────────────────────
# Child References
# ─────────────────────────────────────────────

@onready var page_tree    : Tree      = %PageTree
@onready var btn_add_page : Button    = %AddPageButton
@onready var btn_delete   : Button    = %DeletePageButton
@onready var context_menu : PopupMenu = %PageContextMenu

# ─────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────

const DEFAULT_PAGE_NAME := "New Page"
const DEFAULT_ROOT_NAME := "Project"
const PAGE_ICON_PATH    := "res://assets/icons/page_icon.svg"

enum MenuAction {
    ADD_PAGE,
    DELETE_PAGE
}

# ─────────────────────────────────────────────
# State
# ─────────────────────────────────────────────

## The visible root tree item — represents the project itself.
var _tree_root  : TreeItem  = null
var _page_icon  : Texture2D = null
var _item_map   : Dictionary = {}
var _is_syncing_selection: bool = false
var _last_confirmed_page_id: String = ""

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
    _load_icon()
    _setup_tree()
    _connect_signals()
    _update_button_states()


func _load_icon() -> void:
    if ResourceLoader.exists(PAGE_ICON_PATH):
        _page_icon = load(PAGE_ICON_PATH)
    else:
        push_warning("PageDataHandler: Icon not found at '%s'." % PAGE_ICON_PATH)


func _setup_tree() -> void:
    page_tree.hide_root        = false
    page_tree.allow_rmb_select = true
    page_tree.allow_reselect   = true
    page_tree.drop_mode_flags  = Tree.DROP_MODE_INBETWEEN | Tree.DROP_MODE_ON_ITEM

    page_tree.set_drag_forwarding(
        _get_drag_data,
        _can_drop_data,
        _drop_data
    )


func _connect_signals() -> void:
    # ── Buttons ───────────────────────────────────────────────────────────────
    btn_add_page.pressed.connect(_on_add_page_pressed)
    btn_delete.pressed.connect(_on_delete_pressed)

    # ── Context menu ──────────────────────────────────────────────────────────
    context_menu.id_pressed.connect(_on_context_menu_id_pressed)

    # ── Tree ──────────────────────────────────────────────────────────────────
    # item_selected is intentionally not connected — programmatic selection
    # via _item_map must not trigger a page change request.
    # Page changes are driven exclusively by mouse clicks via item_mouse_selected.
    page_tree.item_mouse_selected.connect(_on_item_mouse_selected)
    page_tree.item_edited.connect(_on_item_edited)

    # ── EventBus ──────────────────────────────────────────────────────────────
    EventBus.project_opened.connect(_on_project_opened)
    EventBus.project_closed.connect(_on_project_closed)
    EventBus.page_created.connect(_on_page_created)
    EventBus.page_deleted.connect(_on_page_deleted)
    EventBus.page_renamed.connect(_on_page_renamed)
    EventBus.page_hierarchy_changed.connect(_on_page_hierarchy_changed)

    # Consumed to confirm and sync tree selection after canvas approves the change.
    EventBus.page_changed.connect(_on_page_changed)

# ─────────────────────────────────────────────
# Tree Building
# ─────────────────────────────────────────────

func _rebuild_tree() -> void:
    page_tree.clear()
    _item_map.clear()

    _tree_root = page_tree.create_item()
    _tree_root.set_text(0, _get_project_name())
    _tree_root.set_selectable(0, true)

    if AppState.current_project == null:
        return

    for page: PageData in AppState.current_project.pages:
        _build_item(_tree_root, page)

    _tree_root.set_collapsed(false)


func _build_item(parent: TreeItem, page: PageData) -> TreeItem:
    var item := _create_item(parent, page)
    for child: PageData in page.children:
        _build_item(item, child)
    return item


func _create_item(parent: TreeItem, page: PageData) -> TreeItem:
    var item := page_tree.create_item(parent)
    item.set_text(0, page.page_name)
    item.set_metadata(0, page)
    item.set_editable(0, false)

    if _page_icon != null:
        item.set_icon(0, _page_icon)

    _item_map[page.page_id] = item
    return item


func _get_project_name() -> String:
    if AppState.current_project == null:
        return DEFAULT_ROOT_NAME
    return AppState.current_project.project_name \
           if not AppState.current_project.project_name.is_empty() \
           else DEFAULT_ROOT_NAME

# ─────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────

## Adds a new page as a child of the currently selected item.
## Falls back to the project root if nothing is selected.
func add_page(page_name: String = DEFAULT_PAGE_NAME) -> void:
    if not _assert_active_project():
        return

    var new_page  := PageData.create(page_name)
    var selected  := page_tree.get_selected()

    if selected == null or selected == _tree_root:
        # Add as top-level page
        AppState.current_project.add_page(new_page)
    else:
        # Add as child of selected page
        var parent_data: PageData = selected.get_metadata(0)
        parent_data.add_child_page(new_page)


func delete_selected_page() -> void:
    if not _assert_active_project():
        return

    var selected := page_tree.get_selected()
    if selected == null or selected == _tree_root:
        return

    var page_data: PageData = selected.get_metadata(0)

    if AppState.current_project.pages.size() == 1 \
            and selected.get_parent() == _tree_root:
        push_warning("PageDataHandler: Cannot delete the last remaining page.")
        return

    if AppState.current_page != null \
            and AppState.current_page.page_id == page_data.page_id:
        AppState.current_page = null

    AppState.current_project.remove_page(page_data.page_id)


func rename_selected_page() -> void:
    var selected := page_tree.get_selected()
    if selected == null or selected == _tree_root:
        return
    selected.set_editable(0, true)
    page_tree.edit_selected()


func select_page(page_id: String) -> void:
    if _item_map.has(page_id):
        _item_map[page_id].select(0)

# ─────────────────────────────────────────────
# Button Handlers
# ─────────────────────────────────────────────

func _on_add_page_pressed() -> void:
    add_page()


func _on_delete_pressed() -> void:
    delete_selected_page()

# ─────────────────────────────────────────────
# Context Menu
# ─────────────────────────────────────────────

func _show_context_menu() -> void:
    var selected  := page_tree.get_selected()
    var has_page  := selected != null and selected != _tree_root

    context_menu.clear()
    context_menu.add_item("Add Page", MenuAction.ADD_PAGE)
    context_menu.add_separator()
    context_menu.add_item("Delete",   MenuAction.DELETE_PAGE)
    context_menu.set_item_disabled(
        context_menu.get_item_index(MenuAction.DELETE_PAGE),
        not has_page
    )
    context_menu.popup_on_parent(
        Rect2(get_viewport().get_mouse_position(), Vector2.ZERO)
    )


func _on_context_menu_id_pressed(id: int) -> void:
    match id:
        MenuAction.ADD_PAGE:    add_page()
        MenuAction.DELETE_PAGE: delete_selected_page()

# ─────────────────────────────────────────────
# Tree Interaction
# ─────────────────────────────────────────────

func _on_item_mouse_selected(position: Vector2, mouse_button_index: int) -> void:
    match mouse_button_index:
        MOUSE_BUTTON_LEFT:
            if _is_syncing_selection:
                return

            var item := page_tree.get_selected()
            if item == null or item == _tree_root:
                return

            var page_data: PageData = item.get_metadata(0)
            if AppState.current_page != null \
                    and AppState.current_page.page_id == page_data.page_id:
                return

            # Immediately restore visual selection to current confirmed page
            # The tree will only move if the canvas confirms the change
            _is_syncing_selection = true
            if _last_confirmed_page_id != "" \
                    and _item_map.has(_last_confirmed_page_id):
                _item_map[_last_confirmed_page_id].select(0)
            _is_syncing_selection = false

            IntentBus.page_change_requested.emit(page_data)

        MOUSE_BUTTON_RIGHT:
            _show_context_menu()

## Updates tree selection only after the canvas has confirmed the page change.
func _on_page_changed(page: PageData) -> void:
    if page == null:
        return
    _last_confirmed_page_id = page.page_id
    AppState.current_page   = page
    _update_button_states()

    if not _item_map.has(page.page_id):
        return

    _is_syncing_selection = true
    _item_map[page.page_id].select(0)
    _is_syncing_selection = false

func _on_item_edited() -> void:
    var item := page_tree.get_selected()
    if item == null or item == _tree_root:
        return

    var page_data : PageData = item.get_metadata(0)
    var new_name  : String   = item.get_text(0).strip_edges()

    if new_name.is_empty():
        item.set_text(0, page_data.page_name)
        return

    if new_name == page_data.page_name:
        return

    page_data.page_name = new_name
    item.set_editable(0, false)
    EventBus.page_renamed.emit(page_data.page_id, new_name)


func _update_button_states() -> void:
    var selected := page_tree.get_selected()
    var has_page := selected != null and selected != _tree_root
    btn_delete.disabled = not has_page

# ─────────────────────────────────────────────
# Drag and Drop
# ─────────────────────────────────────────────

func _get_drag_data(_position: Vector2) -> Variant:
    var selected := page_tree.get_selected()
    if selected == null or selected == _tree_root:
        return null

    var page_data: PageData = selected.get_metadata(0)

    var preview      := Label.new()
    preview.text      = page_data.page_name
    page_tree.set_drag_preview(preview)

    return { "page": page_data }


func _can_drop_data(position: Vector2, data: Variant) -> bool:
    if not data is Dictionary or not data.has("page"):
        return false

    var dragged : PageData = data["page"]
    var target  := page_tree.get_item_at_position(position)

    if target == null:
        return false

    # Allow drop onto root — becomes a top-level page
    if target == _tree_root:
        return true

    var target_data: PageData = target.get_metadata(0)

    if target_data.page_id == dragged.page_id:
        return false

    return not _is_descendant_of(target_data.page_id, dragged)


func _drop_data(position: Vector2, data: Variant) -> void:
    var dragged     : PageData = data["page"]
    var target_item := page_tree.get_item_at_position(position)

    if target_item == null:
        return

    var drop_mode := page_tree.get_drop_section_at_position(position)

    # Remove from current position before reinserting
    AppState.current_project.remove_page(dragged.page_id)

    if target_item == _tree_root:
        AppState.current_project.add_page(dragged)
    else:
        var target_data: PageData = target_item.get_metadata(0)
        match drop_mode:
            -1: _insert_relative(dragged, target_data, 0)
            0:  target_data.children.insert(0, dragged)
            1:  _insert_relative(dragged, target_data, 1)

    EventBus.page_hierarchy_changed.emit()

# ─────────────────────────────────────────────
# Event Bus Handlers
# ─────────────────────────────────────────────

func _on_project_opened(_project_data: ProjectData) -> void:
    _rebuild_tree()
    _select_first_page()


func _on_project_closed() -> void:
    page_tree.clear()
    _item_map.clear()
    _tree_root = page_tree.create_item()
    _tree_root.set_text(0, DEFAULT_ROOT_NAME)
    _tree_root.set_selectable(0, false)
    _update_button_states()


func _on_page_created(page_data: PageData) -> void:
    var parent_item := _find_parent_item(page_data)
    var item        := _create_item(parent_item, page_data)
    item.select(0)
    _update_button_states()


func _on_page_deleted(page_id: String) -> void:
    if not _item_map.has(page_id):
        return
    _remove_item_recursive(_item_map[page_id])
    _update_button_states()


func _on_page_renamed(page_id: String, new_name: String) -> void:
    if not _item_map.has(page_id):
        return
    _item_map[page_id].set_text(0, new_name)


func _on_page_hierarchy_changed() -> void:
    var selected_id := _get_selected_page_id()
    _rebuild_tree()
    if selected_id != "":
        select_page(selected_id)

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

func _insert_relative(page: PageData, target: PageData, offset: int) -> void:
    var top_level : Array[PageData] = AppState.current_project.pages
    var index     : int             = top_level.find(target)

    if index != -1:
        top_level.insert(index + offset, page)
        EventBus.page_created.emit(page)
        return

    for entry: PageData in _iter_all_pages(AppState.current_project.pages):
        var child_index: int = entry.children.find(target)
        if child_index != -1:
            entry.children.insert(child_index + offset, page)
            EventBus.page_created.emit(page)
            return


func _remove_item_recursive(item: TreeItem) -> void:
    for child in item.get_children():
        _remove_item_recursive(child)
    var page_data: PageData = item.get_metadata(0)
    _item_map.erase(page_data.page_id)
    item.free()


func _find_parent_item(page: PageData) -> TreeItem:
    for page_id: String in _item_map:
        var candidate: PageData = _item_map[page_id].get_metadata(0)
        if candidate.get_child_page(page.page_id) != null:
            return _item_map[page_id]
    return _tree_root


func _is_descendant_of(candidate_id: String, root: PageData) -> bool:
    for child: PageData in root.children:
        if child.page_id == candidate_id:
            return true
        if _is_descendant_of(candidate_id, child):
            return true
    return false


func _iter_all_pages(pages: Array[PageData]) -> Array[PageData]:
    var result : Array[PageData] = []
    var queue  : Array[PageData] = pages.duplicate()
    while not queue.is_empty():
        var page: PageData = queue.pop_front()
        result.append(page)
        queue.append_array(page.children)
    return result


func _select_first_page() -> void:
    if AppState.current_project == null:
        return
    if AppState.current_project.pages.is_empty():
        return
    var first_page : PageData = AppState.current_project.pages[0]
    var first_id   : String   = first_page.page_id
    select_page(first_id)


func _get_selected_page_id() -> String:
    var selected := page_tree.get_selected()
    if selected == null or selected == _tree_root:
        return ""
    var page_data: PageData = selected.get_metadata(0)
    return page_data.page_id


func _assert_active_project() -> bool:
    if not AppState.has_active_project():
        push_warning("PageDataHandler: No active project.")
        return false
    return true
