# scenes/page_panel/page_panel.gd
class_name PagePanel
extends Control

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

const DEFAULT_PAGE_NAME: String = "New Page"
const DEFAULT_ROOT_NAME: String = "Project"

enum MenuAction {
    ADD_PAGE,
    DELETE_PAGE
}

# ─────────────────────────────────────────────
# State
# ─────────────────────────────────────────────

var _tree_root : TreeItem   = null
var _item_map  : Dictionary = {}

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
    _setup_tree()
    _connect_signals()
    _update_button_states()

func _setup_tree() -> void:
    page_tree.hide_root        = true
    page_tree.allow_rmb_select = true
    page_tree.allow_reselect   = true
    page_tree.drop_mode_flags  = Tree.DROP_MODE_INBETWEEN | Tree.DROP_MODE_ON_ITEM

    page_tree.set_drag_forwarding(
        _get_drag_data,
        _can_drop_data,
        _drop_data
    )


func _connect_signals() -> void:
    btn_add_page.pressed.connect(func() -> void:
        _create_page("")
    )

    btn_delete.pressed.connect(func() -> void:
        var page: ReactivePage = AppState.focused_page.value as ReactivePage
        if page == null or page.page_id.value.is_empty():
            return
        _delete_page(page.page_id.value)
    )

    context_menu.id_pressed.connect(_on_context_menu_id_pressed)
    page_tree.item_mouse_selected.connect(
        func(_mouse_position: Vector2, mouse_button_index: int) -> void:
            _on_item_mouse_selected(mouse_button_index, false)
    )
    page_tree.nothing_selected.connect(
        func() -> void:
            AppState.focused_page.value = null
    )
    page_tree.item_activated.connect(
        func() -> void:
            _on_item_mouse_selected(MOUSE_BUTTON_LEFT, true)
    )
    page_tree.item_edited.connect(_on_item_edited)

    AppState.current_project.pages.connect_self_changed(_on_page_hierarchy_changed)
    AppState.active_page.connect_self_changed(_on_active_page_changed)
    AppState.focused_page.connect_self_changed(
        func(_origin: ReactiveVariant) -> void:
            if _origin.value == null:
                page_tree.deselect_all()
    )

# ─────────────────────────────────────────────
# Tree Building
# ─────────────────────────────────────────────

func _rebuild_tree() -> void:
    page_tree.clear()
    _item_map.clear()

    _tree_root = page_tree.create_item()
    _tree_root.set_text(0, "")
    _tree_root.set_selectable(0, true)

    if not AppState.current_project.is_loaded.value:
        return

    for item: Variant in AppState.current_project.pages.values():
        var page: ReactivePage = item as ReactivePage
        if page != null:
            _build_item(_tree_root, page)

    _tree_root.set_collapsed(false)


func _build_item(parent: TreeItem, page: ReactivePage) -> TreeItem:
    var item: TreeItem = _create_item(parent, page)
    for child_item: Variant in page.children.values():
        var child: ReactivePage = child_item as ReactivePage
        if child != null:
            _build_item(item, child)
    return item


func _create_item(parent: TreeItem, page: ReactivePage) -> TreeItem:
    var item: TreeItem = page_tree.create_item(parent)
    item.set_text(0, page.page_name.value)
    item.set_metadata(0, page)
    item.set_editable(0, false)

    _item_map[page.page_id.value] = item
    return item

# ─────────────────────────────────────────────
# Page Mutations
# ─────────────────────────────────────────────

func _create_page(page_name: String) -> void:
    if not AppState.current_project.is_loaded.value:
        push_warning("PagePanel: No active project.")
        return

    var project: ReactiveProject = AppState.current_project

    # Resolve a unique name
    var resolved: String = page_name if not page_name.is_empty() else DEFAULT_PAGE_NAME
    var offset: int = 1
    while project.find_page_name(resolved) != null:
        resolved = DEFAULT_PAGE_NAME + " " + str(offset)
        offset  += 1

    var focused: ReactivePage = AppState.focused_page.value as ReactivePage

    if focused != null and not focused.page_id.value.is_empty():
        var new_page: ReactivePage = ReactivePage.create(resolved, focused.children)
        focused.add_child_page(new_page)
    else:
        var new_page: ReactivePage = ReactivePage.create(resolved, AppState.current_project.pages)
        project.add_page(new_page)


func _delete_page(page_id: String) -> void:
    if not AppState.current_project.is_loaded.value:
        push_warning("PagePanel: No active project.")
        return

    var project: ReactiveProject = AppState.current_project

    if project.pages.values().size() == 1:
        push_warning("PagePanel: Cannot delete the last remaining page.")
        return

    var focused: ReactivePage = AppState.focused_page.value as ReactivePage
    if focused != null and focused.page_id.value == page_id:
        AppState.focused_page.value = null

    var active: ReactivePage = AppState.active_page.value as ReactivePage
    if active != null and active.page_id.value == page_id:
        AppState.active_page.value = null

    project.remove_page(page_id)

# ─────────────────────────────────────────────
# Context Menu
# ─────────────────────────────────────────────

