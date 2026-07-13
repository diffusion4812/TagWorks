# scenes/canvas/canvas.gd
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

var _tree_root : TreeItem  = null
var _page_icon : Texture2D = null
var _item_map  : Dictionary = {}

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
    btn_add_page.pressed.connect(func() -> void:
        IntentBus.add_page_requested.emit("")
    )

    btn_delete.pressed.connect(func() -> void:
        var page := AppState.focused_page.value as ReactivePage
        if page == null:
            return
        IntentBus.delete_page_requested.emit(page.page_id.value)
    )

    context_menu.id_pressed.connect(_on_context_menu_id_pressed)
    page_tree.item_mouse_selected.connect(_on_item_mouse_selected)
    page_tree.item_edited.connect(_on_item_edited)

    IntentBus.add_page_requested.connect(_on_add_page_requested)
    IntentBus.delete_page_requested.connect(_on_delete_page_requested)

    EventBus.project_opened.connect(_on_project_opened)
    EventBus.project_closed.connect(_on_project_closed)
    EventBus.page_hierarchy_changed.connect(_on_page_hierarchy_changed)

    AppState.focused_page.changed.connect(_on_focus_changed)

# ─────────────────────────────────────────────
# Tree Building
# ─────────────────────────────────────────────

func _rebuild_tree() -> void:
    page_tree.clear()
    _item_map.clear()

    _tree_root = page_tree.create_item()
    _tree_root.set_text(0, _get_project_name())
    _tree_root.set_selectable(0, true)

    if not AppState.has_active_project():
        return

    for item: Variant in AppState.current_project.pages.values():
        var page := item as ReactivePage
        if page != null:
            _build_item(_tree_root, page)

    _tree_root.set_collapsed(false)


func _build_item(parent: TreeItem, page: ReactivePage) -> TreeItem:
    var item := _create_item(parent, page)
    for child_item: Variant in page.children.values():
        var child := child_item as ReactivePage
        if child != null:
            _build_item(item, child)
    return item


func _create_item(parent: TreeItem, page: ReactivePage) -> TreeItem:
    var item := page_tree.create_item(parent)
    item.set_text(0, page.page_name.value)
    item.set_metadata(0, page)
    item.set_editable(0, false)

    if _page_icon != null:
        item.set_icon(0, _page_icon)

    _item_map[page.page_id.value] = item
    return item


func _get_project_name() -> String:
    if not AppState.has_active_project():
        return DEFAULT_ROOT_NAME
    var name := AppState.current_project.project_name.value
    return name if not name.is_empty() else DEFAULT_ROOT_NAME

# ─────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────

func add_page(page_name: String = DEFAULT_PAGE_NAME) -> void:
    if not _assert_active_project():
        return

    var new_page := ReactivePage.new(PageData.create(page_name))
    var selected := page_tree.get_selected()

    if selected == null or selected == _tree_root:
        AppState.current_project.add_page(new_page)
    else:
        var parent_page := selected.get_metadata(0) as ReactivePage
        if parent_page != null:
            parent_page.add_child_page(new_page)


func delete_selected_page() -> void:
    if not _assert_active_project():
        return

    var selected := page_tree.get_selected()
    if selected == null or selected == _tree_root:
        return

    var page := selected.get_metadata(0) as ReactivePage
    if page == null:
        return

    if AppState.current_project.pages.values().size() == 1 \
            and selected.get_parent() == _tree_root:
        push_warning("PageDataHandler: Cannot delete the last remaining page.")
        return

    if AppState.has_active_page() \
            and AppState.current_page.page_id.value == page.page_id.value:
        AppState.current_page = ReactivePage.new()

    AppState.current_project.remove_page(page.page_id.value)


func rename_selected_page() -> void:
    var selected := page_tree.get_selected()
    if selected == null or selected == _tree_root:
        return
    selected.set_editable(0, true)
    page_tree.edit_selected()


func select_page(page_id: String) -> void:
    if not _item_map.has(page_id):
        return
    _item_map[page_id].select(0)
    var page := _item_map[page_id].get_metadata(0) as ReactivePage
    if page != null:
        AppState.focused_page.value = page

