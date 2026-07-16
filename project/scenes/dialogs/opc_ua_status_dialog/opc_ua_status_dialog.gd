class_name OpcUaStatusDialog
extends BaseDialog

## When set, the view is filtered to this server only.
## An empty string means show all servers.
var focused_server_id: String = ""

@onready var _tree:   Tree  = %Tree
@onready var _timer:  Timer = %RefreshTimer
@onready var _status: Label = %StatusLabel
@onready var _title_label:  Label  = %TitleLabel
@onready var _show_all_button: Button = %ShowAllButton
@onready var _close_button: Button = %CloseButton

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
    _timer.timeout.connect(_refresh)

    # Toggle the paused state whenever visibility changes
    visibility_changed.connect(
        func() -> void:
        _timer.paused = not is_visible()
    )

    close_requested.connect(hide)
    _close_button.pressed.connect(hide)
    _show_all_button.pressed.connect(_on_show_all_pressed)
    _refresh()


# ── Public API ────────────────────────────────────────────────────────────────

## Scopes the status view to a single server.
## Call before popup_centered_ratio().
func focus_server(server_id: String) -> void:
    focused_server_id = server_id
    _refresh()


# ── Refresh ───────────────────────────────────────────────────────────────────

func _refresh() -> void:
    _tree.clear()
    var root: TreeItem = _tree.create_item()
    root.set_text(0, "OPC UA Servers")

    var manager: Node = get_node_or_null("/root/OpcUaManager")
    if manager == null:
        _status.text = "⚠ OpcUaManager autoload not found."
        return

    var connections: Dictionary = manager._connections
    if connections.is_empty():
        _status.text = "No servers registered."
        return

    var scope_ids: Array = connections.keys()
    if focused_server_id != "":
        scope_ids = scope_ids.filter(
            func(id: String) -> bool: return id == focused_server_id
        )
        _title_label.text     = "Status — %s" % focused_server_id
        _show_all_button.visible = true
    else:
        _title_label.text     = "Status — All Servers"
        _show_all_button.visible = false

    var server_count : int = 0
    var group_count  : int = 0
    var tag_count    : int = 0

    for server_id: String in scope_ids:
        var conn: OpcUaServerConnection = connections[server_id]
        server_count += 1

        # ── Server row ────────────────────────────────────────────────────────
        var server_item: TreeItem = _tree.create_item(root)
        server_item.set_text(
            0, "%s  %s" % ["🟢" if conn.is_server_connected() else "🔴", server_id]
        )

        var group_ids: Array = conn.get_group_ids()
        if group_ids.is_empty():
            var empty: TreeItem = _tree.create_item(server_item)
            empty.set_text(0, "  (no groups configured)")
            continue

        for group_id: String in group_ids:
            group_count += 1

            var group_cfg: OpcUaSubscriptionGroupConfig = \
                conn._group_configs.get(group_id, null)

            # ── Group row ─────────────────────────────────────────────────────
            var group_item: TreeItem = _tree.create_item(server_item)
            group_item.set_text(
                0,
                "📦  %s  (%s)" % [
                    group_cfg.display_name if group_cfg else group_id,
                    ("%.0f ms" % group_cfg.pub_interval_ms) if group_cfg else "unknown interval"
                ]
            )

            if group_cfg == null:
                var no_cfg: TreeItem = _tree.create_item(group_item)
                no_cfg.set_text(0, "  ⚠ group config missing")
                continue

            # ── Tag rows — matched by group_id exactly ────────────────────────
            var entries: Array = conn.registry.get_active_entries_for_group(group_id)
            if entries.is_empty():
                var no_tags: TreeItem = _tree.create_item(group_item)
                no_tags.set_text(0, "  (no active tags)")
                continue

            for entry: OpcUaTagRegistry.TagEntry in entries:
                tag_count += 1
                var tag_item: TreeItem = _tree.create_item(group_item)
                tag_item.set_text(
                    0,
                    "  %s  %s  →  %s" % [
                        "✅" if entry.quality_good else "⚠",
                        entry.tag_name,
                        str(entry.value)
                    ]
                )
                tag_item.set_tooltip_text(
                    0,
                    "Tag:          %s
Value:        %s
Quality Good: %s
Sampling:     %.0f ms
Interval:     %.0f ms
Mode:         %s" % [
                        entry.tag_name,
                        str(entry.value),
                        str(entry.quality_good),
                        entry.sampling_ms,
                        entry.pub_interval_ms,
                        OpcUaSubscriptionMode.Mode.keys()[entry.subscribe_mode]
                    ]
                )

    _status.text = "%s  |  Servers: %d  |  Groups: %d  |  Tags: %d" % [
        Time.get_time_string_from_system(), server_count, group_count, tag_count
    ]


func _on_show_all_pressed() -> void:
    focused_server_id = ""
    _refresh()
