class_name WidgetPropertyBuilder

var _panel       : PropertyPanel
var _target_data : ReactiveWidget

func _init(panel: PropertyPanel, target_data: ReactiveWidget) -> void:
    _panel       = panel
    _target_data = target_data

## Directly emits a property value without creating any UI field.
## Used by emit_all() to synchronise current widget state after
## fields have been built.
func emit(prop: String, value: Variant) -> void:
    IntentBus.change_widget_property_requested.emit(_target_data, prop, value)

# ── Private helpers ───────────────────────────────────────────────────────────

func _make_script_button(prop: String) -> Button:
    var button: Button = Button.new()
    button.text         = "{}"
    button.tooltip_text = "Open script editor"
    button.pressed.connect(func() -> void: _panel._open_script_editor(prop))
    return button

# ── Field builders ────────────────────────────────────────────────────────────

func add_float_field(lbl: String, target: ReactiveVariant) -> void:
    var row   :HBoxContainer = HBoxContainer.new()
    var label :Label = Label.new()
    var field :LineEdit = LineEdit.new()

    label.text                  = lbl
    label.custom_minimum_size.x = 100
    field.text                  = str(target.value)
    field.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    field.text_submitted.connect(func(v: String) -> void:
        _panel.property_changed.emit(target.label, float(v))
        field.text = str(target.value) # re-sync after widget accepts/refuses
    )

    row.add_child(label)
    row.add_child(field)
    #row.add_child(_make_script_button(target))
    _panel.extra_props.add_child(row)


func add_int_field(prop: String, lbl: String, current: int) -> void:
    var row   :HBoxContainer = HBoxContainer.new()
    var label :Label = Label.new()
    var field :LineEdit = LineEdit.new()

    label.text                  = lbl
    label.custom_minimum_size.x = 100
    field.text                  = str(current)
    field.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    field.text_submitted.connect(func(v: String) -> void: emit(prop, int(v)))

    row.add_child(label)
    row.add_child(field)
    row.add_child(_make_script_button(prop))
    _panel.extra_props.add_child(row)


func add_string_field(p: String, l: String, v: ReactiveDictionary) -> void:
    var row   :HBoxContainer = HBoxContainer.new()
    var label :Label = Label.new()
    var field :LineEdit = LineEdit.new()

    label.text                  = l
    label.custom_minimum_size.x = 100
    field.text                  = v.value[p].value
    field.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    field.text_submitted.connect(func(n: String) -> void:
        _panel.property_changed.emit(p, n)
        field.text = v.value[p].value # re-sync after widget accepts/refuses
    )

    row.add_child(label)
    row.add_child(field)
    #row.add_child(_make_script_button(target))
    _panel.extra_props.add_child(row)


func add_bool_field(prop: String, lbl: String, current: bool) -> void:
    var row      :HBoxContainer = HBoxContainer.new()
    var label    :Label = Label.new()
    var checkbox :CheckBox = CheckBox.new()

    label.text                     = lbl
    label.custom_minimum_size.x    = 100
    checkbox.button_pressed        = current
    checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    checkbox.toggled.connect(func(v: bool) -> void: emit(prop, v))

    row.add_child(label)
    row.add_child(checkbox)
    row.add_child(_make_script_button(prop))
    _panel.extra_props.add_child(row)


func add_color_field(prop: String, lbl: String, current: Color) -> void:
    var row    :HBoxContainer = HBoxContainer.new()
    var label  :Label = Label.new()
    var picker :ColorPickerButton = ColorPickerButton.new()

    label.text                   = lbl
    label.custom_minimum_size.x  = 100
    picker.color                 = current
    picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    picker.custom_minimum_size.y = 32

    picker.color_changed.connect(func(v: Color) -> void: emit(prop, v))

    row.add_child(label)
    row.add_child(picker)
    row.add_child(_make_script_button(prop))
    _panel.extra_props.add_child(row)


func add_string_list_field(prop: String, lbl: String, current: Array[String]) -> void:
    var working_copy: Array[String] = current.duplicate()

    var col       :VBoxContainer = VBoxContainer.new()
    var header    :HBoxContainer = HBoxContainer.new()
    var title_lbl :Label = Label.new()

    title_lbl.text                  = lbl
    title_lbl.custom_minimum_size.x = 100
    header.add_child(title_lbl)
    col.add_child(header)

    var scroll :ScrollContainer = ScrollContainer.new()
    scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
    scroll.custom_minimum_size.y  = 120
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

    var list_container :VBoxContainer = VBoxContainer.new()
    list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(list_container)
    col.add_child(scroll)

    for i: int in working_copy.size():
        _add_string_list_entry(prop, list_container, working_copy, i)

    var add_btn :Button = Button.new()
    add_btn.text                  = "+ Add Tab"
    add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_btn.pressed.connect(func() -> void:
        working_copy.append("New Tab")
        _add_string_list_entry(prop, list_container, working_copy, working_copy.size() - 1)
        emit(prop, working_copy.duplicate())
    )
    col.add_child(add_btn)
    _panel.extra_props.add_child(col)


func _add_string_list_entry(
    prop:      String,
    container: VBoxContainer,
    list:      Array[String],
    index:     int
) -> void:
    var entry_row :HBoxContainer = HBoxContainer.new()

    var field :LineEdit = LineEdit.new()
    field.text                  = list[index]
    field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    field.text_submitted.connect(func(new_text: String) -> void:
        list[index] = new_text
        emit(prop, list.duplicate())
    )
    entry_row.add_child(field)

    var remove_btn :Button = Button.new()
    remove_btn.text         = "✕"
    remove_btn.tooltip_text = "Remove this tab"
    remove_btn.pressed.connect(func() -> void:
        list.remove_at(index)
        entry_row.queue_free()
        emit(prop, list.duplicate())
    )
    entry_row.add_child(remove_btn)
    container.add_child(entry_row)


