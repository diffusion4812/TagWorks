# resources/opc_ua_config_registry.gd
class_name OpcUaConfigRegistry
extends RefCounted

signal configs_changed()

var _configs: Dictionary = {}    # id -> OpcUaServerConfig

# ── Mutation ──────────────────────────────────────────────────────────────────

func add_config(cfg: OpcUaServerConfig) -> void:
    assert(cfg.id != "", "OpcUaServerConfig must have a non-empty id")
    _configs[cfg.id] = cfg
    configs_changed.emit()

func remove_config(id: String) -> void:
    if _configs.erase(id):
        configs_changed.emit()

func get_config(id: String) -> OpcUaServerConfig:
    return _configs.get(id, null)

func get_all_configs() -> Array[OpcUaServerConfig]:
    var result: Array[OpcUaServerConfig] = []
    for cfg in _configs.values():
        result.append(cfg)
    return result

## Marks a config as dirty and emits configs_changed without replacing the
## config object. Use this after mutating groups on an existing config.
func mark_dirty(id: String) -> void:
    assert(_configs.has(id), "Cannot mark unknown config id as dirty: " + id)
    configs_changed.emit()

## Convenience wrapper: adds or updates a group on an existing config and
## emits configs_changed. Fails silently if the config id is not registered.
func update_group(config_id: String, group: OpcUaSubscriptionGroupConfig) -> void:
    var cfg: OpcUaServerConfig = _configs.get(config_id, null)
    if cfg == null:
        push_warning("OpcUaConfigRegistry.update_group: unknown config id '%s'" % config_id)
        return
    cfg.add_or_update_group(group)
    configs_changed.emit()

## Convenience wrapper: removes a group from an existing config and
## emits configs_changed. Fails silently if the config id is not registered.
func remove_group(config_id: String, group_id: String) -> void:
    var cfg: OpcUaServerConfig = _configs.get(config_id, null)
    if cfg == null:
        push_warning("OpcUaConfigRegistry.remove_group: unknown config id '%s'" % config_id)
        return
    cfg.remove_group(group_id)
    configs_changed.emit()

# ── Serialisation ─────────────────────────────────────────────────────────────

func serialize() -> Array:
    var result: Array = []
    for cfg: OpcUaServerConfig in _configs.values():
        result.append(cfg.serialize())
    return result

func deserialize(data: Array) -> void:
    _configs.clear()
    for entry: Variant in data:
        if not entry is Dictionary:
            continue
        var cfg := OpcUaServerConfig.deserialize(entry)
        if cfg.id != "":
            _configs[cfg.id] = cfg
    configs_changed.emit()
