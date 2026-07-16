# scenes/widget_palette/widget_palette.gd
class_name WidgetPalette
extends PanelContainer

const WIDGET_TYPES: Array[Dictionary] = [
    { "label": "🔘 Button",        "scene": preload("res://widgets/button_widget/button_widget.tscn")                  },
    { "label": "🏷️ Label",         "scene": preload("res://widgets/label_widget/label_widget.tscn")                    },
    { "label": "🔢 Numeric Field", "scene": preload("res://widgets/numeric_field_widget/numeric_field_widget.tscn")    },
    { "label": "📈 Live Plot",     "scene": preload("res://widgets/live_plot_widget/live_plot_widget.tscn")            },
]

@onready var palette_list: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/PaletteList
@onready var cancel_btn:   Button        = $MarginContainer/VBoxContainer/Button

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    for widget_def: Dictionary in WIDGET_TYPES:
        var btn: Button = Button.new()
        btn.text                  = widget_def["label"]
        btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        btn.pressed.connect(
            func() -> void:
                IntentBus.add_widget_requested.emit(widget_def["scene"] as PackedScene)
        )
        palette_list.add_child(btn)

    cancel_btn.pressed.connect(_on_cancel_pressed)


func _on_cancel_pressed() -> void:
    hide()
