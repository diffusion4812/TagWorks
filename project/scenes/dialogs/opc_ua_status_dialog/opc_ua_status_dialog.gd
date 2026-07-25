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

    # Refresh immediately on project switch, rather than waiting for the
    # next timer tick — avoids showing a stale project's servers/groups/tags.
    AppState.current_project.changed.connect(_refresh)

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

    var project: ReactiveProject = AppState.current_project.value
    if project == null:
        _status.text = "No project loaded."
        return

    var configured_servers: Array = project.opc_ua_servers.value
    if configured_servers.is_empty():
        _status.text = "No servers configured in project."
        return

    var manager_available: bool = is_instance_valid(OpcUaManager)
    if not manager_available:
        _status.text = "⚠ OpcUaManager autoload not found. Showing config only."

    var scope: Array = configured_servers
    if focused_server_id != "":
        scope = configured_servers.filter(
            func(s: ReactiveOpcUaServer) -> bool: return s.id.value == focused_server_id
        )
        _title_label.text        = "Status — %s" % focused_server_id
        _show_all_button.visible = true
    else:
        _title_label.text        = "Status — All Servers"
        _show_all_button.visible = false

    if scope.is_empty():
        _status.text = "No matching server found in project configuration."
        return

    var server_count : int = 0
    var group_count  : int = 0
    var tag_count    : int = 0

    for server: ReactiveOpcUaServer in scope:
        server_count += 1

        # Live status lookup — null means "configured but not connected"
        var conn: OpcUaServerConnection = null
        if manager_available:
            conn = OpcUaManager.get_connection(server.id.value)

        var is_connected: bool = conn != null and conn.is_server_connected()

        # ── Server row ────────────────────────────────────────────────────────
        var server_item: TreeItem = _tree.create_item(root)
        server_item.set_text(
            0,
            "%s  %s%s" % [
                "🟢" if is_connected else "🔴",
                server.display_name.value,
                "" if conn != null else "  (not connected)"
            ]
        )

        var configured_groups: Array = server.groups.value
        if configured_groups.is_empty():
            var empty: TreeItem = _tree.create_item(server_item)
            empty.set_text(0, "  (no groups configured)")
            continue

        for group_cfg: ReactiveOpcUaGroup in configured_groups:
            group_count += 1

            # Live group lookup — may be null if server/group not connected yet
            var live_group: OpcUaGroup = null
            if conn != null:
                live_group = conn.get_group(group_cfg.group_id)

            # ── Group row ─────────────────────────────────────────────────────
            var group_item: TreeItem = _tree.create_item(server_item)
            group_item.set_text(
                0,
                "📦  %s  (%.0f ms)%s" % [
                    group_cfg.display_name.value,
                    group_cfg.pub_interval_ms.value,
                    "" if live_group != null else "  ⚠ not active"
                ]
            )

            var configured_entries: Array = group_cfg.tags.value
            if configured_entries.is_empty():
                var no_tags: TreeItem = _tree.create_item(group_item)
                no_tags.set_text(0, "  (no tags configured)")
                continue

            for entry_cfg: ReactiveOpcUaTag in configured_entries:
                tag_count += 1

                # Live value lookup — fall back to config-only if not connected
                var live_entry: OpcUaGroup.TagEntry = null
                if live_group != null:
                    live_entry = live_group.get_entry(entry_cfg.node_id)

                var value_display: String = str(live_entry.value) if live_entry != null else "—"
                var is_active: bool       = live_entry.is_active if live_entry != null else false

                var tag_item: TreeItem = _tree.create_item(group_item)
                tag_item.set_text(
                    0,
                    "  %s  %s  →  %s" % [
                        "✅" if is_active else "⏸",
                        entry_cfg.display_name.value,
                        value_display
                    ]
                )
                tag_item.set_tooltip_text(
                    0,
					"Node ID:        %s
Display Name:   %s
Value:          %s
Active:         %s
Sampling:       %.0f ms
Deadband:       %.2f
Group Interval: %.0f ms
Connected:      %s" % [
                        entry_cfg.node_id.value,
                        entry_cfg.display_name.value,
                        value_display,
                        str(is_active),
                        entry_cfg.sampling_ms.value,
                        entry_cfg.deadband.value,
                        group_cfg.pub_interval_ms.value,
                        str(live_entry != null)
                    ]
                )

    _status.text = "%s  |  Servers: %d  |  Groups: %d  |  Tags: %d" % [
        Time.get_time_string_from_system(), server_count, group_count, tag_count
    ]


func _on_show_all_pressed() -> void:
    focused_server_id = ""
    _refresh()