# ─────────────────────────────────────────────
# Intent Handlers
# ─────────────────────────────────────────────

func _on_add_page_requested(page_name: String) -> void:
    if not AppState.has_active_project():
        return

    var name = DEFAULT_PAGE_NAME
    var offset = 1
    if page_name == "":
        if AppState.current_project.find_page_name(name):
            while AppState.current_project.find_page_name(name):
                name = DEFAULT_PAGE_NAME + " " + str(offset)
                offset += 1

    var new_page   := ReactivePage.new(PageData.create(name))
    var focused    := AppState.focused_page.value as ReactivePage

    if focused != null:
        focused.add_child_page(new_page)
    else:
        AppState.current_project.add_page(new_page)


func _on_delete_page_requested(page_id: String) -> void:
    if not AppState.has_active_project():
        return

    if AppState.current_project.pages.values().size() == 1:
        push_warning("PageDataHandler: Cannot delete the last remaining page.")
        return

    var focused := AppState.focused_page.value as ReactivePage
    if focused != null and focused.page_id.value == page_id:
        AppState.focused_page.value = null

    AppState.current_project.remove_page(page_id)

# ─────────────────────────────────────────────
# Context Menu
# ─────────────────────────────────────────────

func _show_context_menu() -> void:
    var selected := page_tree.get_selected()
    var has_page := selected != null and selected != _tree_root

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

func _on_item_mouse_selected(_position: Vector2, mouse_button_index: int) -> void:
    match mouse_button_index:
        MOUSE_BUTTON_LEFT:
            var item := page_tree.get_selected()
            if item == null or item == _tree_root:
                return

            var page := item.get_metadata(0) as ReactivePage
            if page == null:
                return

            if AppState.focused_page != null \
                    and AppState.focused_page.value.page_id.value == page.page_id.value:
                return

            AppState.focused_page.value = page

        MOUSE_BUTTON_RIGHT:
            _show_context_menu()


## Called when selected_page.changed fires — meaning the selection was accepted.
## Syncs the visual tree highlight to match the confirmed selection.
func _on_focus_changed(page: ReactivePage) -> void:
    if page == null or page.page_id.value.is_empty():
        return

    _update_button_states()

    if not _item_map.has(page.page_id.value):
        return

    _item_map[page.page_id.value].select(0)


func _on_item_edited() -> void:
    var item := page_tree.get_selected()
    if item == null or item == _tree_root:
        return

    var page := item.get_metadata(0) as ReactivePage
    if page == null:
        return

    var new_name := item.get_text(0).strip_edges()

    if new_name.is_empty():
        item.set_text(0, page.page_name.value)
        return

    if new_name == page.page_name.value:
        return

    page.page_name.value = new_name
    item.set_editable(0, false)
    EventBus.page_renamed.emit(page.page_id.value, new_name)


func _update_button_states() -> void:
    var selected    := page_tree.get_selected()
    var has_page    := selected != null and selected != _tree_root
    btn_delete.disabled = not has_page

# ─────────────────────────────────────────────
# Drag and Drop
# ─────────────────────────────────────────────

func _get_drag_data(_position: Vector2) -> Variant:
    var selected := page_tree.get_selected()
    if selected == null or selected == _tree_root:
        return null

    var page := selected.get_metadata(0) as ReactivePage
    if page == null:
        return null

    var preview  := Label.new()
    preview.text  = page.page_name.value
    page_tree.set_drag_preview(preview)

    return { "page": page }


func _can_drop_data(position: Vector2, data: Variant) -> bool:
    page_tree.drop_mode_flags = Tree.DROP_MODE_ON_ITEM | Tree.DROP_MODE_INBETWEEN

    if not data is Dictionary or not data.has("page"):
        return false

    var dragged := data["page"] as ReactivePage
    if dragged == null:
        return false

    var target := page_tree.get_item_at_position(position)
    if target == null:
        return false

    if target == _tree_root:
        return true

    var target_page := target.get_metadata(0) as ReactivePage
    if target_page == null:
        return false

    if target_page.page_id.value == dragged.page_id.value:
        return false

    return not _is_descendant_of(target_page.page_id.value, dragged)


