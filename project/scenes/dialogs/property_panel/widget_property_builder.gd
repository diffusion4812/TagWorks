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


func add_dynamic_field(p: String, l: String, v: ReactiveDictionary) -> void:
    var field: ReactiveDynamicField = v.value[p]

    var row: HBoxContainer = HBoxContainer.new()
    var label: Label = Label.new()
    label.text                  = l
    label.custom_minimum_size.x = 100
    row.add_child(label)

    var container: VBoxContainer = VBoxContainer.new()
    container.add_child(row)
    container.add_child(_build_dynamic_field_editor(p, field))
    _panel.extra_props.add_child(container)

func add_action_field(p: String, l: String, v: ReactiveDictionary) -> void:
    var action: ReactiveActionBinding = v.value[p]

    var row: HBoxContainer = HBoxContainer.new()
    var label: Label = Label.new()
    var type_dropdown: OptionButton = OptionButton.new()
    var editor_slot: VBoxContainer = VBoxContainer.new()

    label.text                  = l
    label.custom_minimum_size.x = 100

    type_dropdown.add_item("None",           ReactiveActionBinding.ActionType.NONE)
    type_dropdown.add_item("Write Tag",      ReactiveActionBinding.ActionType.WRITE_TAG)
    type_dropdown.add_item("Run Script",     ReactiveActionBinding.ActionType.RUN_SCRIPT)
    type_dropdown.add_item("Navigate Scene", ReactiveActionBinding.ActionType.NAVIGATE_SCENE)
    type_dropdown.add_item("Emit App Event", ReactiveActionBinding.ActionType.EMIT_APP_EVENT)
    type_dropdown.select(action.action_type.value)

    row.add_child(label)
    row.add_child(type_dropdown)

    var container: VBoxContainer = VBoxContainer.new()
    container.add_child(row)
    container.add_child(editor_slot)

    var rebuild: Callable = func() -> void:
        for child: Node in editor_slot.get_children():
            child.queue_free()
        match action.action_type.value:
            ReactiveActionBinding.ActionType.WRITE_TAG:
                var wrapper: VBoxContainer = VBoxContainer.new()
                wrapper.add_child(_build_write_target_editor(action.target_node, func() -> void:
                    _panel.property_changed.emit(p, action)
                ))
                wrapper.add_child(_build_dynamic_field_editor(p, action.value))
                editor_slot.add_child(wrapper)
            ReactiveActionBinding.ActionType.RUN_SCRIPT:
                editor_slot.add_child(_make_action_script_editor(p, action))
            ReactiveActionBinding.ActionType.NAVIGATE_SCENE:
                editor_slot.add_child(_make_scene_path_editor(p, action))
            ReactiveActionBinding.ActionType.EMIT_APP_EVENT:
                editor_slot.add_child(_make_event_name_editor(p, action))
            ReactiveActionBinding.ActionType.NONE:
                pass  # nothing to configure

    type_dropdown.item_selected.connect(func(idx: int) -> void:
        action.action_type.value = type_dropdown.get_item_id(idx)
        _panel.property_changed.emit(p, action)
        rebuild.call()
    )

    rebuild.call()
    _panel.extra_props.add_child(container)

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


func add_node_field(prop: String, lbl: String, v: ReactiveDictionary) -> void:
    var binding_prop: ReactiveOpcUaTagBinding = v.value[prop] as ReactiveOpcUaTagBinding

    var col: VBoxContainer = VBoxContainer.new()
    var label: Label = Label.new()
    label.text = lbl
    col.add_child(label)
    col.add_child(_build_tag_binding_editor(binding_prop))

    _panel.extra_props.add_child(col)

# ── Option population helpers ─────────────────────────────────────────────────
func _populate_server_option(option: OptionButton) -> void:
    option.clear()

    for cfg: ReactiveOpcUaServer in AppState.current_project.opc_ua_servers.values():
        option.add_item(cfg.display_name.value)
        option.set_item_metadata(option.item_count - 1, cfg.id.value)


func _populate_group_option(option: OptionButton, server_id: String) -> void:
    option.clear()
    if server_id == "":
        return

    for group: ReactiveOpcUaSubscription in AppState.current_project.opc_ua_servers.get_entry(server_id).subscriptions.values():
        var item_label: String = "%s  —  %.0f ms" % [group.id.value, group.pub_interval_ms.value]
        option.add_item(item_label)
        option.set_item_metadata(option.item_count - 1, group.id.value)

func _select_option_by_metadata(option: OptionButton, metadata_value: String) -> void:
    for i: int in option.item_count:
        if option.get_item_metadata(i) == metadata_value:
            option.select(i)
            return

