# WidgetCanvas.gd
class_name WidgetCanvas
extends Panel

var _context_target : Node      = null
var _context_menu   : PopupMenu = null
var _page_id        : String    = ""

# ── Context Menu Item IDs ─────────────────────────────────────────────────────

const MENU_ADD_CHILD       :int = 0
const MENU_EDIT_PROPERTIES :int = 1
const MENU_DELETE          :int = 2

const MENU_SERVER_CONNECT_ALL : int = 1000
const MENU_SERVER_DISCONNECT_ALL : int = 1001

# ─────────────────────────────────────────────
# Reactive Data
# ─────────────────────────────────────────────

## The reactive data object backing this widget instance.
var data: ReactiveCanvas = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    add_to_group("widget_host")
    mouse_filter = Control.MOUSE_FILTER_STOP
    _build_context_menu()

    IntentBus.add_widget_requested.connect(_on_add_widget_requested)
    IntentBus.delete_widget_requested.connect(_on_delete_widget_requested)

    AppState.edit_mode.connect_self_changed(_on_edit_mode_changed)

    for widget: ReactiveWidget in data.widgets.value:
        _restore_node(self, widget)

## Instantiates and initialises a single widget from its backing ReactiveWidget,
## then recurses into container children.
func _restore_node(parent: Control, reactive_widget: ReactiveWidget) -> void:
    var type: String = reactive_widget.widget_type.value

    if not ProjectManager.NODE_REGISTRY.has(type):
        push_error("ProjectManager: Unknown node type '%s'." % type)
        return

    var packed: PackedScene = ProjectManager.NODE_REGISTRY[type] as PackedScene
    if packed == null:
        push_error("ProjectManager: Failed to load scene for '%s'." % type)
        return

    var instance: Node = packed.instantiate()
    if not instance is BaseWidget:
        push_error("ProjectManager: Scene is not a BaseWidget for type '%s'." % type)
        instance.queue_free()
        return

    var widget: BaseWidget = instance as BaseWidget

    # Initialise from backing data BEFORE entering the tree, so _ready()
    # (triggered by add_child) can safely rely on `data` being set.
    widget.init(reactive_widget)

    parent.add_child(widget)

    if parent is BaseWidget and (parent as BaseWidget).is_container:
        (parent as BaseWidget)._elevate_child(widget)

    if not widget.is_container:
        return

    var drop_target: Control = widget.get_drop_target()
    if drop_target == null:
        return

    for child_widget: ReactiveWidget in reactive_widget.children.value:
        _restore_node(drop_target, child_widget)

# ── Guards ────────────────────────────────────────────────────────────────────

func _is_active_canvas() -> bool:
    var active: ReactivePage = AppState.active_page.value as ReactivePage
    return active != null and active.page_id.value == _page_id


func _get_reactive_page() -> ReactivePage:
    return AppState.current_project.find_page_id(_page_id)

# ── Dirty State ───────────────────────────────────────────────────────────────

# TODO: replace with reactive changed event
func _mark_dirty() -> void:
    var page: ReactivePage = _get_reactive_page()
    if page != null:
        page.canvas.is_dirty.value = true


func _clear_dirty() -> void:
    var page: ReactivePage = _get_reactive_page()
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
        _context_menu.add_item("Delete",           MENU_DELETE)

    elif target is BaseWidget:
        _context_menu.add_item("Edit Properties",  MENU_EDIT_PROPERTIES)
        _context_menu.add_item("Delete",           MENU_DELETE)

    else:
        # Right-clicked the canvas background — offer add via palette
        _context_menu.add_item("Add Widget",       MENU_ADD_CHILD)
        _context_menu.add_separator()
        
        # 1. Create the Server Submenu
        var server_menu : PopupMenu = PopupMenu.new()
        server_menu.name = "ServerSubMenu"
        
        # 2. Populate the Server Submenu with unique IDs
        server_menu.add_item("Connect all", MENU_SERVER_CONNECT_ALL)
        server_menu.add_item("Disconnect all", MENU_SERVER_DISCONNECT_ALL)
        
        # 3. Connect the signal to your handling function
        #server_menu.id_pressed.connect(_on_server_menu_id_pressed)
        
        # 4. Bind it to the parent so it frees automatically on _context_menu.clear()
        _context_menu.add_child(server_menu)
        
        # 5. Add it as a submenu item in the main context menu
        _context_menu.add_submenu_node_item("Server", server_menu)

    _context_menu.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i.ZERO))


