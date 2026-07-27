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
    var binding_prop: ReactiveOpcUaTagBinding = v.value[prop] as ReactiveOpcUaTagBinding

    # Fundamental runtime type wrapping the three identity fields. Added as a
    # child of `col` below so its lifecycle (and OpcUaManager signal cleanup
    # in _exit_tree) is handled automatically when this field is torn down.
    var binding: OpcUaBinding = OpcUaBinding.new()
    binding.setup(
        binding_prop.server_id.value,
        binding_prop.group_id.value,
        binding_prop.parsed_node_id()
    )

    var col   : VBoxContainer = VBoxContainer.new()
    var label : Label = Label.new()
    label.text = lbl
    col.add_child(label)
    col.add_child(binding)

    var server_row    : HBoxContainer = HBoxContainer.new()
    var server_label  : Label = Label.new()
    var server_option : OptionButton = OptionButton.new()

    server_label.text                   = "Server"
    server_label.custom_minimum_size.x  = 60
    server_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    _populate_server_option(server_option)
    _select_option_by_metadata(server_option, binding_prop.server_id.value)

    server_row.add_child(server_label)
    server_row.add_child(server_option)
    col.add_child(server_row)

    var group_row    : HBoxContainer = HBoxContainer.new()
    var group_label  : Label = Label.new()
    var group_option : OptionButton = OptionButton.new()

    group_label.text                   = "Group"
    group_label.custom_minimum_size.x  = 60
    group_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    _populate_group_option(group_option, binding_prop.server_id.value)
    _select_option_by_metadata(group_option, binding_prop.group_id.value)

    group_row.add_child(group_label)
    group_row.add_child(group_option)
    col.add_child(group_row)

    var tag_row    : HBoxContainer = HBoxContainer.new()
    var tag_label  : Label = Label.new()
    var tag_edit   : LineEdit = LineEdit.new()
    var browse_btn : Button = Button.new()

    tag_label.text                  = "Tag"
    tag_label.custom_minimum_size.x = 60
    tag_edit.text                   = binding_prop.node_id.value if binding_prop.node_id.value != "" else "(none)"
    tag_edit.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
    tag_edit.editable               = false
    browse_btn.text                 = "Browse"

    tag_row.add_child(tag_label)
    tag_row.add_child(tag_edit)
    tag_row.add_child(browse_btn)
    col.add_child(tag_row)

    # ── Reactive → UI (binding_prop changes update the widgets) ──────────────

    var on_server_changed: Callable = func(_new_value: String) -> void:
        if not is_instance_valid(server_option):
            return
        _select_option_by_metadata(server_option, binding_prop.server_id.value)
        if is_instance_valid(group_option):
            _populate_group_option(group_option, binding_prop.server_id.value)
            _select_option_by_metadata(group_option, binding_prop.group_id.value)
        binding.setup(
            binding_prop.server_id.value,
            binding_prop.group_id.value,
            binding_prop.parsed_node_id()
        )

    var on_group_changed: Callable = func(_new_value: String) -> void:
        if not is_instance_valid(group_option):
            return
        _select_option_by_metadata(group_option, binding_prop.group_id.value)
        binding.setup(
            binding_prop.server_id.value,
            binding_prop.group_id.value,
            binding_prop.parsed_node_id()
        )

    var on_node_id_changed: Callable = func(_new_value: String) -> void:
        if not is_instance_valid(tag_edit):
            return
        tag_edit.text = binding_prop.node_id.value if binding_prop.node_id.value != "" else "(none)"
        binding.setup(
            binding_prop.server_id.value,
            binding_prop.group_id.value,
            binding_prop.parsed_node_id()
        )

    binding_prop.server_id.changed.connect(on_server_changed)
    binding_prop.group_id.changed.connect(on_group_changed)
    binding_prop.node_id.changed.connect(on_node_id_changed)

    col.tree_exiting.connect(func() -> void:
        if binding_prop.server_id.changed.is_connected(on_server_changed):
            binding_prop.server_id.changed.disconnect(on_server_changed)
        if binding_prop.group_id.changed.is_connected(on_group_changed):
            binding_prop.group_id.changed.disconnect(on_group_changed)
        if binding_prop.node_id.changed.is_connected(on_node_id_changed):
            binding_prop.node_id.changed.disconnect(on_node_id_changed)
    )

    # ── User intent → binding_prop (UI updates only set data, never text) ────

    server_option.item_selected.connect(func(_index: int) -> void:
        var sid: String = server_option.get_item_metadata(server_option.selected)
        binding_prop.server_id.value = sid
        binding_prop.group_id.value  = ""
        binding_prop.node_id.value   = ""
    )

    group_option.item_selected.connect(func(_index: int) -> void:
        var gid: String = group_option.get_item_metadata(group_option.selected)
        binding_prop.group_id.value = gid
    )

    browse_btn.pressed.connect(func() -> void:
        _panel.opc_ua_connection_dialog.browse(func(result: OpcUaTagBinding) -> void:
            if not result.is_valid():
                return

            _ensure_tag_registered(result.server_id, result.group_id, result.node_id)

            binding_prop.server_id.value = result.server_id
            binding_prop.group_id.value  = result.group_id
            binding_prop.node_id.value   = result.node_id_string()
        )
    )

    _panel.extra_props.add_child(col)

