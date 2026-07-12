class_name WidgetPropertyBuilder

var _panel: PropertyPanel

func _init(panel: PropertyPanel) -> void:
    _panel = panel

## Directly emits a property value without creating any UI field.
## Used by emit_all() to synchronise current widget state into the
## panel after fields have been built.
func emit(prop: String, value: Variant) -> void:
    _panel.property_changed.emit(prop, value)

# ── Private helpers ───────────────────────────────────────────────────────────

func _make_script_button(prop: String) -> Button:
    var button := Button.new()
    button.text         = "{}"
    button.tooltip_text = "Open script editor"
    button.pressed.connect(func(): _panel._open_script_editor(prop))
    return button

# ── Field builders ────────────────────────────────────────────────────────────

func add_float_field(prop: String, lbl: String, current: float) -> void:
    var row   := HBoxContainer.new()
    var label := Label.new()
    var field := LineEdit.new()

    label.text                  = lbl
    label.custom_minimum_size.x = 100
    field.text                  = str(current)
    field.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    field.text_submitted.connect(func(v): _panel.property_changed.emit(prop, float(v)))

    row.add_child(label)
    row.add_child(field)
    row.add_child(_make_script_button(prop))
    _panel.extra_props.add_child(row)


func add_int_field(prop: String, lbl: String, current: int) -> void:
    var row   := HBoxContainer.new()
    var label := Label.new()
    var field := LineEdit.new()

    label.text                  = lbl
    label.custom_minimum_size.x = 100
    field.text                  = str(current)
    field.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    field.text_submitted.connect(func(v): _panel.property_changed.emit(prop, int(v)))

    row.add_child(label)
    row.add_child(field)
    row.add_child(_make_script_button(prop))
    _panel.extra_props.add_child(row)


func add_string_field(prop: String, lbl: String, current: String) -> void:
    var row   := HBoxContainer.new()
    var label := Label.new()
    var field := LineEdit.new()

    label.text                  = lbl
    label.custom_minimum_size.x = 100
    field.text                  = current
    field.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    field.text_submitted.connect(func(v): _panel.property_changed.emit(prop, v))

    row.add_child(label)
    row.add_child(field)
    row.add_child(_make_script_button(prop))
    _panel.extra_props.add_child(row)


func add_bool_field(prop: String, lbl: String, current: bool) -> void:
    var row      := HBoxContainer.new()
    var label    := Label.new()
    var checkbox := CheckBox.new()

    label.text                     = lbl
    label.custom_minimum_size.x    = 100
    checkbox.button_pressed        = current
    checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    checkbox.toggled.connect(func(v): _panel.property_changed.emit(prop, v))

    row.add_child(label)
    row.add_child(checkbox)
    row.add_child(_make_script_button(prop))
    _panel.extra_props.add_child(row)


func add_color_field(prop: String, lbl: String, current: Color) -> void:
    var row    := HBoxContainer.new()
    var label  := Label.new()
    var picker := ColorPickerButton.new()

    label.text                   = lbl
    label.custom_minimum_size.x  = 100
    picker.color                 = current
    picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    picker.custom_minimum_size.y = 32

    picker.color_changed.connect(func(v): _panel.property_changed.emit(prop, v))

    row.add_child(label)
    row.add_child(picker)
    row.add_child(_make_script_button(prop))
    _panel.extra_props.add_child(row)


func add_string_list_field(prop: String, lbl: String, current: Array[String]) -> void:
    var working_copy: Array[String] = current.duplicate()

    var col       := VBoxContainer.new()
    var header    := HBoxContainer.new()
    var title_lbl := Label.new()

    title_lbl.text                  = lbl
    title_lbl.custom_minimum_size.x = 100
    header.add_child(title_lbl)
    col.add_child(header)

    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
    scroll.custom_minimum_size.y  = 120
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

    var list_container := VBoxContainer.new()
    list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(list_container)
    col.add_child(scroll)

    for i in working_copy.size():
        _add_string_list_entry(prop, list_container, working_copy, i)

    var add_btn := Button.new()
    add_btn.text                  = "+ Add Tab"
    add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_btn.pressed.connect(func() -> void:
        working_copy.append("New Tab")
        _add_string_list_entry(prop, list_container, working_copy, working_copy.size() - 1)
        _panel.property_changed.emit(prop, working_copy.duplicate())
    )
    col.add_child(add_btn)
    _panel.extra_props.add_child(col)


func _add_string_list_entry(
    prop:      String,
    container: VBoxContainer,
    list:      Array[String],
    index:     int
) -> void:
    var entry_row := HBoxContainer.new()

    var field := LineEdit.new()
    field.text                  = list[index]
    field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    field.text_submitted.connect(func(new_text: String) -> void:
        list[index] = new_text
        _panel.property_changed.emit(prop, list.duplicate())
    )
    entry_row.add_child(field)

    var remove_btn := Button.new()
    remove_btn.text         = "✕"
    remove_btn.tooltip_text = "Remove this tab"
    remove_btn.pressed.connect(func() -> void:
        list.remove_at(index)
        entry_row.queue_free()
        _panel.property_changed.emit(prop, list.duplicate())
    )
    entry_row.add_child(remove_btn)
    container.add_child(entry_row)