func _build_dynamic_field_editor(p: String, field: ReactiveDynamicField) -> Control:
    var wrapper: VBoxContainer = VBoxContainer.new()
    var source_dropdown: OptionButton = OptionButton.new()
    var editor_slot: MarginContainer = MarginContainer.new()

    source_dropdown.add_item("Constant", ReactiveDynamicField.SourceType.CONSTANT)
    source_dropdown.add_item("OPC Tag",  ReactiveDynamicField.SourceType.OPC_TAG)
    source_dropdown.add_item("Script",   ReactiveDynamicField.SourceType.SCRIPT)
    source_dropdown.select(field.source_type.value)

    wrapper.add_child(source_dropdown)
    wrapper.add_child(editor_slot)

    var rebuild: Callable = func() -> void:
        for child: Node in editor_slot.get_children():
            child.queue_free()
        match field.source_type.value:
            ReactiveDynamicField.SourceType.CONSTANT:
                editor_slot.add_child(_make_constant_editor(p, field))
            ReactiveDynamicField.SourceType.OPC_TAG:
                editor_slot.add_child(_make_tag_editor(p, field))
            ReactiveDynamicField.SourceType.SCRIPT:
                editor_slot.add_child(_make_script_editor(p, field))

    source_dropdown.item_selected.connect(func(idx: int) -> void:
        field.source_type.value = source_dropdown.get_item_id(idx)
        _panel.property_changed.emit(p, field)
        rebuild.call()
    )

    rebuild.call()
    return wrapper

func _make_constant_editor(p: String, f: ReactiveDynamicField) -> Control:
    var field: LineEdit = LineEdit.new()
    field.text                  = str(f.constant_value.value)
    field.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    field.text_submitted.connect(func(n: String) -> void:
        f.constant_value.value = n
        _panel.property_changed.emit(p, f)
        field.text = str(f.constant_value.value)
    )
    return field

func _make_tag_editor(p: String, f: ReactiveDynamicField) -> Control:
    return _build_tag_binding_editor(f.tag_binding, func() -> void:
        _panel.property_changed.emit(p, f)
    )

func _make_script_editor(p: String, f: ReactiveDynamicField) -> Control:
    var edit: TextEdit = TextEdit.new()
    edit.text                  = f.script_source.value
    edit.custom_minimum_size.y = 80
    edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    edit.text_changed.connect(func() -> void:
        f.script_source.value = edit.text
        _panel.property_changed.emit(p, f)
    )
    return edit

func _make_action_script_editor(p: String, a: ReactiveActionBinding) -> Control:
    var edit: TextEdit = TextEdit.new()
    edit.text                  = a.script_source.value
    edit.custom_minimum_size.y = 100
    edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    edit.text_changed.connect(func() -> void:
        a.script_source.value = edit.text
        _panel.property_changed.emit(p, a)
    )
    return edit

func _make_scene_path_editor(p: String, a: ReactiveActionBinding) -> Control:
    var field: LineEdit = LineEdit.new()
    field.text                  = a.scene_path.value
    field.placeholder_text      = "res://path/to/scene.tscn"
    field.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    field.text_submitted.connect(func(n: String) -> void:
        a.scene_path.value = n
        _panel.property_changed.emit(p, a)
        field.text = a.scene_path.value
    )
    return field

func _make_event_name_editor(p: String, a: ReactiveActionBinding) -> Control:
    var field: LineEdit = LineEdit.new()
    field.text                  = a.event_name.value
    field.placeholder_text      = "custom_event_name"
    field.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    field.text_submitted.connect(func(n: String) -> void:
        a.event_name.value = n
        _panel.property_changed.emit(p, a)
        field.text = a.event_name.value
    )
    return field