func _show_context_menu() -> void:
    var selected: TreeItem = page_tree.get_selected()
    var has_page: bool = selected != null and selected != _tree_root

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
        MenuAction.ADD_PAGE:
            _create_page("")
        MenuAction.DELETE_PAGE:
            var selected: TreeItem = page_tree.get_selected()
            if selected == null or selected == _tree_root:
                return
            var page: ReactivePage = selected.get_metadata(0) as ReactivePage
            if page != null:
                _delete_page(page.page_id.value)

# ─────────────────────────────────────────────
# Tree Interaction
# ─────────────────────────────────────────────

func _on_item_mouse_selected(mouse_button_index: int, double_clicked: bool) -> void:
    match mouse_button_index:
        MOUSE_BUTTON_LEFT:
            var item: TreeItem = page_tree.get_selected()
            if item == null or item == _tree_root:
                return

            var page: ReactivePage = item.get_metadata(0) as ReactivePage
            if page == null:
                return

            if double_clicked:
                AppState.active_page.value = page
                return

            if AppState.focused_page.value == page:
                return

            AppState.focused_page.value = page

        MOUSE_BUTTON_RIGHT:
            _show_context_menu()


func _on_active_page_changed(active_page: ReactiveVariant) -> void:
    _update_button_states()

    if active_page.value == null:
        return

    var page_id: String = active_page.value.page_id.value if active_page.value.page_id else ""

    if page_id.is_empty() or not _item_map.has(page_id):
        return

    _item_map[page_id].select(0)


func _on_item_edited() -> void:
    var item: TreeItem = page_tree.get_selected()
    if item == null or item == _tree_root:
        return

    var page: ReactivePage = item.get_metadata(0) as ReactivePage
    if page == null:
        return

    var new_name: String = item.get_text(0).strip_edges()

    if new_name.is_empty():
        item.set_text(0, page.page_name.value)
        item.set_editable(0, false)
        return

    if new_name == page.page_name.value:
        item.set_editable(0, false)
        return

    # Mutate reactive value directly — changed signal propagates automatically
    page.page_name.value = new_name
    item.set_editable(0, false)


func _update_button_states() -> void:
    var selected: TreeItem = page_tree.get_selected()
    var has_page: bool     = selected != null and selected != _tree_root
    btn_delete.disabled = not has_page

# ─────────────────────────────────────────────
# AppState Handlers
# ─────────────────────────────────────────────
## Fires when the page hierarchy is structurally modified.
func _on_page_hierarchy_changed(_pages: ReactiveArray) -> void:
    if not AppState.current_project.is_loaded.value:
        return

    var selected_id: String = _get_selected_page_id()
    _rebuild_tree()
    if not selected_id.is_empty():
        _select_page_by_id(selected_id)

# ─────────────────────────────────────────────
# Drag and Drop
# ─────────────────────────────────────────────

func _get_drag_data(_position: Vector2) -> Variant:
    var selected: TreeItem = page_tree.get_selected()
    if selected == null or selected == _tree_root:
        return null

    var page: ReactivePage = selected.get_metadata(0) as ReactivePage
    if page == null:
        return null

    var preview: Label = Label.new()
    preview.text  = page.page_name.value
    page_tree.set_drag_preview(preview)

    return { "page": page }


func _can_drop_data(pos: Vector2, data: Variant) -> bool:
    page_tree.drop_mode_flags = Tree.DROP_MODE_ON_ITEM | Tree.DROP_MODE_INBETWEEN

    if not data is Dictionary or not data.has("page"):
        return false

    var dragged: ReactivePage = data["page"] as ReactivePage
    if dragged == null:
        return false

    var target: TreeItem = page_tree.get_item_at_position(pos)
    if target == null:
        return false

    if target == _tree_root:
        return true

    var target_page: ReactivePage = target.get_metadata(0) as ReactivePage
    if target_page == null:
        return false

    if target_page.page_id.value == dragged.page_id.value:
        return false

    return not _is_descendant_of(target_page.page_id.value, dragged)


func _drop_data(pos: Vector2, data: Variant) -> void:
    var dragged: ReactivePage = data["page"] as ReactivePage
    if dragged == null:
        return

    var target_item: TreeItem = page_tree.get_item_at_position(pos)
    if target_item == null:
        return

    var project: ReactiveProject = AppState.current_project

    if target_item == _tree_root:
        # Move to top level — detach and re-append to project root
        var page: ReactivePage = project._detach_recursive(
            dragged.page_id.value,
            project.pages
        )
        if page != null:
            page.owner = null
            project.pages.append(page)
        return

    var target_page: ReactivePage = target_item.get_metadata(0) as ReactivePage
    if target_page == null:
        return

    var drop_mode: int = page_tree.get_drop_section_at_position(pos)
    project.move_page(dragged.page_id.value, target_page, drop_mode)

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────
func _select_page_by_id(page_id: String) -> void:
    if not _item_map.has(page_id):
        return
    _item_map[page_id].select(0)

func _get_selected_page_id() -> String:
    var selected: TreeItem = page_tree.get_selected()
    if selected == null or selected == _tree_root:
        return ""
    var page: ReactivePage = selected.get_metadata(0) as ReactivePage
    return page.page_id.value if page != null else ""

func _is_descendant_of(candidate_id: String, root: ReactivePage) -> bool:
    for item: Variant in root.children.values():
        var child: ReactivePage = item as ReactivePage
        if child == null:
            continue
        if child.page_id.value == candidate_id:
            return true
        if _is_descendant_of(candidate_id, child):
            return true
    return false