func add_node_field(
    prop:           String,
    lbl:            String,
    current_node:   OpcUaNodeId,
    current_server: String = "",
    current_group:  String = ""
) -> void:
    var col   := VBoxContainer.new()
    var label := Label.new()
    label.text = lbl
    col.add_child(label)

    var server_row    := HBoxContainer.new()
    var server_label  := Label.new()
    var server_option := OptionButton.new()

    server_label.text                   = "Server"
    server_label.custom_minimum_size.x  = 60
    server_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    _populate_server_option(server_option)

    var initial_server_id := current_server \
        if current_server != "" \
        else _get_first_server_id()
    _select_option_by_meta(server_option, initial_server_id)

    server_row.add_child(server_label)
    server_row.add_child(server_option)
    col.add_child(server_row)

    var group_row    := HBoxContainer.new()
    var group_label  := Label.new()
    var group_option := OptionButton.new()

    group_label.text                   = "Group"
    group_label.custom_minimum_size.x  = 60
    group_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    _populate_group_option(group_option, initial_server_id)

    var initial_group_id := current_group \
        if current_group != "" \
        else _get_first_group_id(initial_server_id)
    _select_option_by_meta(group_option, initial_group_id)

    group_row.add_child(group_label)
    group_row.add_child(group_option)
    col.add_child(group_row)

    var tag_row    := HBoxContainer.new()
    var tag_label  := Label.new()
    var tag_edit   := LineEdit.new()
    var browse_btn := Button.new()

    tag_label.text                  = "Tag"
    tag_label.custom_minimum_size.x = 60
    tag_edit.text                   = current_node.to_tag_name() \
                                          if current_node != null else ""
    tag_edit.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
    tag_edit.editable               = false
    browse_btn.text                 = "Browse"

    tag_row.add_child(tag_label)
    tag_row.add_child(tag_edit)
    tag_row.add_child(browse_btn)
    tag_row.add_child(_make_script_button(prop))
    col.add_child(tag_row)

    server_option.item_selected.connect(func(_index: int) -> void:
        var sid: String = server_option.get_item_metadata(server_option.selected)
        _populate_group_option(group_option, sid)
        var first_gid := _get_first_group_id(sid)
        _select_option_by_meta(group_option, first_gid)
        _panel.property_changed.emit(prop + "/server_id", sid)
        _panel.property_changed.emit(prop + "/group_id",  first_gid)
        if is_instance_valid(tag_edit):
            tag_edit.text = ""
        _panel.property_changed.emit(prop + "/node_id", null)
    )

    group_option.item_selected.connect(func(_index: int) -> void:
        var gid: String = group_option.get_item_metadata(group_option.selected)
        _panel.property_changed.emit(prop + "/group_id", gid)
    )

    browse_btn.pressed.connect(func() -> void:
        var sid: String = server_option.get_item_metadata(server_option.selected) \
            if server_option.item_count > 0 else ""

        if sid == "":
            OS.alert(
                "No server configured.\nAdd a server in the OPC UA connection dialog.",
                "Browse Unavailable"
            )
            return

        _panel._open_browser_for_server(sid, func(node_id: OpcUaNodeId) -> void:
            if is_instance_valid(tag_edit):
                tag_edit.text = node_id.to_tag_name()
            _panel.property_changed.emit(prop + "/node_id", node_id)
        )
    )

    _panel.extra_props.add_child(col)


func _get_first_group_id(server_id: String) -> String:
    if server_id == "":
        return ""
    var cfg := ProjectManager.opc_ua_registry.get_config(server_id)
    if cfg == null or cfg.subscription_groups.is_empty():
        return ""
    return cfg.subscription_groups[0].id

# ── Option population helpers ─────────────────────────────────────────────────

func _populate_server_option(option: OptionButton) -> void:
    option.clear()
    for cfg: OpcUaServerConfig in ProjectManager.opc_ua_registry.get_all_configs():
        var prefix := "● " if OpcUaManager.is_server_connected(cfg.id) else "○ "
        option.add_item(prefix + cfg.display_name)
        option.set_item_metadata(option.item_count - 1, cfg.id)


func _populate_group_option(option: OptionButton, server_id: String) -> void:
    option.clear()
    if server_id == "":
        return
    var cfg := ProjectManager.opc_ua_registry.get_config(server_id)
    if cfg == null:
        return
    for group: OpcUaSubscriptionGroupConfig in cfg.subscription_groups:
        var item_label := "%s  —  %.0f ms" % [group.display_name, group.pub_interval_ms]
        option.add_item(item_label)
        option.set_item_metadata(option.item_count - 1, group.id)


func _select_option_by_meta(option: OptionButton, target_value: String) -> void:
    for i in option.item_count:
        if option.get_item_metadata(i) == target_value:
            option.select(i)
            return


func _get_first_server_id() -> String:
    var configs := ProjectManager.opc_ua_registry.get_all_configs()
    return configs[0].id if not configs.is_empty() else ""
