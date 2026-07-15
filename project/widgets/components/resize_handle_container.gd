# widgets/components/resize_handle_container.gd
class_name ResizeHandleContainer
extends Control

signal drag_started()
signal drag_finished()
signal dragged(delta: Vector2, anchor: ResizeHandle.HandleAnchor)

const HANDLE_SIZE := ResizeHandle.HANDLE_SIZE

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = MOUSE_FILTER_IGNORE
    _spawn_handles()


func _spawn_handles() -> void:
    for anchor in ResizeHandle.HandleAnchor.values():
        var handle := ResizeHandle.new()
        handle.anchor = anchor
        handle.drag_started.connect(func(): drag_started.emit())
        handle.drag_finished.connect(func(): drag_finished.emit())
        handle.dragged.connect(func(delta, a): dragged.emit(delta, a))
        add_child(handle)


## Repositions all handles to match the current size of the parent.
## Must be called after any size change on the parent.
func refresh() -> void:
    if not is_node_ready():
        return

    var configs := {
        ResizeHandle.HandleAnchor.TOP_LEFT: {
            "preset":  Control.PRESET_TOP_LEFT,
            "grow_h":  Control.GROW_DIRECTION_BEGIN,
            "grow_v":  Control.GROW_DIRECTION_BEGIN,
        },
        ResizeHandle.HandleAnchor.TOP_CENTER: {
            "preset":  Control.PRESET_CENTER_TOP,
            "grow_h":  Control.GROW_DIRECTION_BOTH,
            "grow_v":  Control.GROW_DIRECTION_BEGIN,
        },
        ResizeHandle.HandleAnchor.TOP_RIGHT: {
            "preset":  Control.PRESET_TOP_RIGHT,
            "grow_h":  Control.GROW_DIRECTION_END,
            "grow_v":  Control.GROW_DIRECTION_BEGIN,
        },
        ResizeHandle.HandleAnchor.MIDDLE_LEFT: {
            "preset":  Control.PRESET_CENTER_LEFT,
            "grow_h":  Control.GROW_DIRECTION_BEGIN,
            "grow_v":  Control.GROW_DIRECTION_BOTH,
        },
        ResizeHandle.HandleAnchor.MIDDLE_RIGHT: {
            "preset":  Control.PRESET_CENTER_RIGHT,
            "grow_h":  Control.GROW_DIRECTION_END,
            "grow_v":  Control.GROW_DIRECTION_BOTH,
        },
        ResizeHandle.HandleAnchor.BOTTOM_LEFT: {
            "preset":  Control.PRESET_BOTTOM_LEFT,
            "grow_h":  Control.GROW_DIRECTION_BEGIN,
            "grow_v":  Control.GROW_DIRECTION_END,
        },
        ResizeHandle.HandleAnchor.BOTTOM_CENTER: {
            "preset":  Control.PRESET_CENTER_BOTTOM,
            "grow_h":  Control.GROW_DIRECTION_BOTH,
            "grow_v":  Control.GROW_DIRECTION_END,
        },
        ResizeHandle.HandleAnchor.BOTTOM_RIGHT: {
            "preset":  Control.PRESET_BOTTOM_RIGHT,
            "grow_h":  Control.GROW_DIRECTION_END,
            "grow_v":  Control.GROW_DIRECTION_END,
        },
    }

    for child in get_children():
        if child is ResizeHandle:
            var config: Dictionary = configs.get(child.anchor, {})
            if config.is_empty():
                continue
            child.grow_horizontal = config["grow_h"]
            child.grow_vertical   = config["grow_v"]
            child.set_anchors_and_offsets_preset(config["preset"], Control.PRESET_MODE_MINSIZE)
