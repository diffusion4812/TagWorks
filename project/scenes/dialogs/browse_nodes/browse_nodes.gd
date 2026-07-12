class_name BrowseNodes
extends BaseDialog

## Emitted when the user confirms a selection.
signal node_id_selected(node_id: OpcUaNodeId)

# ── Scene references ──────────────────────────────────────────────────────────
@onready var search_bar:            LineEdit = %SearchBar
@onready var refresh_button:        Button   = %RefreshButton
@onready var tree:                  Tree     = %NodeTree
@onready var selected_label:        Label    = %SelectedLabel
@onready var confirm_button:        Button   = %ConfirmButton
@onready var close_button:          Button   = %CloseButton
@onready var _hide_internal_toggle: CheckBox = %HideInternalCheckBox

# ── State ─────────────────────────────────────────────────────────────────────
var _client:      GodotOpcUa = null
var _owns_client: bool       = false

var _browse_thread := Thread.new()
var _thread_busy   := false
var _thread_mutex  := Mutex.new()

## When true, internal OPC UA namespace-0 infrastructure nodes are hidden.
var _hide_internal_nodes: bool = true

# ── TreeItem metadata slot indices ────────────────────────────────────────────
const META_NODE_ID    := 0
const META_NODE_CLASS := 1
const PLACEHOLDER_TAG := "__placeholder__"

# ── String constants ──────────────────────────────────────────────────────────
const TEXT_PLACEHOLDER     := "…"
const TEXT_LOADING         := "Loading…"
const TEXT_NO_SELECTION    := "No node selected"
const TEXT_BROWSING_SERVER := "Browsing server…"

# ── Node classes that may contain children ────────────────────────────────────
const EXPANDABLE_CLASSES: Array[String] = [
    "Object", "View", "ObjectType",
    "VariableType", "DataType", "ReferenceType",
]

# ── Color per node class ──────────────────────────────────────────────────────
const CLASS_COLORS := {
    "Object":        Color(0.85, 0.85, 0.85),
    "Variable":      Color(0.45, 0.95, 0.45),
    "Method":        Color(0.45, 0.75, 1.00),
    "ObjectType":    Color(0.60, 0.60, 0.60),
    "VariableType":  Color(0.60, 0.60, 0.60),
    "DataType":      Color(0.60, 0.60, 0.60),
    "ReferenceType": Color(0.60, 0.60, 0.60),
    "View":          Color(0.85, 0.85, 0.85),
}

var _root_node := OpcUaNodeId.numeric(0, 84)

# =============================================================================
# Lifecycle
# =============================================================================

func _ready() -> void:
    confirm_button.disabled = true
    confirm_button.visible  = false

    tree.item_collapsed.connect(_on_item_collapsed)
    tree.item_selected.connect(_on_item_selected)
    tree.item_activated.connect(_on_item_activated)
    search_bar.text_changed.connect(_on_search_changed)
    _hide_internal_toggle.button_pressed = _hide_internal_nodes
    _hide_internal_toggle.toggled.connect(_on_hide_internal_toggled)
    refresh_button.pressed.connect(_refresh)
    confirm_button.pressed.connect(_on_confirm)
    close_button.pressed.connect(_on_close_pressed)

# =============================================================================
# Public API
# =============================================================================

## Opens the browser in browse-only mode using a live managed connection.
## The confirm button is hidden — no selection is returned.
func open_managed(manager: Node, server_id: String) -> void:
    _client               = manager.get_raw_client(server_id)
    _owns_client          = false
    confirm_button.visible = false
    _reset()
    popup_centered(Vector2i(700, 500))


## Opens the browser in browse-only mode using a temporary client.
## BrowseNodes takes ownership and disconnects the client on close.
func open_temporary(client: GodotOpcUa) -> void:
    _client               = client
    _owns_client          = true
    confirm_button.visible = false
    _reset()
    popup_centered(Vector2i(700, 500))


## Opens the browser in selection mode using a live managed connection.
## The confirm button is shown. on_selected is called once with the chosen
## OpcUaNodeId then automatically disconnected (CONNECT_ONE_SHOT).
##
## Example:
##   browse_nodes.request_node_id(OpcUaManager, server_id,
##       func(node_id: OpcUaNodeId) -> void:
##           my_edit.text = node_id.to_tag_name()
##   )
func request_node_id(
    manager:     Node,
    server_id:   String,
    on_selected: Callable
) -> void:
    _client               = manager.get_raw_client(server_id)
    _owns_client          = false
    confirm_button.visible = true
    _reset()
    node_id_selected.connect(on_selected, CONNECT_ONE_SHOT)
    popup_centered(Vector2i(700, 500))


