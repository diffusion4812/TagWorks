class_name SelectableControl
extends Control

signal selection_requested(control: SelectableControl)
signal context_menu_requested(control: SelectableControl)
signal widget_moved(widget: SelectableControl)
signal widget_resized(widget: SelectableControl)

const GRID_SIZE: int = 10

var _is_selected:      bool                  = false
var _handle_container: ResizeHandleContainer = null

var snap_enabled: bool = true

var _dragging:     bool    = false
var _drag_offset:  Vector2 = Vector2.ZERO
var _raw_position: Vector2 = Vector2.ZERO
var _raw_size:     Vector2 = Vector2.ZERO

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    _raw_position = position
    AppState.selected_widgets.connect_self_changed(_on_selected_widgets_changed)
    _sync_selection_state()

# ── Virtuals ──────────────────────────────────────────────────────────────────

func get_drop_target() -> Control:
    return null

func get_class_name_override() -> String:
    return "SelectableControl"

## Overridden by subclasses (e.g. BaseWidget) to return the identity object
## (typically a ReactiveWidget) used to test membership in AppState.selected_widgets.
## Returning null means this control can never be considered selected.
func _get_selection_identity() -> Variant:
    return null

# ── Selection State (derived from AppState.selected_widgets) ─────────────────

func is_selected() -> bool:
    return _is_selected

func _on_selected_widgets_changed(_selected: Variant) -> void:
    _sync_selection_state()

func _sync_selection_state() -> void:
    var identity: Variant       = _get_selection_identity()
    var should_select: bool     = identity != null \
        and AppState.selected_widgets.value.has(identity)

    if should_select == _is_selected:
        return

    _is_selected = should_select
    _apply_selected_style(_is_selected)

    if _is_selected:
        _show_handles()
    else:
        _hide_handles()

# ── Grid Snapping ─────────────────────────────────────────────────────────────

func _snap(value: Vector2) -> Vector2:
    if not snap_enabled:
        return value
    return Vector2(
        snappedf(value.x, GRID_SIZE),
        snappedf(value.y, GRID_SIZE)
    )


func _get_position_bounds() -> Rect2:
    var parent: Node = get_parent()
    if parent is Control:
        return Rect2(Vector2.ZERO, (parent as Control).size - size)
    return Rect2(Vector2.ZERO, Vector2(INF, INF))

# ── Input ─────────────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
    if not AppState.edit_mode.value:
        return

    if event is InputEventMouseButton and event.pressed:
        match event.button_index:
            MOUSE_BUTTON_LEFT:
                _begin_drag()
                selection_requested.emit(self)
                get_viewport().set_input_as_handled()

            MOUSE_BUTTON_RIGHT:
                context_menu_requested.emit(self)
                get_viewport().set_input_as_handled()
        return

    if event is InputEventMouseButton and not event.pressed \
            and event.button_index == MOUSE_BUTTON_LEFT:
        if _dragging:
            widget_moved.emit(self)
        _dragging = false
        get_viewport().set_input_as_handled()
        return

    if event is InputEventScreenTouch:
        if event.pressed:
            _begin_drag()
            selection_requested.emit(self)
        else:
            if _dragging:
                widget_moved.emit(self)
            _dragging = false
        get_viewport().set_input_as_handled()
        return

    if _dragging and (event is InputEventMouseMotion or event is InputEventScreenDrag):
        var bounds: Rect2        = _get_position_bounds()
        var local_mouse: Vector2 = (get_parent() as Control).get_local_mouse_position()
        _raw_position            = (local_mouse - _drag_offset).clamp(bounds.position, bounds.end)
        position                 = _snap(_raw_position)
        get_viewport().set_input_as_handled()


func _begin_drag() -> void:
    _drag_offset  = get_local_mouse_position()
    _raw_position = position
    _raw_size     = size
    _dragging     = true

# ── Style ─────────────────────────────────────────────────────────────────────

func _apply_selected_style(active: bool) -> void:
    modulate = Color(1.2, 1.2, 1.2) if active else Color.WHITE

# ── Handles ───────────────────────────────────────────────────────────────────

func _show_handles() -> void:
    if _handle_container != null:
        return
    _handle_container = ResizeHandleContainer.new()
    _handle_container.dragged.connect(_on_handle_dragged)
    _handle_container.drag_finished.connect(_on_handle_drag_finished)
    add_child(_handle_container)
    _handle_container.refresh()


func _hide_handles() -> void:
    if _handle_container == null:
        return
    _handle_container.queue_free()
    _handle_container = null


func _on_handle_dragged(delta: Vector2, anchor: ResizeHandle.HandleAnchor) -> void:
    var raw_pos: Vector2  = _raw_position
    var raw_size: Vector2 = _raw_size

    match anchor:
        ResizeHandle.HandleAnchor.TOP_LEFT:
            raw_pos  += delta
            raw_size -= delta
        ResizeHandle.HandleAnchor.TOP_CENTER:
            raw_pos.y  += delta.y
            raw_size.y -= delta.y
        ResizeHandle.HandleAnchor.TOP_RIGHT:
            raw_pos.y  += delta.y
            raw_size    = Vector2(raw_size.x + delta.x, raw_size.y - delta.y)
        ResizeHandle.HandleAnchor.MIDDLE_LEFT:
            raw_pos.x  += delta.x
            raw_size.x -= delta.x
        ResizeHandle.HandleAnchor.MIDDLE_RIGHT:
            raw_size.x += delta.x
        ResizeHandle.HandleAnchor.BOTTOM_LEFT:
            raw_pos.x  += delta.x
            raw_size    = Vector2(raw_size.x - delta.x, raw_size.y + delta.y)
        ResizeHandle.HandleAnchor.BOTTOM_CENTER:
            raw_size.y += delta.y
        ResizeHandle.HandleAnchor.BOTTOM_RIGHT:
            raw_size   += delta

    _raw_size     = raw_size
    _raw_position = raw_pos

    size     = _snap(_raw_size)
    position = _snap(_raw_position)
    _handle_container.refresh()

func _on_handle_drag_finished() -> void:
    widget_resized.emit(self)

# ── Serialization ─────────────────────────────────────────────────────────────

func serialize() -> Dictionary:
    return {
        "class":    get_class_name_override(),
        "position": { "x": position.x, "y": position.y },
        "size":     { "x": size.x,     "y": size.y     },
    }


func deserialize(data: Dictionary) -> void:
    position = Vector2(
        data.get("position", {}).get("x", 0.0),
        data.get("position", {}).get("y", 0.0)
    )
    size = Vector2(
        data.get("size", {}).get("x", 128.0),
        data.get("size", {}).get("y", 128.0)
    )
