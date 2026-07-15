# widgets/components/resize_handle.gd
class_name ResizeHandle
extends Control

## Renamed from Anchor to HandleAnchor to avoid collision with Control.Anchor
enum HandleAnchor {
    TOP_LEFT,
    TOP_CENTER,
    TOP_RIGHT,
    MIDDLE_LEFT,
    MIDDLE_RIGHT,
    BOTTOM_LEFT,
    BOTTOM_CENTER,
    BOTTOM_RIGHT
}

const HANDLE_SIZE := 10.0

signal drag_started()
signal drag_finished()
signal dragged(delta: Vector2, anchor: HandleAnchor)

@export var anchor: HandleAnchor = HandleAnchor.BOTTOM_RIGHT

var _dragging       := false
var _last_mouse_pos := Vector2.ZERO

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    custom_minimum_size        = Vector2(HANDLE_SIZE, HANDLE_SIZE)
    size                       = Vector2(HANDLE_SIZE, HANDLE_SIZE)
    mouse_filter               = MOUSE_FILTER_STOP
    mouse_default_cursor_shape = _cursor_for_anchor(anchor)

# ── Drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.9, 0.9, 0.9), true)
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.3, 0.3, 0.3), false)

# ── Input ─────────────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            _dragging       = true
            _last_mouse_pos = get_global_mouse_position()
            drag_started.emit()
            get_viewport().set_input_as_handled()
        else:
            _dragging = false
            drag_finished.emit()
            get_viewport().set_input_as_handled()

    if _dragging and event is InputEventMouseMotion:
        var current := get_global_mouse_position()
        var delta   := current - _last_mouse_pos
        _last_mouse_pos = current
        dragged.emit(delta, anchor)
        get_viewport().set_input_as_handled()

# ── Cursor ────────────────────────────────────────────────────────────────────

func _cursor_for_anchor(a: HandleAnchor) -> Control.CursorShape:
    match a:
        HandleAnchor.TOP_LEFT,     HandleAnchor.BOTTOM_RIGHT: return Control.CURSOR_FDIAGSIZE
        HandleAnchor.TOP_RIGHT,    HandleAnchor.BOTTOM_LEFT:  return Control.CURSOR_BDIAGSIZE
        HandleAnchor.TOP_CENTER,   HandleAnchor.BOTTOM_CENTER: return Control.CURSOR_VSIZE
        HandleAnchor.MIDDLE_LEFT,  HandleAnchor.MIDDLE_RIGHT:  return Control.CURSOR_HSIZE
    return Control.CURSOR_ARROW
