# scenes/page_panel/page_panel.gd
class_name PagePanel
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

var _tree_root : TreeItem   = null
var _page_icon : Texture2D  = null
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
        push_warning("PagePanel: Icon not found at '%s'." % PAGE_ICON_PATH)


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
        IntentBus.create_page_requested.emit("")
    )

    btn_delete.pressed.connect(func() -> void:
        var page := AppState.focused_page.value as ReactivePage
        if page == null or page.page_id.value.is_empty():
            return
        IntentBus.delete_page_requested.emit(page.page_id.value)
    )

    context_menu.id_pressed.connect(_on_context_menu_id_pressed)
    page_tree.item_mouse_selected.connect(_on_item_mouse_selected)
    page_tree.item_edited.connect(_on_item_edited)

    IntentBus.create_page_requested.connect(_on_create_page_requested)
    IntentBus.delete_page_requested.connect(_on_delete_page_requested)

    # React to project being loaded or cleared
    AppState.current_project.reactive_changed.connect(_on_current_project_changed)

    # React to confirmed page selection
    AppState.active_page.reactive_changed.connect(_on_active_page_changed)

# ─────────────────────────────────────────────
# Tree Building
# ─────────────────────────────────────────────

func _rebuild_tree() -> void:
    page_tree.clear()
    _item_map.clear()

    _tree_root = page_tree.create_item()
    _tree_root.set_text(0, _get_project_name())
    _tree_root.set_selectable(0, true)

    var project: ReactiveProject = AppState.current_project.value as ReactiveProject
    if project == null or project.project_name.value.is_empty():
        return

    for item: Variant in project.pages.values():
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
    var project: ReactiveProject = AppState.current_project.value
    if project == null:
        return DEFAULT_ROOT_NAME
    var name := project.project_name.value
    return name if not name.is_empty() else DEFAULT_ROOT_NAME

# ─────────────────────────────────────────────
# Intent Handlers
# ─────────────────────────────────────────────

func _on_create_page_requested(page_name: String) -> void:
    var project := AppState.current_project.value as ReactiveProject
    if project == null or project.project_name.value.is_empty():
        push_warning("PagePanel: No active project.")
        return

    # Resolve a unique name
    var resolved := page_name if not page_name.is_empty() else DEFAULT_PAGE_NAME
    var offset   := 1
    while project.find_page_name(resolved) != null:
        resolved = DEFAULT_PAGE_NAME + " " + str(offset)
        offset  += 1

    var new_page := ReactivePage.create(resolved)
    var focused  := AppState.focused_page.value as ReactivePage

    if focused != null and not focused.page_id.value.is_empty():
        focused.add_child_page(new_page)
    else:
        project.add_page(new_page)


func _on_delete_page_requested(page_id: String) -> void:
    var project := AppState.current_project
    if project == null or project.project_name.value.is_empty():
        push_warning("PagePanel: No active project.")
        return

    if project.pages.values().size() == 1:
        push_warning("PagePanel: Cannot delete the last remaining page.")
        return

    var focused := AppState.focused_page.value as ReactivePage
    if focused != null and focused.page_id.value == page_id:
        AppState.focused_page.value = null

    var active := AppState.active_page.value as ReactivePage
    if active != null and active.page_id.value == page_id:
        AppState.active_page.value = null

    project.remove_page(page_id)

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
        MenuAction.ADD_PAGE:
            IntentBus.create_page_requested.emit("")
        MenuAction.DELETE_PAGE:
            var selected := page_tree.get_selected()
            if selected == null or selected == _tree_root:
                return
            var page := selected.get_metadata(0) as ReactivePage
            if page != null:
                IntentBus.delete_page_requested.emit(page.page_id.value)

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

            if AppState.focused_page.value == page:
                return

            AppState.focused_page.value = page

        MOUSE_BUTTON_RIGHT:
            _show_context_menu()


func _on_active_page_changed(_reactive) -> void:
    _update_button_states()

    var page_id: String = AppState.active_page.value.page_id.value
    if page_id.is_empty() or not _item_map.has(page_id):
        return

    _item_map[page_id].select(0)


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
        item.set_editable(0, false)
        return

    if new_name == page.page_name.value:
        item.set_editable(0, false)
        return

    # Mutate reactive value directly — changed signal propagates automatically
    page.page_name.value = new_name
    item.set_editable(0, false)


func _update_button_states() -> void:
    var selected    := page_tree.get_selected()
    var has_page    := selected != null and selected != _tree_root
    btn_delete.disabled = not has_page

# ─────────────────────────────────────────────
# AppState Handlers
# ─────────────────────────────────────────────

## Fires when the active project is replaced or cleared.
func _on_current_project_changed(_reactive) -> void:
    var project := AppState.current_project.value as ReactiveProject
    var is_open := project != null and not project.project_name.value.is_empty()

    if is_open:
        if project.pages.reactive_changed.is_connected(_on_page_hierarchy_changed):
            project.pages.reactive_changed.disconnect(_on_page_hierarchy_changed)
        project.pages.reactive_changed.connect(_on_page_hierarchy_changed)

        _rebuild_tree()
        _select_first_page()
    else:
        page_tree.clear()
        _item_map.clear()
        _tree_root = page_tree.create_item()
        _tree_root.set_text(0, DEFAULT_ROOT_NAME)
        _tree_root.set_selectable(0, false)
        _update_button_states()


## Fires when the page hierarchy is structurally modified.
func _on_page_hierarchy_changed(_reactive) -> void:
    var selected_id := _get_selected_page_id()
    _rebuild_tree()
    if not selected_id.is_empty():
        _select_page_by_id(selected_id)

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
        # Move to top level — detach and re-append to project root
        var page: ReactivePage = AppState.current_project.value._detach_recursive(
            dragged.page_id.value,
            AppState.current_project.value.pages
        )
        if page != null:
            page.owner = null
            AppState.current_project.value.pages.append(page)
        return

    var target_page := target_item.get_metadata(0) as ReactivePage
    if target_page == null:
        return

    var drop_mode := page_tree.get_drop_section_at_position(position)
    AppState.current_project.value.move_page(dragged.page_id.value, target_page, drop_mode)

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

func _select_first_page() -> void:
    var project: ReactiveProject = AppState.current_project.value
    if project == null:
        return
    var all := project.pages.values()
    if all.is_empty():
        return
    var first := all[0] as ReactivePage
    if first == null:
        return
    AppState.focused_page.value = first
    AppState.active_page.value  = first


func _select_page_by_id(page_id: String) -> void:
    if not _item_map.has(page_id):
        return
    _item_map[page_id].select(0)


func _get_selected_page_id() -> String:
    var selected := page_tree.get_selected()
    if selected == null or selected == _tree_root:
        return ""
    var page := selected.get_metadata(0) as ReactivePage
    return page.page_id.value if page != null else ""


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
