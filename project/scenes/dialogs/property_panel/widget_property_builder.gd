class_name WidgetPropertyBuilder
extends RefCounted

## Builds the property/event editor rows for a widget's inspector panel.
##
## Responsibilities:
##  - Routes rows into the "Properties" or "Events" tab depending on which
##    add_* method is called (widget scripts never specify a tab directly).
##  - Renders a per-row source dropdown (Constant / Script / OPC Tag /
##    OPC Tags per-zone) scoped to what the given field type supports.
##  - Provides array-aware editors (add/remove rows) for both constant
##    arrays and per-zone OPC tag arrays.
##
## NOTE: `_build_tag_binding_editor()` assumes AppState.current_project
## exposes `opc_ua_servers` / `subscriptions` / `tags` as dictionary-like
## containers with `.value` (Dictionary) and `.get_entry(id)`. Adjust the
## population logic below if your ReactiveProject API differs.

var _panel: Object  # exposes ._properties and ._events (Control containers)

func _init(panel: Object) -> void:
    _panel = panel

# ══════════════════════════════════════════════════════════════════════════
# PUBLIC API — called from widget scripts' build_properties()
# ══════════════════════════════════════════════════════════════════════════

func add_dynamic_field(prop: String, lbl: String, props: ReactiveDictionary) -> void:
    var field: ReactiveDynamicField = props.value[prop]
    var is_vector: bool = field.is_vector_field()

    var factories: Dictionary = {
        ReactiveDynamicField.SourceType.CONSTANT: (
            _constant_array_editor_factory(field) if is_vector
            else _constant_auto_editor_factory(field)
        ),
        ReactiveDynamicField.SourceType.SCRIPT: _script_editor_factory(field),
        ReactiveDynamicField.SourceType.OPC_TAG: _tag_editor_factory(field.tag_binding),
    }
    if is_vector:
        factories[ReactiveDynamicField.SourceType.OPC_TAG_ARRAY] = _tag_array_editor_factory(field)

    _build_field_row(lbl, field, factories, _panel._properties)

func add_constant_color_field(prop: String, lbl: String, props: ReactiveDictionary) -> void:
    var field: ReactiveConstantField = props.value[prop]
    var factories: Dictionary = {
        ReactiveConstantField.SourceType.CONSTANT: _constant_color_editor_factory(field),
        ReactiveConstantField.SourceType.SCRIPT: _script_editor_factory(field),
    }
    _build_field_row(lbl, field, factories, _panel._properties)

func add_constant_float_field(prop: String, lbl: String, props: ReactiveDictionary) -> void:
    var field: ReactiveConstantField = props.value[prop]
    var factories: Dictionary = {
        ReactiveConstantField.SourceType.CONSTANT: _constant_float_editor_factory(field),
        ReactiveConstantField.SourceType.SCRIPT: _script_editor_factory(field),
    }
    _build_field_row(lbl, field, factories, _panel._properties)

func add_constant_string_field(prop: String, lbl: String, props: ReactiveDictionary) -> void:
    var field: ReactiveConstantField = props.value[prop]
    var factories: Dictionary = {
        ReactiveConstantField.SourceType.CONSTANT: _constant_string_editor_factory(field),
        ReactiveConstantField.SourceType.SCRIPT: _script_editor_factory(field),
    }
    _build_field_row(lbl, field, factories, _panel._properties)

func add_constant_bool_field(prop: String, lbl: String, props: ReactiveDictionary) -> void:
    var field: ReactiveConstantField = props.value[prop]
    var factories: Dictionary = {
        ReactiveConstantField.SourceType.CONSTANT: _constant_bool_editor_factory(field),
        ReactiveConstantField.SourceType.SCRIPT: _script_editor_factory(field),
    }
    _build_field_row(lbl, field, factories, _panel._properties)

func add_constant_array_field(prop: String, lbl: String, props: ReactiveDictionary) -> void:
    var field: ReactiveConstantField = props.value[prop]
    var factories: Dictionary = {
        ReactiveConstantField.SourceType.CONSTANT: _constant_array_editor_factory(field),
        ReactiveConstantField.SourceType.SCRIPT: _script_editor_factory(field),
    }
    _build_field_row(lbl, field, factories, _panel._properties)