func add_node_field(
    prop: String,
    lbl:  String,
    v:    ReactiveDictionary
) -> void:
    var tag :ReactiveTag = v.value[prop] as ReactiveTag

    var col   :VBoxContainer = VBoxContainer.new()
    var label :Label = Label.new()
    label.text = lbl
    col.add_child(label)

    var server_row    :HBoxContainer = HBoxContainer.new()
    var server_label  :Label = Label.new()
    var server_option :OptionButton = OptionButton.new()

    server_label.text                   = "Server"
    server_label.custom_minimum_size.x  = 60
    server_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    _populate_server_option(server_option)

    var initial_server_id :String = tag.server_id.value \
        if tag.server_id.value != "" \
        else _get_first_server_id()
    _select_option_by_meta(server_option, initial_server_id)

    server_row.add_child(server_label)
    server_row.add_child(server_option)
    col.add_child(server_row)

    var group_row    :HBoxContainer = HBoxContainer.new()
    var group_label  :Label = Label.new()
    var group_option :OptionButton = OptionButton.new()

    group_label.text                   = "Group"
    group_label.custom_minimum_size.x  = 60
    group_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    _populate_group_option(group_option, initial_server_id)

    var initial_group_id :String = tag.group_id.value \
        if tag.group_id.value != "" \
        else _get_first_group_id(initial_server_id)
    _select_option_by_meta(group_option, initial_group_id)

    group_row.add_child(group_label)
    group_row.add_child(group_option)
    col.add_child(group_row)

    var tag_row    :HBoxContainer = HBoxContainer.new()
    var tag_label  :Label = Label.new()
    var tag_edit   :LineEdit = LineEdit.new()
    var browse_btn :Button = Button.new()

    tag_label.text                  = "Tag"
    tag_label.custom_minimum_size.x = 60
    tag_edit.text                   = tag.to_tag_name()
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
        var first_gid: String = _get_first_group_id(sid)
        _select_option_by_meta(group_option, first_gid)

        _panel.property_changed.emit(prop + "/server_id", sid)
        _panel.property_changed.emit(prop + "/group_id",  first_gid)
        _panel.property_changed.emit(prop + "/node_id",   null)

        # re-sync after widget accepts/refuses
        _select_option_by_meta(server_option, tag.server_id.value)
        _select_option_by_meta(group_option,  tag.group_id.value)
        if is_instance_valid(tag_edit):
            tag_edit.text = tag.to_tag_name()
    )

    group_option.item_selected.connect(func(_index: int) -> void:
        var gid: String = group_option.get_item_metadata(group_option.selected)

        _panel.property_changed.emit(prop + "/group_id", gid)

        # re-sync after widget accepts/refuses
        _select_option_by_meta(group_option, tag.group_id.value)
    )

    browse_btn.pressed.connect(func() -> void:
        var sid: String = server_option.get_item_metadata(server_option.selected) \
            if server_option.item_count > 0 else ""

        if sid == "":
            OS.alert(
                "No server configured.
    Add a server in the OPC UA connection dialog.",
                "Browse Unavailable"
            )
            return

        _panel._open_browser_for_server(sid, func(node_id: OpcUaNodeId) -> void:
            tag.node_id.value = node_id   # mutate the ReactiveTag sub-field directly

            if is_instance_valid(tag_edit):
                tag_edit.text = tag.to_tag_name()
        )
    )

    _panel.extra_props.add_child(col)


func _get_first_group_id(server_id: String) -> String:
    if server_id == "":
        return ""
    var cfg: OpcUaServerConfig = ProjectManager.opc_ua_registry.get_config(server_id)
    if cfg == null or cfg.subscription_groups.is_empty():
        return ""
    return cfg.subscription_groups[0].id

# ── Option population helpers ─────────────────────────────────────────────────

func _populate_server_option(option: OptionButton) -> void:
    option.clear()
    for cfg: OpcUaServerConfig in ProjectManager.opc_ua_registry.get_all_configs():
        var prefix: String = "● " if OpcUaManager.is_server_connected(cfg.id) else "○ "
        option.add_item(prefix + cfg.display_name)
        option.set_item_metadata(option.item_count - 1, cfg.id)


func _populate_group_option(option: OptionButton, server_id: String) -> void:
    option.clear()
    if server_id == "":
        return
    var cfg: OpcUaServerConfig = ProjectManager.opc_ua_registry.get_config(server_id)
    if cfg == null:
        return
    for group: OpcUaSubscriptionGroupConfig in cfg.subscription_groups:
        var item_label: String = "%s  —  %.0f ms" % [group.display_name, group.pub_interval_ms]
        option.add_item(item_label)
        option.set_item_metadata(option.item_count - 1, group.id)


func _select_option_by_meta(option: OptionButton, target_value: String) -> void:
    for i: int in option.item_count:
        if option.get_item_metadata(i) == target_value:
            option.select(i)
            return


func _get_first_server_id() -> String:
    var configs: Array[OpcUaServerConfig] = ProjectManager.opc_ua_registry.get_all_configs()
    return configs[0].id if not configs.is_empty() else ""
