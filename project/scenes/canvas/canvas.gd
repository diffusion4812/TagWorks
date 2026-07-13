# WidgetCanvas.gd
class_name WidgetCanvas
extends Control

@onready var widget_palette:     WidgetPalette = get_tree().root.find_child("WidgetPalette", true, false)
@onready var property_panel:     PropertyPanel = get_tree().root.find_child("PropertyPanel", true, false)

var _context_target: Node      = null
var _context_menu:   PopupMenu = null
var _page_id:        String    = ""

# ── Context Menu Item IDs ─────────────────────────────────────────────────────

const MENU_ADD_CHILD       := 0
const MENU_EDIT_PROPERTIES := 1
const MENU_DELETE          := 2

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    _build_context_menu()

    IntentBus.add_widget_requested.connect(_on_add_widget_requested)
    IntentBus.delete_widget_requested.connect(_on_delete_widget_requested)

    AppState.is_edit_mode.reactive_changed.connect(_on_edit_mode_changed)

# ── Guards ────────────────────────────────────────────────────────────────────

func _is_active_canvas() -> bool:
    var active := AppState.active_page.value as ReactivePage
    return active != null and active.page_id.value == _page_id


func _get_reactive_page() -> ReactivePage:
    return AppState.current_project.find_page_id(_page_id)

# ── Dirty State ───────────────────────────────────────────────────────────────

func _mark_dirty() -> void:
    var page := _get_reactive_page()
    if page != null:
        page.canvas.is_dirty.value = true


func _clear_dirty() -> void:
    var page := _get_reactive_page()
    if page != null:
        page.canvas.is_dirty.value = false

# ── Context Menu ──────────────────────────────────────────────────────────────

func _build_context_menu() -> void:
    _context_menu      = PopupMenu.new()
    _context_menu.name = "WidgetCanvasContextMenu"
    add_child(_context_menu)
    _context_menu.id_pressed.connect(_on_context_menu_id_pressed)


func _show_context_menu_for(target: Node) -> void:
    _context_menu.clear()

    if target is BaseWidget and (target as BaseWidget).is_container:
        _context_menu.add_item("Add Child Widget", MENU_ADD_CHILD)
        _context_menu.add_separator()
        _context_menu.add_item("Edit Properties",  MENU_EDIT_PROPERTIES)
        if target != self:
            _context_menu.add_item("Delete",       MENU_DELETE)

    elif target is BaseWidget:
        _context_menu.add_item("Edit Properties",  MENU_EDIT_PROPERTIES)
        _context_menu.add_item("Delete",           MENU_DELETE)

    _context_menu.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i.ZERO))


func _on_context_menu_id_pressed(id: int) -> void:
    match id:
        MENU_ADD_CHILD:
            if _context_target != null:
                _select_target(_context_target)
            widget_palette.show()

        MENU_EDIT_PROPERTIES:
            if _context_target != null:
                _select_target(_context_target)
            property_panel.show()

        MENU_DELETE:
            if _context_target is BaseWidget:
                IntentBus.delete_widget_requested.emit(
                    (_context_target as BaseWidget).widget_id
                )

# ── Input ─────────────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
    if not AppState.is_edit_mode.value:
        return

    if event is InputEventMouseButton and event.pressed:
        match event.button_index:
            MOUSE_BUTTON_LEFT:
                _deselect_current()
                get_viewport().set_input_as_handled()

            MOUSE_BUTTON_RIGHT:
                _context_target = self
                _show_context_menu_for(self)
                get_viewport().set_input_as_handled()


func _on_child_gui_input(event: InputEvent, target: Node) -> void:
    if not AppState.is_edit_mode.value:
        return
    if event is InputEventMouseButton \
            and event.button_index == MOUSE_BUTTON_RIGHT \
            and event.pressed:
        _context_target = target
        _show_context_menu_for(target)
        get_viewport().set_input_as_handled()

# ── Selection ─────────────────────────────────────────────────────────────────

func _deselect_current() -> void:
    var current := AppState.current_project.canvas.selected_widget.value as BaseWidget
    if current == null:
        return
    current.deselect()
    AppState.current_project.canvas.selected_widget.value = null


func _select_target(target: Node) -> void:
    if AppState.current_project.canvas.selected_widget.value as BaseWidget == target:
        return

    _deselect_current()

    if target is BaseWidget:
        var widget := target as BaseWidget
        widget.select()
        AppState.selected_widget.value = widget


func _on_widget_selected(widget: SelectableControl) -> void:
    _select_target(widget)

# ── Edit Mode ─────────────────────────────────────────────────────────────────

func _on_edit_mode_changed(_reactive: ReactiveVariant) -> void:
    if not AppState.is_edit_mode.value:
        _deselect_current()

# ── Widget Spawning ───────────────────────────────────────────────────────────