func add_action_field(prop: String, lbl: String, props: ReactiveDictionary) -> void:
    var action: ReactiveActionBinding = props.value[prop]

    var row: HBoxContainer = HBoxContainer.new()
    var label: Label = Label.new()
    label.text                  = lbl
    label.custom_minimum_size.x = 100
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(label)
    row.add_child(_build_action_binding_editor(action))

    _panel._events.add_child(row)
    _panel._events.add_child(HSeparator.new())

# ══════════════════════════════════════════════════════════════════════════
# GENERIC ROW SCAFFOLDING (label + source dropdown + swappable body)
# ══════════════════════════════════════════════════════════════════════════

func _build_field_row(
    label_text: String,
    field: Object,
    editor_factories: Dictionary,
    container: Control
) -> void:
    var wrapper: VBoxContainer = VBoxContainer.new()

    var header: HBoxContainer = HBoxContainer.new()
    var label: Label = Label.new()
    label.text                  = label_text
    label.custom_minimum_size.x = 100
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(label)
    header.add_child(_make_source_dropdown(field))

    var body: MarginContainer = MarginContainer.new()
    body.add_theme_constant_override("margin_left", 100)

    var rebuild_body: Callable = func() -> void:
        if not is_instance_valid(body):
            return
        for c in body.get_children():
            c.queue_free()
        var factory: Callable = editor_factories.get(field.source_type.value, Callable())
        if factory.is_valid():
            body.add_child(factory.call())

    var on_source_type_changed: Callable = func(_s) -> void: rebuild_body.call()
    field.source_type.connect_self_changed(on_source_type_changed)

    # Same cleanup pattern as the tag array row — prevents this row's
    # rebuild_body listener from leaking onto field.source_type across
    # repeated panel rebuilds.
    wrapper.tree_exiting.connect(func() -> void:
        if field.source_type.reactive_changed.is_connected(on_source_type_changed):
            field.source_type.reactive_changed.disconnect(on_source_type_changed)
    )

    rebuild_body.call()

    wrapper.add_child(header)
    wrapper.add_child(body)
    container.add_child(wrapper)
    container.add_child(HSeparator.new())

func _make_source_dropdown(field: Object) -> MenuButton:
    var btn: MenuButton = MenuButton.new()
    btn.text         = "⚙"
    btn.tooltip_text = "Change data source"

    var popup: PopupMenu = btn.get_popup()
    popup.clear()

    var is_dynamic: bool = field is ReactiveDynamicField
    var is_vector: bool = field.is_vector_field()

    var id_to_source_type: Dictionary = {}

    popup.add_item("Constant", 0)
    id_to_source_type[0] = field.SourceType.CONSTANT

    popup.add_item("Script", 1)
    id_to_source_type[1] = field.SourceType.SCRIPT

    if is_dynamic:
        popup.add_item("OPC Tag (native array)" if is_vector else "OPC Tag", 2)
        id_to_source_type[2] = field.SourceType.OPC_TAG

        if is_vector:
            popup.add_item("OPC Tags (per zone)", 3)
            id_to_source_type[3] = field.SourceType.OPC_TAG_ARRAY

    # Reflect current selection as the button's tooltip for quick reference
    btn.tooltip_text = "Data source: %s" % _source_type_display_name(field)

    popup.id_pressed.connect(func(id: int) -> void:
        field.source_type.value = id_to_source_type[id]
        btn.tooltip_text = "Data source: %s" % _source_type_display_name(field)
    )

    return btn

func _source_type_display_name(field: Object) -> String:
    var is_dynamic: bool = field is ReactiveDynamicField
    match field.source_type.value:
        0: return "Constant"
        1: return "Script"
        2: return "OPC Tag" if is_dynamic else "Unknown"
        3: return "OPC Tags (per zone)"
        _: return "Unknown"

# ══════════════════════════════════════════════════════════════════════════
# SCALAR CONSTANT EDITORS
# ══════════════════════════════════════════════════════════════════════════

func _constant_color_editor_factory(field: Object) -> Callable:
    return func() -> Control:
        var picker: ColorPickerButton = ColorPickerButton.new()
        picker.color                 = field.constant_value.value
        picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        picker.custom_minimum_size.y = 32
        picker.color_changed.connect(func(v: Color) -> void: field.constant_value.value = v)
        return picker