func _build_tag_binding_editor(
    binding_prop: ReactiveOpcUaTagBinding,
    on_change: Callable = Callable()
) -> Control:
    var container: VBoxContainer = VBoxContainer.new()

    # ── Server row ─────────────────────────────────────────────
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
    container.add_child(server_row)

    # ── Group row ──────────────────────────────────────────────
    var group_row    : HBoxContainer = HBoxContainer.new()
    var group_label  : Label = Label.new()
    var group_option : OptionButton = OptionButton.new()

    group_label.text                   = "Group"
    group_label.custom_minimum_size.x  = 60
    group_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    _populate_group_option(group_option, binding_prop.server_id.value)
    _select_option_by_metadata(group_option, binding_prop.subscription_id.value)

    group_row.add_child(group_label)
    group_row.add_child(group_option)
    container.add_child(group_row)

    # ── Tag row ────────────────────────────────────────────────
    var tag_row    : HBoxContainer = HBoxContainer.new()
    var tag_label  : Label = Label.new()
    var tag_edit   : LineEdit = LineEdit.new()
    var browse_btn : Button = Button.new()

    tag_label.text                  = "Tag"
    tag_label.custom_minimum_size.x = 60
    tag_edit.text                   = binding_prop.tag_id.value
    tag_edit.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
    tag_edit.editable               = false
    browse_btn.text                 = "Browse"

    tag_row.add_child(tag_label)
    tag_row.add_child(tag_edit)
    tag_row.add_child(browse_btn)
    container.add_child(tag_row)

    # ── Reactive → UI ──────────────────────────────────────────
    var on_server_changed: Callable = func(_new_value: ReactiveString) -> void:
        if not is_instance_valid(server_option):
            return
        _select_option_by_metadata(server_option, _new_value.value)
        if is_instance_valid(group_option):
            _populate_group_option(group_option, _new_value.value)
            _select_option_by_metadata(group_option, binding_prop.subscription_id.value)

    var on_subscription_changed: Callable = func(_new_value: ReactiveString) -> void:
        if is_instance_valid(group_option):
            _select_option_by_metadata(group_option, _new_value.value)

    var on_tag_id_changed: Callable = func(_new_value: ReactiveString) -> void:
        if is_instance_valid(tag_edit):
            tag_edit.text = _new_value.value

    binding_prop.server_id.connect_self_changed(on_server_changed)
    binding_prop.subscription_id.connect_self_changed(on_subscription_changed)
    binding_prop.tag_id.connect_self_changed(on_tag_id_changed)

    container.tree_exiting.connect(func() -> void:
        if binding_prop.server_id.reactive_changed.is_connected(on_server_changed):
            binding_prop.server_id.reactive_changed.disconnect(on_server_changed)
        if binding_prop.subscription_id.reactive_changed.is_connected(on_subscription_changed):
            binding_prop.subscription_id.reactive_changed.disconnect(on_subscription_changed)
        if binding_prop.tag_id.reactive_changed.is_connected(on_tag_id_changed):
            binding_prop.tag_id.reactive_changed.disconnect(on_tag_id_changed)
    )

    # ── User intent → binding_prop ────────────────────────────
    server_option.item_selected.connect(func(_index: int) -> void:
        var sid: String = server_option.get_item_metadata(server_option.selected)
        binding_prop.server_id.value       = sid
        binding_prop.subscription_id.value = ""
        binding_prop.tag_id.value          = ""
        if on_change.is_valid():
            on_change.call()
    )

    group_option.item_selected.connect(func(_index: int) -> void:
        var gid: String = group_option.get_item_metadata(group_option.selected)
        binding_prop.subscription_id.value = gid
        if on_change.is_valid():
            on_change.call()
    )

    browse_btn.pressed.connect(func() -> void:
        _panel.opc_ua_connection_dialog.browse(func(result: ReactiveOpcUaTagBinding) -> void:
            binding_prop.server_id.value       = result.server_id.value
            binding_prop.subscription_id.value = result.subscription_id.value
            binding_prop.tag_id.value          = result.tag_id.value
            if on_change.is_valid():
                on_change.call()
        )
    )

    return container

func _build_write_target_editor(
    target: ReactiveOpcUaWriteTarget,
    on_change: Callable = Callable()
) -> Control:
    var container: VBoxContainer = VBoxContainer.new()

    # ── Server row ─────────────────────────────────────────────
    var server_row    : HBoxContainer = HBoxContainer.new()
    var server_label  : Label = Label.new()
    var server_option : OptionButton = OptionButton.new()

    server_label.text                   = "Server"
    server_label.custom_minimum_size.x  = 60
    server_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    _populate_server_option(server_option)
    _select_option_by_metadata(server_option, target.server_id.value)

    server_row.add_child(server_label)
    server_row.add_child(server_option)
    container.add_child(server_row)

    # ── Node row (no subscription/group needed for writes) ────
    var node_row    : HBoxContainer = HBoxContainer.new()
    var node_label  : Label = Label.new()
    var node_edit   : LineEdit = LineEdit.new()
    var browse_btn  : Button = Button.new()

    node_label.text                  = "Node"
    node_label.custom_minimum_size.x = 60
    node_edit.text                   = target.node_id.value
    node_edit.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
    node_edit.editable               = false
    browse_btn.text                  = "Browse"

    node_row.add_child(node_label)
    node_row.add_child(node_edit)
    node_row.add_child(browse_btn)
    container.add_child(node_row)

    # ── Reactive → UI ──────────────────────────────────────────
    var on_server_changed: Callable = func(_v: ReactiveString) -> void:
        if is_instance_valid(server_option):
            _select_option_by_metadata(server_option, _v.value)

    var on_node_changed: Callable = func(_v: ReactiveString) -> void:
        if is_instance_valid(node_edit):
            node_edit.text = _v.value

    target.server_id.connect_self_changed(on_server_changed)
    target.node_id.connect_self_changed(on_node_changed)

    container.tree_exiting.connect(func() -> void:
        if target.server_id.reactive_changed.is_connected(on_server_changed):
            target.server_id.reactive_changed.disconnect(on_server_changed)
        if target.node_id.reactive_changed.is_connected(on_node_changed):
            target.node_id.reactive_changed.disconnect(on_node_changed)
    )

    # ── User intent → target ────────────────────────────────────
    server_option.item_selected.connect(func(_index: int) -> void:
        var sid: String = server_option.get_item_metadata(server_option.selected)
        target.server_id.value = sid
        target.node_id.value   = ""  # server changed — clear stale node
        if on_change.is_valid():
            on_change.call()
    )

    browse_btn.pressed.connect(func() -> void:
        var browse_nodes: BrowseNodes = _panel.get_node("/root/Main/Dialogs/BrowseNodes")
        browse_nodes.browse(
            AppState.current_project.opc_ua_servers.get_entry(target.server_id.value),
            func(result: OpcUaNodeId) -> void:
                target.node_id.value = result.to_tag_name()
        )
    )

    return container
