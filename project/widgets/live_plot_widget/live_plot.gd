class_name LivePlot extends Control

# --- Data Structures --------------------------------------------------------
class PlotSignal:
    var name    : String
    var color   : Color
    var enabled : bool = true
    var axis_id : int  = 0
    var times   : PackedFloat32Array = PackedFloat32Array()
    var values  : PackedFloat32Array = PackedFloat32Array()

    func _init(_name: String, _color: Color, _axis: int) -> void:
        name = _name
        color = _color
        axis_id = _axis

class AxisBounds:
    var min_v : float = INF
    var max_v : float = -INF
    func update(v: float) -> void:
        min_v = minf(min_v, v)
        max_v = maxf(max_v, v)

# --- Configuration ----------------------------------------------------------
@export_group("Visuals")
@export var background_color : Color = Color(0.05, 0.05, 0.05, 0.9)
@export var axis_color       : Color = Color(0.6, 0.6, 0.6, 0.5)
@export var font             : Font  = ThemeDB.fallback_font

@export_group("Time Window")
@export var time_window      : float = 10.0
@export var time_divisions   : int   = 5
@export var max_points       : int   = 2000

@export_group("Interaction")
@export var zoom_speed : float = 1.1
@export var min_window : float = 0.1

@export_group("Smoothing")
@export var y_smoothing_enabled : bool  = true
@export var y_smooth_speed      : float = 5.0

# --- State ------------------------------------------------------------------
var signals : Dictionary = {} # String -> PlotSignal
var _redraw_pending : bool = false
var _smooth_min : float = 0.0
var _smooth_max : float = 1.0

# --- Public API -------------------------------------------------------------

func add_signal(sig_name: String, color: Color = Color.WHITE, axis: int = 0) -> void:
    if not signals.has(sig_name):
        signals[sig_name] = PlotSignal.new(sig_name, color, axis)
        queue_redraw()

func push_data(sig_name: String, value: float, timestamp: float = -1.0) -> void:
    if not signals.has(sig_name):
        return
    var t: float = timestamp if timestamp >= 0.0 else Time.get_ticks_usec() * 1e-6
    var sig: PlotSignal = signals[sig_name]
    sig.times.append(t)
    sig.values.append(value)

    # Trim logic
    var cutoff: float = t - time_window
    while sig.times.size() > 0 and sig.times[0] < cutoff:
        sig.times.remove_at(0)
        sig.values.remove_at(0)

    if sig.times.size() > max_points:
        sig.times = sig.times.slice(sig.times.size() - max_points)
        sig.values = sig.values.slice(sig.values.size() - max_points)

    _redraw_pending = true

## Set the axis number of an existing signal at runtime
func set_signal_axis(sig_name: String, axis_id: int) -> void:
    if signals.has(sig_name):
        signals[sig_name].axis_id = axis_id
        queue_redraw()

## Change the color of an existing signal at runtime
func set_signal_color(sig_name: String, new_color: Color) -> void:
    if signals.has(sig_name):
        signals[sig_name].color = new_color
        queue_redraw()

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.is_pressed():
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            time_window = maxf(min_window, time_window / zoom_speed)
            accept_event()
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            time_window *= zoom_speed
            accept_event()

func _process(delta: float) -> void:
    var raw_min : float = INF
    var raw_max : float = -INF

    for sig: PlotSignal in signals.values():
        for v: float in sig.values:
            raw_min = minf(raw_min, v)
            raw_max = maxf(raw_max, v)

    if raw_min < INF:
        if y_smoothing_enabled:
            _smooth_min = lerpf(_smooth_min, raw_min, y_smooth_speed * delta)
            _smooth_max = lerpf(_smooth_max, raw_max, y_smooth_speed * delta)
        else:
            _smooth_min = raw_min
            _smooth_max = raw_max

    queue_redraw()

# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), background_color)

    # Always use current real time so the axis scrolls continuously
    var t_now : float = Time.get_ticks_usec() * 1e-6
    var t_max : float = t_now
    var t_min : float = t_max - time_window

    var active_axes : Dictionary = {} # int -> AxisBounds

    for sig: PlotSignal in signals.values():
        if not sig.enabled or sig.times.size() == 0:
            continue
        if not active_axes.has(sig.axis_id):
            active_axes[sig.axis_id] = AxisBounds.new()
        for v: float in sig.values:
            active_axes[sig.axis_id].update(v)

    if active_axes.is_empty():
        return

    var sorted_axis_ids : Array = active_axes.keys()
    sorted_axis_ids.sort()

    var margin_left : float = 10.0 + (sorted_axis_ids.size() * 45.0)
    var plot_rect : Rect2 = Rect2(margin_left, 10, size.x - margin_left - 20, size.y - 40)

    _draw_time_grid(plot_rect, t_min, t_max)

    for i: int in range(sorted_axis_ids.size()):
        var id: int = sorted_axis_ids[i]
        var b: AxisBounds = active_axes[id]
        var x_pos: float = plot_rect.position.x - (i * 45.0) - 5.0
        _draw_v_axis(plot_rect, x_pos, id, b.min_v, b.max_v)

    for sig: PlotSignal in signals.values():
        if not sig.enabled or sig.times.size() < 2:
            continue
        var b: AxisBounds = active_axes[sig.axis_id]
        _draw_signal_line(sig, plot_rect, t_min, t_max, b.min_v, b.max_v)

func _draw_time_grid(r: Rect2, t_min: float, t_max: float) -> void:
    for i: int in range(time_divisions + 1):
        var x: float = r.position.x + (float(i) / time_divisions) * r.size.x
        draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), axis_color)
        var lbl: String = "%.1fs" % ((t_min + (float(i) / time_divisions) * time_window) - t_max)
        draw_string(font, Vector2(x - 15, r.end.y + 18), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.GRAY)

func _draw_v_axis(r: Rect2, x: float, id: int, v_min: float, v_max: float) -> void:
    if is_equal_approx(v_min, v_max):
        v_max += 1.0
    draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), axis_color, 1.0)
    # Label the axis ID at top
    draw_string(font, Vector2(x - 20, r.position.y - 2), "A%d" % id, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color.WHITE)

    for i: int in range(5):
        var frac: float = i / 4.0
        var y: float = r.end.y - (frac * r.size.y)
        var val: float = lerp(v_min, v_max, frac)
        draw_string(font, Vector2(x - 42, y + 4), str(snapped(val, 0.01)), HORIZONTAL_ALIGNMENT_RIGHT, -1, 9, Color.LIGHT_GRAY)

func _draw_signal_line(sig: PlotSignal, r: Rect2, t0: float, t1: float, y0: float, y1: float) -> void:
    var pts : PackedVector2Array = PackedVector2Array()
    var t_range : float = t1 - t0
    var y_range : float = y1 - y0 if not is_equal_approx(y1, y0) else 1.0
    for i: int in sig.times.size():
        var px: float = r.position.x + ((sig.times[i] - t0) / t_range) * r.size.x
        var py: float = r.end.y - ((sig.values[i] - y0) / y_range) * r.size.y
        pts.append(Vector2(px, py))
    draw_polyline(pts, sig.color, 1.5, true)