## Ensures a ReactiveOpcUaTag exists for `node_id` inside the target group's
## tags array. If one already exists (matched by node_id string), it is left
## untouched; otherwise a new tag entry is appended so OpcUaGroup will pick
## it up on the next reconciliation and actually subscribe to it.
func _ensure_tag_registered(server_id: String, group_id: String, node_id: OpcUaNodeId) -> void:
    var project: ReactiveProject = AppState.current_project.value
    if project == null:
        return

    var server: ReactiveOpcUaServer = null
    for s: ReactiveOpcUaServer in project.opc_ua_servers.value:
        if s.id.value == server_id:
            server = s
            break

    if server == null:
        push_warning("_ensure_tag_registered: server '%s' not found." % server_id)
        return

    var group: ReactiveOpcUaSubscription = null
    for g: ReactiveOpcUaSubscription in server.groups.value:
        if g.id.value == group_id:
            group = g
            break

    if group == null:
        push_warning("_ensure_tag_registered: group '%s' not found on server '%s'." % [group_id, server_id])
        return

    var node_id_str: String = node_id.to_tag_name()

    for existing: ReactiveOpcUaTag in group.tags.value:
        if existing.node_id.value == node_id_str:
            return  # already registered — nothing to do

    var new_tag: ReactiveOpcUaTag = ReactiveOpcUaTag.new({
        "node_id": node_id_str,
        "display_name": node_id_str,
        "is_active": true,
    }, group, "tag")

    group.tags.append(new_tag)

# ── Option population helpers ─────────────────────────────────────────────────
func _populate_server_option(option: OptionButton) -> void:
    option.clear()

    var project: ReactiveProject = AppState.current_project.value
    if project == null:
        return

    for cfg: ReactiveOpcUaServer in project.opc_ua_servers.values():
        option.add_item(cfg.display_name.value)
        option.set_item_metadata(option.item_count - 1, cfg.id.value)


func _populate_group_option(option: OptionButton, server_id: String) -> void:
    option.clear()
    if server_id == "":
        return

    var project: ReactiveProject = AppState.current_project.value
    if project == null:
        return

    var cfg: ReactiveOpcUaServer = null
    for server: ReactiveOpcUaServer in project.opc_ua_servers.values():
        if server.id.value == server_id:
            cfg = server
            break

    if cfg == null:
        return

    for group: ReactiveOpcUaSubscription in cfg.groups.values():
        var item_label: String = "%s  —  %.0f ms" % [group.id.value, group.pub_interval_ms.value]
        option.add_item(item_label)
        option.set_item_metadata(option.item_count - 1, group.id.value)

func _select_option_by_metadata(option: OptionButton, metadata_value: String) -> void:
    for i: int in option.item_count:
        if option.get_item_metadata(i) == metadata_value:
            option.select(i)
            return