func _on_context_menu_id_pressed(id: int) -> void:
    match id:
        MENU_ADD_CHILD:
            _select_target(_context_target)
            IntentBus.show_widget_palette_requested.emit()

        MENU_EDIT_PROPERTIES:
            _select_target(_context_target)

        MENU_DELETE:
            if _context_target is BaseWidget:
                IntentBus.delete_widget_requested.emit(
                    (_context_target as BaseWidget).data.widget_id.value
                )

# ── Input ─────────────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
    if not AppState.edit_mode.value:
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
    if not AppState.edit_mode.value:
        return
    if event is InputEventMouseButton \
            and event.button_index == MOUSE_BUTTON_RIGHT \
            and event.pressed:
        _context_target = target
        _show_context_menu_for(target)
        get_viewport().set_input_as_handled()

# ── Selection ─────────────────────────────────────────────────────────────────

func _deselect_current() -> void:
    var current: ReactiveWidget = AppState.selected_widget.value as ReactiveWidget
    if current == null:
        return
    get_widget_node(current).deselect()
    AppState.selected_widget.value = null

#TODO: Update this to be more efficient!
func get_widget_node(w: ReactiveWidget) -> BaseWidget:
    return _find_widget(get_tree().root, w)

func _find_widget(node: Node, widget_id: ReactiveWidget) -> BaseWidget:
    if node is BaseWidget and node.data == widget_id:
        return node
    for child: Node in node.get_children():
        var found: BaseWidget = _find_widget(child, widget_id)
        if found != null:
            return found
    return null

func _select_target(target: Node) -> void:
    if target == null or not target is BaseWidget:
        return

    var widget: BaseWidget = target as BaseWidget

    if AppState.selected_widget.value == widget.data:
        return

    _deselect_current()          # ← deselects previous widget
    widget.select()              # ← canvas instructs new widget to select itself
    AppState.selected_widget.value = widget.data  # ← state updated


func _on_widget_selection_requested(widget: SelectableControl) -> void:
    _select_target(widget)

# ── Edit Mode ─────────────────────────────────────────────────────────────────

func _on_edit_mode_changed(edit_mode: ReactiveBool) -> void:
    if not edit_mode.value:
        _deselect_current()

# ── Widget Spawning ───────────────────────────────────────────────────────────

func spawn_widget(scene: PackedScene) -> void:
    var instance: Node = scene.instantiate()

    if not instance is BaseWidget:
        push_error("WidgetCanvas: Spawned scene is not a BaseWidget: %s" % scene.resource_path)
        instance.queue_free()
        return

    var widget: BaseWidget = instance as BaseWidget

    # Build the backing ReactiveWidget now that get_widget_class() is available
    var reactive_widget: ReactiveWidget = ReactiveWidget.create(widget.get_widget_class(), widget.widget_label, null, data.widgets)
    reactive_widget.z_index.value = widget.z_index
    data.widgets.append(reactive_widget)

    # Initialise the scene node from its backing data (applies default properties)
    widget.init(reactive_widget)

    # Resolve placement and attach to the scene tree
    var parent: Control = _resolve_parent_for_placement(get_global_mouse_position())
    parent.add_child(widget)

    var parent_widget: BaseWidget = parent as BaseWidget
    if parent_widget != null and parent_widget.is_container:
        parent_widget._elevate_child(widget)

    # Centre the widget under the spawn point, using its own default size
    var centered_position: Vector2 = parent.size / 2.0 - widget.size / 2.0
    reactive_widget.properties.value["position"].value = centered_position

    _subscribe_widget(widget)

    # Wait a frame so layout/containers have settled before syncing the node's transform
    await get_tree().process_frame
    widget.position = centered_position

    _mark_dirty()

