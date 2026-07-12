# scenes/canvas/canvas.gd
class_name WidgetCanvas
extends Control

@onready var add_widget_button:  Button        = %AddWidgetButton
@onready var edit_widget_button: Button        = %EditWidgetButton
@onready var widget_palette:     WidgetPalette = get_tree().root.find_child("WidgetPalette", true, false)
@onready var property_panel:     PropertyPanel = get_tree().root.find_child("PropertyPanel", true, false)

var _selected_target: Node = null
var _context_target:  Node = null
var _context_menu:    PopupMenu
var is_edit_mode:     bool = false

## True when the canvas has unsaved changes since the last save or page load.
var is_dirty: ReactiveBool = ReactiveBool.new(false, null, "is_dirty")

## Minimum overlap area in pixels² required to trigger proximity reparenting.
const REPARENT_OVERLAP_THRESHOLD := 400.0

# ── Context Menu Item IDs ─────────────────────────────────────────────────────

const MENU_ADD_CHILD       := 0
const MENU_EDIT_PROPERTIES := 1
const MENU_DELETE          := 2

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    add_widget_button.pressed.connect(_on_add_widget_pressed)
    edit_widget_button.pressed.connect(_on_edit_widget_pressed)
    _set_toolbar_visible(is_edit_mode)
    _build_context_menu()

    # ── IntentBus ─────────────────────────────────────────────────────────────
    IntentBus.add_widget_requested.connect(_on_add_widget_requested)
    IntentBus.deselect_widget_requested.connect(_on_deselect_widget_requested)
    IntentBus.delete_widget_requested.connect(_on_delete_widget_requested)

    # ── EventBus ──────────────────────────────────────────────────────────────
    EventBus.edit_mode_changed.connect(_on_edit_mode_changed)
    EventBus.widget_deselected.connect(_on_widget_deselected_event)
    EventBus.project_saved.connect(_on_project_saved)

func _on_project_saved(_path: String) -> void:
    _clear_dirty()

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

    var screen_pos: Vector2i = DisplayServer.mouse_get_position()
    _context_menu.popup(Rect2i(screen_pos, Vector2i.ZERO))


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
            if _context_target != null and _context_target is BaseWidget:
                IntentBus.delete_widget_requested.emit(
                    (_context_target as BaseWidget).widget_id
                )

func _delete_target(target: Node) -> void:
    if target == null:
        return
    if _selected_target == target:
        _deselect_current()
        IntentBus.deselect_widget_requested.emit()
    target.queue_free()
    _context_target = null
    _mark_dirty()

# ── Input ─────────────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
    if not is_edit_mode:
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
    widget.is_edit_mode = true
    _mark_dirty()
    EventBus.widget_added.emit(widget)

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

# ── Proximity Reparenting ─────────────────────────────────────────────────────

func _on_widget_drag_ended(widget: SelectableControl) -> void:
    var base_widget := widget as BaseWidget
    if base_widget == null or base_widget.is_container:
        return

    var best_container := _find_best_container(base_widget)
    if best_container == null:
        return

    if base_widget.get_parent() == best_container:
        return

    _reparent_widget(base_widget, best_container, base_widget.position)


func _on_widget_drag_moved(widget: SelectableControl) -> void:
    var base_widget := widget as BaseWidget
    if base_widget == null:
        return

    var best := _find_best_container(base_widget)
    _highlight_container(best)


func _find_best_container(widget: BaseWidget) -> Control:
    var widget_rect  := widget.get_global_rect()
    var best_target:  Control = null
    var best_overlap: float   = REPARENT_OVERLAP_THRESHOLD

    _check_containers_recursive(self, widget, widget_rect, best_target, best_overlap)
    return best_target


func _check_containers_recursive(
    root:         Control,
    widget:       BaseWidget,
    widget_rect:  Rect2,
    best_target:  Control,
    best_overlap: float
) -> void:
    for child in root.get_children():
        if not child is BaseWidget:
            continue

        var candidate := child as BaseWidget
        if not candidate.is_container:
            continue
        if candidate == widget:
            continue

        var drop_target := candidate.get_drop_target()
        if drop_target == null:
            continue

        if candidate._is_ancestor_of(widget):
            continue

        var overlap := widget_rect.intersection(drop_target.get_global_rect())
        var area    := overlap.size.x * overlap.size.y

        if area > best_overlap:
            best_overlap = area
            best_target  = drop_target

        _check_containers_recursive(drop_target, widget, widget_rect, best_target, best_overlap)


func _highlight_container(target: Control) -> void:
    for child in get_children():
        if child is BaseWidget and (child as BaseWidget).is_container:
            child.modulate = Color.WHITE

    if is_instance_valid(target):
        target.modulate = Color(0.8, 1.0, 0.8)


func _reparent_widget(widget: BaseWidget, new_parent: Control, _drop_position: Vector2) -> void:
    var old_parent := widget.get_parent()
    if old_parent == new_parent:
        return

    var global_pos := widget.global_position

    old_parent.remove_child(widget)
    new_parent.add_child(widget)

    var new_parent_widget := new_parent as BaseWidget
    if new_parent_widget != null and new_parent_widget.is_container:
        new_parent_widget._elevate_child(widget)

    _subscribe_widget(widget)

    await get_tree().process_frame

    widget.global_position = global_pos
    widget.is_edit_mode    = true
    _mark_dirty()

# ── Signal Subscription ───────────────────────────────────────────────────────

