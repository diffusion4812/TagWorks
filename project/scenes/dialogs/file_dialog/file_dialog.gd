extends FileDialog

func _ready():
    # Configure standard file dialog behavior
    file_mode = FileDialog.FILE_MODE_SAVE_FILE
    
    # Detect host environment
    var platform = OS.get_name()
    var is_mobile = (platform == "Android" or platform == "iOS")
    
    if is_mobile:
        # Mobile: Break out into a dedicated, exclusive full screen viewport
        popup_window = true
        mode = Window.MODE_EXCLUSIVE_FULLSCREEN
    else:
        # Desktop: Display as a normal, standalone popup window
        popup_window = true
        mode = Window.MODE_WINDOWED
        
        # Set a fallback default size for desktop windows
        size = Vector2i(800, 600)