func _constant_float_editor_factory(field: Object) -> Callable:
    return func() -> Control:
        var spin: SpinBox = SpinBox.new()
        spin.min_value              = -1000000.0
        spin.max_value               = 1000000.0
        spin.step                    = 0.01
        spin.allow_greater           = true
        spin.allow_lesser            = true
        spin.value                   = float(field.constant_value.value)
        spin.size_flags_horizontal   = Control.SIZE_EXPAND_FILL
        spin.value_changed.connect(func(v: float) -> void: field.constant_value.value = v)
        return spin

func _constant_string_editor_factory(field: Object) -> Callable:
    return func() -> Control:
        var edit: LineEdit = LineEdit.new()
        edit.text                  = str(field.constant_value.value)
        edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        edit.text_changed.connect(func(v: String) -> void: field.constant_value.value = v)
        return edit

func _constant_bool_editor_factory(field: Object) -> Callable:
    return func() -> Control:
        var check: CheckBox = CheckBox.new()
        check.button_pressed = bool(field.constant_value.value)
        check.toggled.connect(func(v: bool) -> void: field.constant_value.value = v)
        return check

# Fallback used by add_dynamic_field for non-vector fields whose underlying
# type isn't known ahead of time — inspects the current resolved value to
# pick a reasonable editor. Prefer the explicit add_constant_*_field
# variants when the type is known statically.
func _constant_auto_editor_factory(field: Object) -> Callable:
    var v: Variant = field.constant_value.value
    if v is Color:
        return _constant_color_editor_factory(field)
    if v is bool:
        return _constant_bool_editor_factory(field)
    if v is String:
        return _constant_string_editor_factory(field)
    return _constant_float_editor_factory(field)

# ══════════════════════════════════════════════════════════════════════════
# ARRAY (CONSTANT) EDITOR — add/remove rows, per-value editing
# ══════════════════════════════════════════════════════════════════════════

func _constant_array_editor_factory(field: Object) -> Callable:
    return func() -> Control:
        var list: VBoxContainer = VBoxContainer.new()
        var rows: VBoxContainer = VBoxContainer.new()
        var arr: Array = Array(field.constant_value.value) if field.constant_value.value != null else []

        var rebuild: Callable
        rebuild = func() -> void:
            for c in rows.get_children():
                c.queue_free()
            for i in arr.size():
                rows.add_child(_build_constant_array_row(arr, i, field, rebuild))

        var footer: HBoxContainer = HBoxContainer.new()

        var add_btn: Button = Button.new()
        add_btn.text = "Add Zone"
        add_btn.pressed.connect(func() -> void:
            arr.append(0.0)
            field.constant_value.value = field.rebuild_typed_array(arr)
            rebuild.call()
        )

        var fill_btn: Button = Button.new()
        fill_btn.text = "Set All Equal"
        fill_btn.pressed.connect(func() -> void:
            for i in arr.size():
                arr[i] = 1.0
            field.constant_value.value = field.rebuild_typed_array(arr)
            rebuild.call()
        )

        var clear_btn: Button = Button.new()
        clear_btn.text = "Clear"
        clear_btn.pressed.connect(func() -> void:
            arr.clear()
            field.constant_value.value = field.rebuild_typed_array(arr)
            rebuild.call()
        )

        footer.add_child(add_btn)
        footer.add_child(fill_btn)
        footer.add_child(clear_btn)

        rebuild.call()
        list.add_child(rows)
        list.add_child(footer)
        return list


func _build_constant_array_row(arr: Array, index: int, field: Object, rebuild: Callable) -> Control:
    var row: HBoxContainer = HBoxContainer.new()

    var idx_label: Label = Label.new()
    idx_label.text                  = "Zone %d" % index
    idx_label.custom_minimum_size.x = 60
    row.add_child(idx_label)

    var spin: SpinBox = SpinBox.new()
    spin.min_value              = -1000000.0
    spin.max_value               = 1000000.0
    spin.step                    = 0.01
    spin.allow_greater           = true
    spin.allow_lesser            = true
    spin.value                   = float(arr[index])
    spin.size_flags_horizontal   = Control.SIZE_EXPAND_FILL
    spin.value_changed.connect(func(v: float) -> void:
        arr[index] = v
        field.constant_value.value = field.rebuild_typed_array(arr)
    )
    row.add_child(spin)

    var remove_btn: Button = Button.new()
    remove_btn.text = "✕"
    remove_btn.pressed.connect(func() -> void:
        arr.remove_at(index)
        field.constant_value.value = field.rebuild_typed_array(arr)
        rebuild.call()
    )
    row.add_child(remove_btn)

    return row

