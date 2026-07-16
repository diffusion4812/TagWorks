# selectable_control.gd
class_name SelectableControl
extends Control

signal selection_requested(control: SelectableControl)
signal widget_moved(widget: SelectableControl)
signal widget_resized(widget: SelectableControl)

const GRID_SIZE: int = 10

var _is_selected:      bool                  = false
var _handle_container: ResizeHandleContainer = null

# ─────────────────────────────────────────────
# Drag State
# ─────────────────────────────────────────────

var snap_enabled: bool = true

var _dragging:     bool    = false
var _drag_offset:  Vector2 = Vector2.ZERO
var _raw_position: Vector2 = Vector2.ZERO
var _raw_size:     Vector2 = Vector2.ZERO

# ── Virtuals ──────────────────────────────────────────────────────────────────

func get_drop_target() -> Control:
    return null

func get_class_name_override() -> String:
    return "SelectableControl"

func _on_edit_mode_changed(_enabled: bool) -> void:
    pass

func _propagate_edit_mode(enabled: bool) -> void:
    var drop_target: Control = get_drop_target()
    if drop_target == null:
        return
    for child: Node in drop_target.get_children():
        if child is SelectableControl:
            (child as SelectableControl).edit_mode = enabled

func build_properties(_builder: WidgetPropertyBuilder) -> void:
    pass

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

    if event is InputEventMouseButton or event is InputEventScreenTouch:
        if event.pressed:
            _drag_offset  = get_local_mouse_position()
            _raw_position = position
            _raw_size     = size
            select()
        else:
            if _dragging:
                widget_moved.emit(self)
        _dragging = event.pressed
        get_viewport().set_input_as_handled()

    if _dragging:
        if event is InputEventMouseMotion or event is InputEventScreenDrag:
            var bounds: Rect2         = _get_position_bounds()
            var local_mouse: Vector2  = (get_parent() as Control).get_local_mouse_position()
            _raw_position             = (local_mouse - _drag_offset).clamp(bounds.position, bounds.end)
            position                  = _snap(_raw_position)
            get_viewport().set_input_as_handled()

# ── Selection ─────────────────────────────────────────────────────────────────

func select() -> void:
    if _is_selected:
        return
    _is_selected = true
    _apply_selected_style(true)
    _show_handles()
    selection_requested.emit(self)


func deselect() -> void:
    if not _is_selected:
        return
    _is_selected = false
    _apply_selected_style(false)
    _hide_handles()


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
