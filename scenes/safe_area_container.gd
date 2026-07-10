extends MarginContainer

var margin_left: int   = 4
var margin_top: int    = 8
var margin_right: int  = 4
var margin_bottom: int = 8

func _ready() -> void:
    # 1. Check if the game is running on a PC platform
    # This includes Windows, macOS, Linux, and Web browsers
    var pc_platforms = ["Windows", "macOS", "Linux", "Web"]
    if not OS.get_name() in pc_platforms:
        # 2. If it's a mobile or handheld device, calculate the safe area
        var safe_area: Rect2i = DisplayServer.get_display_safe_area()
        var window_size: Vector2i = DisplayServer.window_get_size()
        
        # 3. Calculate how much padding we need for each side
        margin_left += safe_area.position.x
        margin_top += safe_area.position.y
        margin_right += window_size.x - safe_area.end.x
        margin_bottom += window_size.y - safe_area.end.y
    
    # 4. Apply the safe padding to this MarginContainer
    add_theme_constant_override("margin_left", margin_left)
    add_theme_constant_override("margin_top", margin_top)
    add_theme_constant_override("margin_right", margin_right)
    add_theme_constant_override("margin_bottom", margin_bottom)