# ══════════════════════════════════════════════════════════════════════════
# SCRIPT EDITOR — shared by constant + dynamic, scalar + vector fields
# ══════════════════════════════════════════════════════════════════════════

func _script_editor_factory(field: Object) -> Callable:
    return func() -> Control:
        var wrapper: VBoxContainer = VBoxContainer.new()

        var edit: TextEdit = TextEdit.new()
        edit.custom_minimum_size = Vector2(220, 60)
        edit.text                = field.script_source.value
        edit.wrap_mode            = TextEdit.LINE_WRAPPING_BOUNDARY

        var status: Label = Label.new()
        status.modulate = Color.CRIMSON

        edit.text_changed.connect(func() -> void:
            field.script_source.value = edit.text
            status.text = "" if not field.resolved.value == null else "Script did not resolve — check syntax"
        )

        wrapper.add_child(edit)
        wrapper.add_child(status)
        return wrapper

# ══════════════════════════════════════════════════════════════════════════
# SINGLE OPC TAG EDITOR — used by scalar OPC_TAG and per-zone tag rows
# ══════════════════════════════════════════════════════════════════════════

func _tag_editor_factory(binding: ReactiveOpcUaTagBinding) -> Callable:
    return func() -> Control:
        return _build_tag_binding_editor(binding)

func _build_tag_binding_editor(binding: ReactiveOpcUaTagBinding) -> Control:
    var row: HBoxContainer = HBoxContainer.new()

    var server_select: OptionButton = OptionButton.new()
    var subscription_select: OptionButton = OptionButton.new()
    var tag_select: OptionButton = OptionButton.new()

    for o in [server_select, subscription_select, tag_select]:
        o.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    var project: ReactiveProject = AppState.current_project

    var populate_servers: Callable = func() -> void:
        server_select.clear()
        server_select.add_item("— Select Server —", -1)
        if project == null:
            return
        var ids: Array = project.opc_ua_servers.value.keys()
        for i in ids.size():
            server_select.add_item(str(ids[i]), i)
            server_select.set_item_metadata(i + 1, ids[i])
        _select_option_by_metadata(server_select, binding.server_id.value)

    var populate_subscriptions: Callable
    var populate_tags: Callable

    populate_subscriptions = func() -> void:
        subscription_select.clear()
        subscription_select.add_item("— Select Subscription —", -1)
        if project == null or binding.server_id.value.is_empty():
            return
        var server: ReactiveOpcUaServer = project.opc_ua_servers.get_entry(binding.server_id.value)
        if server == null:
            return
        var ids: Array = server.subscriptions.value.keys()
        for i in ids.size():
            subscription_select.add_item(str(ids[i]), i)
            subscription_select.set_item_metadata(i + 1, ids[i])
        _select_option_by_metadata(subscription_select, binding.subscription_id.value)

    populate_tags = func() -> void:
        tag_select.clear()
        tag_select.add_item("— Select Tag —", -1)
        if project == null or binding.server_id.value.is_empty() or binding.subscription_id.value.is_empty():
            return
        var server: ReactiveOpcUaServer = project.opc_ua_servers.get_entry(binding.server_id.value)
        if server == null:
            return
        var subscription: ReactiveOpcUaSubscription = server.subscriptions.get_entry(binding.subscription_id.value)
        if subscription == null:
            return
        var ids: Array = subscription.tags.value.keys()
        for i in ids.size():
            tag_select.add_item(str(ids[i]), i)
            tag_select.set_item_metadata(i + 1, ids[i])
        _select_option_by_metadata(tag_select, binding.tag_id.value)

    server_select.item_selected.connect(func(idx: int) -> void:
        var meta: Variant = server_select.get_item_metadata(idx)
        binding.server_id.value = str(meta) if meta != null else ""
        binding.subscription_id.value = ""
        binding.tag_id.value = ""
        populate_subscriptions.call()
        populate_tags.call()
    )

    subscription_select.item_selected.connect(func(idx: int) -> void:
        var meta: Variant = subscription_select.get_item_metadata(idx)
        binding.subscription_id.value = str(meta) if meta != null else ""
        binding.tag_id.value = ""
        populate_tags.call()
    )

    tag_select.item_selected.connect(func(idx: int) -> void:
        var meta: Variant = tag_select.get_item_metadata(idx)
        binding.tag_id.value = str(meta) if meta != null else ""
    )

    populate_servers.call()
    populate_subscriptions.call()
    populate_tags.call()

    row.add_child(server_select)
    row.add_child(subscription_select)
    row.add_child(tag_select)
    return row