func spawn_widget(scene: PackedScene) -> void:
    var instance := scene.instantiate()

    if not instance is BaseWidget:
        push_error("WidgetCanvas: Spawned scene is not a BaseWidget: %s" % scene.resource_path)
        instance.queue_free()
        return

    var widget := instance as BaseWidget
    var parent := _resolve_parent_for_placement(get_global_mouse_position())
    parent.add_child(widget)

    var parent_widget := parent as BaseWidget
    if parent_widget != null and parent_widget.is_container:
        parent_widget._elevate_child(widget)

    _subscribe_widget(widget)

    await get_tree().process_frame

    widget.position     = parent.size / 2.0 - widget.size / 2.0
    _mark_dirty()

# ── Parent Resolution ─────────────────────────────────────────────────────────

func _resolve_parent_for_placement(drop_position: Vector2) -> Control:
    var best := _find_deepest_drop_target(self, drop_position)
    return best if best != null else self


func _find_deepest_drop_target(root: Control, drop_position: Vector2) -> Control:
    var best: Control = null

    for child in root.get_children():
        if not child is BaseWidget:
            continue

        var widget      := child as BaseWidget
        var drop_target := widget.get_drop_target()

        if drop_target == null:
            continue
        if not drop_target.get_global_rect().has_point(drop_position):
            continue

        var deeper := _find_deepest_drop_target(drop_target, drop_position)
        best = deeper if deeper != null else drop_target

    return best

# ── Signal Subscription ───────────────────────────────────────────────────────

func _subscribe_widget(widget: BaseWidget) -> void:
    widget._root_canvas = self

    if not widget.selected.is_connected(_on_widget_selected):
        widget.selected.connect(_on_widget_selected)
    if not widget.gui_input.is_connected(_on_child_gui_input.bind(widget)):
        widget.gui_input.connect(_on_child_gui_input.bind(widget))


func _subscribe_all_recursive(root: Control) -> void:
    for child in root.get_children():
        if not child is BaseWidget:
            continue
        var widget := child as BaseWidget
        _subscribe_widget(widget)
        var drop_target := widget.get_drop_target()
        if drop_target != null:
            _subscribe_all_recursive(drop_target)

# ── Node Access ───────────────────────────────────────────────────────────────

func get_all_nodes_recursive() -> Array[Node]:
    var result: Array[Node] = []
    _collect_nodes_recursive(self, result)
    return result


func _collect_nodes_recursive(root: Control, result: Array[Node]) -> void:
    for child in root.get_children():
        if not child is BaseWidget:
            continue
        var widget := child as BaseWidget
        result.append(widget)
        var drop_target := widget.get_drop_target()
        if drop_target != null:
            _collect_nodes_recursive(drop_target, result)

# ── Canvas Operations ─────────────────────────────────────────────────────────

func clear_all_widgets() -> void:
    _deselect_current()
    _context_target = null
    for child in get_children():
        if child is BaseWidget:
            child.queue_free()

# ── Page Loading ──────────────────────────────────────────────────────────────

func load_page(page: ReactivePage) -> void:
    _page_id = page.page_id.value
    clear_all_widgets()
    _load_canvas_state(page.canvas.to_data())
    _clear_dirty()


func _load_canvas_state(canvas_state: Dictionary) -> void:
    if canvas_state.is_empty():
        return

    var children: Array = canvas_state.get("children", canvas_state.get("widgets", []))

    for child_data: Dictionary in children:
        var scene := load(child_data.get("scene", "")) as PackedScene
        if scene == null:
            push_error("WidgetCanvas: Failed to load scene: %s" % child_data.get("scene", ""))
            continue

        var instance := scene.instantiate()
        if not instance is BaseWidget:
            push_error("WidgetCanvas: Not a BaseWidget: %s" % child_data.get("scene", ""))
            instance.queue_free()
            continue

        add_child(instance)
        (instance as BaseWidget).deserialize(child_data)

    _subscribe_all_recursive(self)

# ── Serialisation ─────────────────────────────────────────────────────────────

func serialize() -> Dictionary:
    var serialised_children: Array = []
    for child in get_children():
        if child is BaseWidget:
            serialised_children.append((child as BaseWidget).serialize())
    return { "children": serialised_children }

# ── IntentBus Handlers ────────────────────────────────────────────────────────

func _on_add_widget_requested(scene: PackedScene) -> void:
    if not _is_active_canvas():
        return
    spawn_widget(scene)


func _on_delete_widget_requested(widget_id: String) -> void:
    if not _is_active_canvas():
        return
    for node in get_all_nodes_recursive():
        if node is BaseWidget and (node as BaseWidget).widget_id == widget_id:
            _delete_widget(node)
            return
    push_warning("WidgetCanvas: widget_id '%s' not found for deletion." % widget_id)


func _delete_widget(target: BaseWidget) -> void:
    if AppState.current_project.canvas.selected_widget.value as BaseWidget == target:
        _deselect_current()
    _context_target = null
    target.queue_free()
    _mark_dirty()