## Opens the browser in selection mode using a temporary client.
## BrowseNodes takes ownership and disconnects the client on close.
func request_node_id_temporary(
    client:      GodotOpcUa,
    on_selected: Callable
) -> void:
    _client               = client
    _owns_client          = true
    confirm_button.visible = true
    _reset()
    node_id_selected.connect(on_selected, CONNECT_ONE_SHOT)
    popup_centered(Vector2i(700, 500))

# =============================================================================
# Refresh / root browse
# =============================================================================

## Resets UI state and begins a fresh browse from the root node.
func _reset() -> void:
    search_bar.text         = ""
    selected_label.text     = TEXT_NO_SELECTION
    confirm_button.disabled = true
    _refresh()


func _refresh() -> void:
    if _client == null:
        selected_label.text = "No client connected."
        return
    tree.clear()
    selected_label.text = TEXT_BROWSING_SERVER
    _browse_async(_root_node, _on_root_loaded)


func _on_root_loaded(results: Array) -> void:
    tree.clear()
    if results.is_empty():
        selected_label.text = "Server returned no nodes."
        return

    var invisible_root: TreeItem = tree.create_item()
    for entry: Dictionary in results:
        if not _is_internal_node(entry):        # ← filter applied here
            _add_tree_item(invisible_root, entry)

    selected_label.text     = TEXT_NO_SELECTION
    confirm_button.disabled = true

# =============================================================================
# Async browse helper
# =============================================================================

func _browse_async(node_id: OpcUaNodeId, on_complete: Callable) -> void:
    _thread_mutex.lock()
    var busy: bool = _thread_busy
    _thread_mutex.unlock()

    if busy:
        push_warning("BrowseNodes: browse already in progress; request ignored.")
        return

    if _browse_thread.is_started():
        _browse_thread.wait_to_finish()

    _set_busy(true)
    refresh_button.disabled = true

    _browse_thread.start(func() -> void:
        var results: Array = _client.browse_children(node_id)
        call_deferred("_browse_finished", on_complete, results)
    )


func _browse_finished(on_complete: Callable, results: Array) -> void:
    _set_busy(false)
    refresh_button.disabled = false
    on_complete.call(results)


func _set_busy(value: bool) -> void:
    _thread_mutex.lock()
    _thread_busy = value
    _thread_mutex.unlock()

# =============================================================================
# Tree item creation
# =============================================================================

func _add_tree_item(parent: TreeItem, entry: Dictionary) -> TreeItem:
    var node_name:  String = entry.get("name",       "")
    var node_id:    String = entry.get("node_id",    "")
    var node_class: String = entry.get("node_class", "Unknown")

    var item: TreeItem = tree.create_item(parent)
    item.set_text(0, node_name)
    item.set_metadata(META_NODE_ID,    node_id)
    item.set_tooltip_text(0, node_id)
    item.collapsed = true

    var color: Color = CLASS_COLORS.get(node_class, Color(0.70, 0.70, 0.70))
    item.set_custom_color(0, color)

    if node_class in EXPANDABLE_CLASSES:
        var ph: TreeItem = tree.create_item(item)
        ph.set_text(0, TEXT_PLACEHOLDER)
        ph.set_metadata(META_NODE_ID, PLACEHOLDER_TAG)
        ph.set_selectable(0, false)
        ph.set_custom_color(0, Color(0.45, 0.45, 0.45))

    return item

# =============================================================================
# Lazy child population
# =============================================================================

func _populate_children(target_item: TreeItem, results: Array) -> void:
    if not is_instance_valid(target_item):
        return

    var ph: TreeItem = target_item.get_first_child()
    if ph != null and ph.get_metadata(META_NODE_ID) == PLACEHOLDER_TAG:
        ph.free()

    var visible_count := 0
    for entry: Dictionary in results:
        if not _is_internal_node(entry):        # ← filter applied here
            _add_tree_item(target_item, entry)
            visible_count += 1

    if visible_count == 0:
        target_item.collapsed = true
        return

    if not search_bar.text.is_empty():
        _apply_search_filter(search_bar.text.to_lower())

# =============================================================================
# Helpers
# =============================================================================

func _parse_node_id(node_id_str: String) -> OpcUaNodeId:
    var node_id: OpcUaNodeId = OpcUaNodeId.parse(node_id_str)
    if node_id == null:
        push_warning("BrowseNodes: could not parse node ID: '%s'." % node_id_str)
    return node_id


## Cleans up a pending one-shot connection on the node_id_selected signal.
## Called when the user cancels without confirming a selection.
func _clear_pending_selection_callback() -> void:
    var connections := node_id_selected.get_connections()
    if connections.size() > 0:
        node_id_selected.disconnect(connections[0]["callable"])