func _subscribe_widget(widget: BaseWidget) -> void:
    widget._root_canvas = self

    if not widget.selected.is_connected(_on_widget_selected):
        widget.selected.connect(_on_widget_selected)
    if not widget.deselected.is_connected(_on_widget_deselected):
        widget.deselected.connect(_on_widget_deselected)
    if not widget.gui_input.is_connected(_on_child_gui_input.bind(widget)):
        widget.gui_input.connect(_on_child_gui_input.bind(widget))
    if not widget.drag_ended.is_connected(_on_widget_drag_ended):
        widget.drag_ended.connect(_on_widget_drag_ended)
    if not widget.drag_moved.is_connected(_on_widget_drag_moved):
        widget.drag_moved.connect(_on_widget_drag_moved)


func _subscribe_all_recursive(root: Control) -> void:
    for child in root.get_children():
        if not child is BaseWidget:
            continue
        var widget := child as BaseWidget
        _subscribe_widget(widget)
        var drop_target := widget.get_drop_target()
        if drop_target != null:
            _subscribe_all_recursive(drop_target)


func _on_child_gui_input(event: InputEvent, target: Node) -> void:
    if not is_edit_mode:
        return
    if event is InputEventMouseButton \
            and event.button_index == MOUSE_BUTTON_RIGHT \
            and event.pressed:
        _context_target = target
        _show_context_menu_for(target)
        get_viewport().set_input_as_handled()

# ── Edit Mode ─────────────────────────────────────────────────────────────────

func _on_edit_mode_changed(enabled: bool) -> void:
    is_edit_mode = enabled
    _set_toolbar_visible(enabled)
    set_all_edit_mode(enabled)
    if not enabled:
        _deselect_current()


func set_all_edit_mode(enabled: bool) -> void:
    for child in get_children():
        if child is BaseWidget:
            (child as BaseWidget).is_edit_mode = enabled


func _set_toolbar_visible(enabled: bool) -> void:
    add_widget_button.visible  = enabled
    edit_widget_button.visible = enabled


func _on_add_widget_pressed() -> void:
    widget_palette.show()


func _on_edit_widget_pressed() -> void:
    property_panel.show()

func _mark_dirty() -> void:
    if not is_dirty:
        is_dirty.value = true

func _clear_dirty() -> void:
    if is_dirty:
        is_dirty.value = false

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
    _selected_target = null
    _context_target  = null
    for child in get_children():
        if child is BaseWidget:
            child.queue_free()

# ── Page Loading ──────────────────────────────────────────────────────────────

## Clears the canvas and restores widget layout from the given page.
## Called only on project open — bypasses the dirty check entirely.
func load_page(page: PageData) -> void:
    clear_all_widgets()
    _load_canvas_state(page.canvas)
    _clear_dirty()


func _load_canvas_state(canvas_state: Dictionary) -> void:
    if canvas_state.is_empty():
        return

    var children: Array = canvas_state.get("children", [])
    if children.is_empty():
        children = canvas_state.get("widgets", [])

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
        _subscribe_widget(instance as BaseWidget)
        (instance as BaseWidget).deserialize(child_data)

    _subscribe_all_recursive(self)
    set_all_edit_mode(is_edit_mode)

# ── Serialisation ─────────────────────────────────────────────────────────────

func serialize() -> Dictionary:
    var serialised_children: Array = []
    for child in get_children():
        if child is BaseWidget:
            serialised_children.append((child as BaseWidget).serialize())
    return {
        "children": serialised_children
    }

# ── Selection ─────────────────────────────────────────────────────────────────

func _deselect_current() -> void:
    if _selected_target == null:
        return
    if _selected_target is BaseWidget:
        (_selected_target as BaseWidget).deselect()
    _selected_target = null


func _select_target(target: Node) -> void:
    if _selected_target == target:
        return

    _deselect_current()
    _selected_target            = target
    edit_widget_button.disabled = (target == self)

    if target is BaseWidget:
        IntentBus.select_widget_requested.emit(target as BaseWidget)

# ── IntentBus Handlers ────────────────────────────────────────────────────────

func _on_add_widget_requested(scene: PackedScene) -> void:
    var parent := _find_parent_canvas(_selected_target)
    if parent == null:
        push_warning("WidgetCanvas: No parent canvas found for spawning widget.")
        return
    parent.spawn_widget(scene)


func _on_deselect_widget_requested() -> void:
    _deselect_current()
    EventBus.widget_deselected.emit()


func _on_delete_widget_requested(widget_id: String) -> void:
    var all_widgets := get_all_nodes_recursive()
    for node in all_widgets:
        if node is BaseWidget and (node as BaseWidget).widget_id == widget_id:
            _delete_target(node)
            EventBus.widget_deleted.emit(widget_id)
            return
    push_warning("WidgetCanvas: widget_id '%s' not found for deletion." % widget_id)

# ── EventBus Handlers ─────────────────────────────────────────────────────────

func _on_widget_deselected_event() -> void:
    edit_widget_button.disabled = true

# ── Signal Handlers (from child BaseWidgets) ──────────────────────────────────

func _on_widget_selected(widget: SelectableControl) -> void:
    _select_target(widget)


func _on_widget_deselected() -> void:
    if _selected_target is BaseWidget:
        _selected_target = null
        IntentBus.deselect_widget_requested.emit()


func _find_parent_canvas(target: Node) -> WidgetCanvas:
    var current := target
    while current != null:
        if current is WidgetCanvas:
            return current as WidgetCanvas
        current = current.get_parent()
    return self
