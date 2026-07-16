# WidgetCanvas.gd
class_name WidgetCanvas
extends Control

var _context_target : Node      = null
var _context_menu   : PopupMenu = null
var _page_id        : String    = ""

# ── Context Menu Item IDs ─────────────────────────────────────────────────────

const MENU_ADD_CHILD       :int = 0
const MENU_EDIT_PROPERTIES :int = 1
const MENU_DELETE          :int = 2

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

    AppState.edit_mode.reactive_changed.connect(_on_edit_mode_changed)

    for widget: ReactiveWidget in data.widgets.value:
        _restore_node(self, widget)

## Instantiates and deserialises a single widget from a serialised Dictionary,
## then recurses into container children.
func _restore_node(parent: Control, reactive_widget: ReactiveWidget) -> void:
    var type: String = reactive_widget.widget_type.value

    if not ProjectManager.NODE_REGISTRY.has(type):
        push_error("ProjectManager: Unknown node type '%s'." % type)
        return

    var packed: PackedScene = load(ProjectManager.NODE_REGISTRY[type]) as PackedScene
    if packed == null:
        push_error("ProjectManager: Failed to load scene for '%s'." % type)
        return

    var instance: Node = packed.instantiate()
    if not instance is BaseWidget:
        push_error("ProjectManager: Scene is not a BaseWidget for type '%s'." % type)
        instance.queue_free()
        return

    parent.add_child(instance)

    var widget: BaseWidget = instance as BaseWidget

    if parent is BaseWidget and (parent as BaseWidget).is_container:
        (parent as BaseWidget)._elevate_child(widget)

    widget.init(reactive_widget)

    if widget.is_container:
        var drop_target: Control = widget.get_drop_target()
        if drop_target != null:
            for child_data: Variant in reactive_widget.value.children:
                if child_data is Dictionary:
                    _restore_node(drop_target, child_data)

# ── Guards ────────────────────────────────────────────────────────────────────

func _is_active_canvas() -> bool:
    var active: ReactivePage = AppState.active_page.value as ReactivePage
    return active != null and active.page_id.value == _page_id


func _get_reactive_page() -> ReactivePage:
    return AppState.current_project.value.find_page_id(_page_id)

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
        # Right-clicked the canvas background — only offer add via palette
        _context_menu.add_item("Add Widget",       MENU_ADD_CHILD)

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
    var current: BaseWidget = AppState.selected_widget.value as BaseWidget
    if current == null:
        return
    current.deselect()
    AppState.selected_widget.value = null


func _select_target(target: Node) -> void:
    if target == null or not target is BaseWidget:
        return

    var widget: BaseWidget = target as BaseWidget

    if AppState.selected_widget.value == widget:
        return

    _deselect_current()          # ← deselects previous widget
    widget.select()              # ← canvas instructs new widget to select itself
    AppState.selected_widget.value = widget  # ← state updated


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

    # Resolve parent first so initial position and size can be set correctly
    var parent: Control = _resolve_parent_for_placement(get_global_mouse_position())
    parent.add_child(widget)

    var parent_widget: BaseWidget = parent as BaseWidget
    if parent_widget != null and parent_widget.is_container:
        parent_widget._elevate_child(widget)

    # Build the backing ReactiveWidget now that get_widget_class() is available
    var reactive_widget: ReactiveWidget = ReactiveWidget.create(widget.get_widget_class(), widget.widget_label)
    reactive_widget.position.value = parent.size / 2.0 - widget.size / 2.0
    reactive_widget.size.value     = widget.size
    reactive_widget.z_index.value  = widget.z_index

    # Register in the reactive page canvas
    data.widgets.append(reactive_widget)

    # Initialise the scene node from its backing data
    widget.init(reactive_widget)

    _subscribe_widget(widget)

    await get_tree().process_frame

    widget.position = parent.size / 2.0 - widget.size / 2.0
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
    _mark_dirty()