func _close() -> void:
    if _owns_client and _client != null:
        _client.disconnect_server()
    _client      = null
    _owns_client = false
    hide()

# =============================================================================
# Tree signals
# =============================================================================

func _on_item_collapsed(item: TreeItem) -> void:
    if item.collapsed:
        return

    var first_child: TreeItem = item.get_first_child()
    if first_child == null:
        return
    if first_child.get_metadata(META_NODE_ID) != PLACEHOLDER_TAG:
        return

    var node_id_str: String  = item.get_metadata(META_NODE_ID)
    var node_id: OpcUaNodeId = _parse_node_id(node_id_str)
    if node_id == null:
        return

    first_child.set_text(0, TEXT_LOADING)
    selected_label.text = "Browsing %s…" % node_id_str

    _browse_async(node_id, func(results: Array) -> void:
        _populate_children(item, results)
        selected_label.text = TEXT_NO_SELECTION
    )


func _on_item_selected() -> void:
    var item: TreeItem = tree.get_selected()
    if item == null:
        return

    var node_id_str: String = item.get_metadata(META_NODE_ID)
    if node_id_str == PLACEHOLDER_TAG:
        confirm_button.disabled = true
        return

    selected_label.text     = node_id_str
    confirm_button.disabled = false


func _on_item_activated() -> void:
    if not confirm_button.disabled and confirm_button.visible:
        _on_confirm()


func _on_confirm() -> void:
    var item: TreeItem = tree.get_selected()
    if item == null:
        return

    var node_id_str: String  = item.get_metadata(META_NODE_ID)
    var node_id: OpcUaNodeId = _parse_node_id(node_id_str)
    if node_id == null:
        return

    node_id_selected.emit(node_id)
    _close()


func _on_close_pressed() -> void:
    _clear_pending_selection_callback()
    _close()

# =============================================================================
# Search / filter
# =============================================================================

func _on_search_changed(text: String) -> void:
    _apply_search_filter(text.to_lower())


func _apply_search_filter(search: String) -> void:
    var root: TreeItem = tree.get_root()
    if root == null:
        return
    var child: TreeItem = root.get_first_child()
    while child != null:
        _filter_subtree(child, search)
        child = child.get_next()


func _filter_subtree(item: TreeItem, search: String) -> bool:
    if item.get_metadata(META_NODE_ID) == PLACEHOLDER_TAG:
        item.visible = true
        return false

    var name_matches: bool = search.is_empty() or \
        item.get_text(0).to_lower().contains(search)

    var child_matches := false
    var child: TreeItem = item.get_first_child()
    while child != null:
        if _filter_subtree(child, search):
            child_matches = true
        child = child.get_next()

    item.visible = name_matches or child_matches
    return item.visible

func _on_hide_internal_toggled(pressed: bool) -> void:
    _hide_internal_nodes = pressed
    _refresh()
    
# =============================================================================
# Filter Predicate
# =============================================================================

## Returns true if the entry should be excluded from the tree.
func _is_internal_node(entry: Dictionary) -> bool:
    if not _hide_internal_nodes:
        return false

    var node_id_str: String = entry.get("node_id",    "")
    var node_class:  String = entry.get("node_class", "")
    var node_name:   String = entry.get("name",       "")

    # Always filter pure type-definition nodes — users bind to instances
    const TYPE_CLASSES: Array[String] = [
        "ObjectType", "VariableType", "DataType", "ReferenceType"
    ]
    if node_class in TYPE_CLASSES:
        return true

    # Filter namespace-0 infrastructure
    if node_id_str.begins_with("ns=0;") or node_id_str.begins_with("i="):
        # Keep Variables in ns=0 — some servers expose useful data there
        if node_class != "Variable":
            return true

        # Filter low numeric IDs — OPC UA reserved range (0–999)
        var numeric_part := node_id_str.trim_prefix("ns=0;i=").trim_prefix("i=")
        if numeric_part.is_valid_int() and int(numeric_part) < 1000:
            return true

    # Filter well-known administrative folder names at any namespace
    const INTERNAL_NAMES: Array[String] = [
        "Server", "Aliases", "Diagnostics",
        "ServerDiagnostics", "SessionsDiagnosticsSummary",
        "VendorServerInfo", "ServerRedundancy",
        "Namespaces", "StaticData",
    ]
    if node_name in INTERNAL_NAMES:
        return true

    return false

# =============================================================================
# Cleanup
# =============================================================================

func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        if _browse_thread.is_started():
            _browse_thread.wait_to_finish()