# ── Parent Resolution ─────────────────────────────────────────────────────────

func _resolve_parent_for_placement(drop_position: Vector2) -> Control:
    var best: Control = _find_deepest_drop_target(self, drop_position)
    return best if best != null else self


func _find_deepest_drop_target(root: Control, drop_position: Vector2) -> Control:
    var best: Control = null

    for child: Node in root.get_children():
        if not child is BaseWidget:
            continue

        var widget     : BaseWidget = child as BaseWidget
        var drop_target: Control = widget.get_drop_target()

        if drop_target == null:
            continue
        if not drop_target.get_global_rect().has_point(drop_position):
            continue

        var deeper: Control = _find_deepest_drop_target(drop_target, drop_position)
        best = deeper if deeper != null else drop_target

    return best

# ── Signal Subscription ───────────────────────────────────────────────────────

func _subscribe_widget(widget: BaseWidget) -> void:
    if not widget.selection_requested.is_connected(_on_widget_selection_requested):
        widget.selection_requested.connect(_on_widget_selection_requested)
    if not widget.gui_input.is_connected(_on_child_gui_input.bind(widget)):
        widget.gui_input.connect(_on_child_gui_input.bind(widget))


func _subscribe_all_recursive(root: Control) -> void:
    for child: Node in root.get_children():
        if not child is BaseWidget:
            continue
        var widget: BaseWidget = child as BaseWidget
        _subscribe_widget(widget)
        var drop_target: Control = widget.get_drop_target()
        if drop_target != null:
            _subscribe_all_recursive(drop_target)

# ── Node Access ───────────────────────────────────────────────────────────────

func get_all_nodes_recursive() -> Array[Node]:
    var result: Array[Node] = []
    _collect_nodes_recursive(self, result)
    return result


func _collect_nodes_recursive(root: Control, result: Array[Node]) -> void:
    for child: Node in root.get_children():
        if not child is BaseWidget:
            continue
        var widget: BaseWidget = child as BaseWidget
        result.append(widget)
        var drop_target: Control = widget.get_drop_target()
        if drop_target != null:
            _collect_nodes_recursive(drop_target, result)

# ── Canvas Operations ─────────────────────────────────────────────────────────

func clear_all_widgets() -> void:
    _deselect_current()
    _context_target = null
    for child: Node in get_children():
        if child is BaseWidget:
            child.queue_free()

# ── Page Loading ──────────────────────────────────────────────────────────────

## Assigns this canvas to a page and restores its widget subscriptions.
## Widget scene instantiation is handled by ProjectManager._restore_canvas().
## This method is called after ProjectManager has already populated the
## scene tree — it wires up signals and records the page association.
func load_page(page: ReactivePage) -> void:
    _page_id = page.page_id.value
    _subscribe_all_recursive(self)
    _clear_dirty()

# ── IntentBus Handlers ────────────────────────────────────────────────────────

func _on_add_widget_requested(scene: PackedScene) -> void:
    _deselect_current()
    if not _is_active_canvas():
        return
    spawn_widget(scene)


func _on_delete_widget_requested(widget_id: String) -> void:
    if not _is_active_canvas():
        return
    for node: Node in get_all_nodes_recursive():
        if node is BaseWidget and (node as BaseWidget).data != null \
                and (node as BaseWidget).data.widget_id.value == widget_id:
            _delete_widget(node as BaseWidget)
            return
    push_warning("WidgetCanvas: widget_id '%s' not found for deletion." % widget_id)


func _delete_widget(target: BaseWidget) -> void:
    if AppState.selected_widget.value == target:
        _deselect_current()
    _context_target = null
    target.queue_free()
    AppState.selected_widget.value = null
    _mark_dirty()
