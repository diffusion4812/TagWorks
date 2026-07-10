class_name ScriptEditorDialog
extends BaseDialog

@onready var code_edit: CodeEdit = $Panel/MarginContainer/CodeEdit

func _ready() -> void:
    _setup_code_edit()

func _setup_code_edit() -> void:
    code_edit.syntax_highlighter   = CodeHighlighter.new()
    code_edit.gutters_draw_line_numbers = true
    code_edit.gutters_draw_fold_gutter  = true
    code_edit.indent_automatic         = true
    code_edit.indent_use_spaces         = true
    code_edit.indent_size               = 4
    code_edit.auto_brace_completion_enabled = true

func _setup_autocomplete() -> void:
    code_edit.code_completion_enabled = true
    code_edit.code_completion_requested.connect(_on_completion_requested)

func _on_completion_requested() -> void:
    code_edit.add_code_completion_option(
        CodeEdit.KIND_FUNCTION, "print", "print(", Color.WHITE
    )
    code_edit.update_code_completion_options(true)

func _setup_syntax_highlighter() -> void:
    var hl := CodeHighlighter.new()

    # Keywords
    var keyword_color    := Color(0.36, 0.57, 0.90) # blue
    var control_color    := Color(0.86, 0.60, 0.24) # orange
    var literal_color    := Color(0.56, 0.86, 0.56) # green
    var comment_color    := Color(0.60, 0.60, 0.60) # grey
    var string_color     := Color(0.87, 0.76, 0.45) # yellow
    var number_color     := Color(0.78, 0.56, 0.86) # purple
    var symbol_color     := Color(0.90, 0.90, 0.90) # white

    var keywords := [
        "func", "var", "const", "class", "class_name", "extends",
        "signal", "enum", "static", "return", "pass", "self",
        "null", "true", "false", "and", "or", "not", "in", "is",
        "as", "await", "yield"
    ]

    var control_keywords := [
        "if", "elif", "else", "for", "while", "match",
        "break", "continue", "when"
    ]

    var type_keywords := [
        "bool", "int", "float", "String", "Vector2", "Vector3",
        "Color", "Array", "Dictionary", "Node", "Object", "Variant"
    ]

    for kw in keywords:
        hl.add_keyword_color(kw, keyword_color)

    for kw in control_keywords:
        hl.add_keyword_color(kw, control_color)

    for kw in type_keywords:
        hl.add_keyword_color(kw, literal_color)

    # Symbols
    hl.symbol_color = symbol_color

    # Numbers
    hl.number_color = number_color

    # Strings
    hl.add_color_region('"',  '"',  string_color)
    hl.add_color_region("'",  "'",  string_color)
    hl.add_color_region('"""', '"""', string_color, false)

    # Comments
    hl.add_color_region("#", "", comment_color, true)

    code_edit.syntax_highlighter = hl