func _select_option_by_metadata(option: OptionButton, target: String) -> void:
    if target.is_empty():
        option.select(0)
        return
    for i in option.item_count:
        if str(option.get_item_metadata(i)) == target:
            option.select(i)
            return
    option.select(0)

# ══════════════════════════════════════════════════════════════════════════
# PER-ZONE OPC TAG ARRAY EDITOR — "connect tags to array properties"
# ══════════════════════════════════════════════════════════════════════════

func _tag_array_editor_factory(field: ReactiveDynamicField) -> Callable:
    return func() -> Control:
        var list: VBoxContainer = VBoxContainer.new()
        var rows: VBoxContainer = VBoxContainer.new()
        var binding: ReactiveOpcUaTagArrayBinding = field.tag_array_binding

        var rebuild: Callable
        rebuild = func() -> void:
            # Defensive guard: if this row's controls were already freed
            # (e.g. the property panel rebuilt itself before this listener
            # was disconnected), silently no-op instead of crashing.
            if not is_instance_valid(rows):
                return
            for c in rows.get_children():
                c.queue_free()
            for i in binding.tag_bindings.value.size():
                rows.add_child(_build_tag_array_row(binding, i, rebuild))

        var on_tag_bindings_changed: Callable = func(_t) -> void:
            rebuild.call()
        binding.tag_bindings.connect_any_changed_self(on_tag_bindings_changed)

        # Ensure the listener above is disconnected the moment this row's
        # root control leaves the tree (e.g. torn down by a full property
        # panel rebuild). Without this, every rebuild leaks a listener
        # that still references this row's now-freed `rows` container,
        # causing "Lambda capture ... was freed" the next time a tag is
        # added or removed — since the stale listener remains connected
        # to the field's (long-lived) tag_array_binding.
        list.tree_exiting.connect(func() -> void:
            if binding.tag_bindings.reactive_changed.is_connected(on_tag_bindings_changed):
                binding.tag_bindings.reactive_changed.disconnect(on_tag_bindings_changed)
        )

        var add_btn: Button = Button.new()
        add_btn.text = "Add Zone Tag"
        add_btn.pressed.connect(func() -> void:
            binding.add_tag("", "", "")
        )

        rebuild.call()
        list.add_child(rows)
        list.add_child(add_btn)
        return list

func _build_tag_array_row(binding: ReactiveOpcUaTagArrayBinding, index: int, rebuild: Callable) -> Control:
    var row: HBoxContainer = HBoxContainer.new()

    var idx_label: Label = Label.new()
    idx_label.text                  = "Zone %d" % index
    idx_label.custom_minimum_size.x = 60
    row.add_child(idx_label)

    var picker: Control = _build_tag_binding_editor(binding.tag_bindings.value[index])
    picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(picker)

    var remove_btn: Button = Button.new()
    remove_btn.text = "✕"
    remove_btn.pressed.connect(func() -> void:
        binding.remove_tag(index)
        rebuild.call()
    )
    row.add_child(remove_btn)

    return row

# ══════════════════════════════════════════════════════════════════════════
# ACTION BINDING EDITOR (Events tab)
# ══════════════════════════════════════════════════════════════════════════

## NOTE: This assumes ReactiveActionBinding exposes an `action_type`
## (ReactiveInt) and a `script_source` (ReactiveString) similar in spirit to
## ReactiveDynamicField. Adjust field names below to match your actual
## ReactiveActionBinding implementation.
func _build_action_binding_editor(action: ReactiveActionBinding) -> Control:
    var wrapper: VBoxContainer = VBoxContainer.new()

    var edit: TextEdit = TextEdit.new()
    edit.custom_minimum_size = Vector2(220, 50)
    edit.text                = action.script_source.value if "script_source" in action else ""
    edit.placeholder_text     = "e.g. Widgets.get(\"detail_panel\").set_visible(true)"

    edit.text_changed.connect(func() -> void:
        if "script_source" in action:
            action.script_source.value = edit.text
    )

    wrapper.add_child(edit)
    return wrapper