func _drop_data(position: Vector2, data: Variant) -> void:
    var dragged := data["page"] as ReactivePage
    if dragged == null:
        return

    var target_item := page_tree.get_item_at_position(position)
    if target_item == null:
        return

    if target_item == _tree_root:
        var page := AppState.current_project._detach_recursive(
            dragged.page_id.value,
            AppState.current_project.pages
        )
        if page != null:
            page.owner = null
            AppState.current_project.pages.append(page)
            EventBus.page_hierarchy_changed.emit()
        return

    var target_page := target_item.get_metadata(0) as ReactivePage
    if target_page == null:
        return

    var drop_mode := page_tree.get_drop_section_at_position(position)
    AppState.current_project.move_page(dragged.page_id.value, target_page, drop_mode)

# ─────────────────────────────────────────────
# EventBus Handlers
# ─────────────────────────────────────────────

func _on_project_opened(_project: ProjectData) -> void:
    _rebuild_tree()
    _select_first_page()


func _on_project_closed() -> void:
    page_tree.clear()
    _item_map.clear()
    _tree_root = page_tree.create_item()
    _tree_root.set_text(0, DEFAULT_ROOT_NAME)
    _tree_root.set_selectable(0, false)
    _update_button_states()

func _on_page_hierarchy_changed() -> void:
    var selected_id := _get_selected_page_id()
    _rebuild_tree()
    if selected_id != "":
        select_page(selected_id)

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

func _insert_relative(page: ReactivePage, target: ReactivePage, offset: int) -> void:
    var top_level: Array = AppState.current_project.pages.values()

    for i: int in top_level.size():
        var entry := top_level[i] as ReactivePage
        if entry != null and entry.page_id.value == target.page_id.value:
            AppState.current_project.pages.insert(i + offset, page)
            EventBus.page_created.emit(page.to_data())
            return

    for item: Variant in _iter_all_pages(AppState.current_project.pages):
        var entry := item as ReactivePage
        if entry == null:
            continue
        var children: Array = entry.children.values()
        for i: int in children.size():
            var child := children[i] as ReactivePage
            if child != null and child.page_id.value == target.page_id.value:
                entry.children.insert(i + offset, page)
                EventBus.page_created.emit(page.to_data())
                return


func _remove_item_recursive(item: TreeItem) -> void:
    for child in item.get_children():
        _remove_item_recursive(child)
    var page := item.get_metadata(0) as ReactivePage
    if page != null:
        _item_map.erase(page.page_id.value)
    item.free()


func _find_parent_item(page: ReactivePage) -> TreeItem:
    for page_id: String in _item_map:
        var candidate := _item_map[page_id].get_metadata(0) as ReactivePage
        if candidate != null and candidate.get_child_page(page.page_id.value) != null:
            return _item_map[page_id]
    return _tree_root


func _find_reactive_page(page_id: String) -> ReactivePage:
    return AppState.current_project.find_page(page_id)


func _is_descendant_of(candidate_id: String, root: ReactivePage) -> bool:
    for item: Variant in root.children.values():
        var child := item as ReactivePage
        if child == null:
            continue
        if child.page_id.value == candidate_id:
            return true
        if _is_descendant_of(candidate_id, child):
            return true
    return false


func _iter_all_pages(pages: ReactiveArray) -> Array:
    var result : Array = []
    var queue  : Array = pages.values().duplicate()
    while not queue.is_empty():
        var page := queue.pop_front() as ReactivePage
        if page == null:
            continue
        result.append(page)
        queue.append_array(page.children.values())
    return result


func _select_first_page() -> void:
    if not AppState.has_active_project():
        return
    var all := AppState.current_project.pages.values()
    if all.is_empty():
        return
    var first := all[0] as ReactivePage
    if first != null:
        AppState.focused_page.value = first


func _get_selected_page_id() -> String:
    var selected := page_tree.get_selected()
    if selected == null or selected == _tree_root:
        return ""
    var page := selected.get_metadata(0) as ReactivePage
    return page.page_id.value if page != null else ""


func _assert_active_project() -> bool:
    if not AppState.has_active_project():
        push_warning("PageDataHandler: No active project.")
        return false
    return true
