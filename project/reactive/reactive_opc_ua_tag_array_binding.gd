class_name ReactiveOpcUaTagArrayBinding
extends Reactive

# Ordered list of individual tag bindings — index order defines position
# in the resulting Variant array. Each tag keeps its native OPC data type
# (float, int, bool, string, etc.) — no coercion happens here.
var tag_bindings: ReactiveArray  # ReactiveArray[ReactiveOpcUaTagBinding]

func _init(initial_owner: Reactive = null, label: String = "ReactiveOpcUaTagArrayBinding") -> void:
    super._init(initial_owner, label)
    tag_bindings = ReactiveArray.new([], self, "tag_bindings")

func add_tag(server_id: String, subscription_id: String, tag_id: String) -> void:
    var binding: ReactiveOpcUaTagBinding = ReactiveOpcUaTagBinding.new({}, tag_bindings, str(tag_bindings.value.size()))
    binding.server_id.value = server_id
    binding.subscription_id.value = subscription_id
    binding.tag_id.value = tag_id
    tag_bindings.value.append(binding)
    tag_bindings.manually_emit()

func remove_tag(index: int) -> void:
    if index >= 0 and index < tag_bindings.value.size():
        tag_bindings.value.remove_at(index)
        tag_bindings.manually_emit()

func serialize() -> Variant:
    var out: Array = []
    for b in tag_bindings.value:
        out.append((b as ReactiveOpcUaTagBinding).serialize())
    return out

func deserialize(data: Variant) -> void:
    tag_bindings.value.clear()
    for d in (data as Array):
        var b: ReactiveOpcUaTagBinding = ReactiveOpcUaTagBinding.new({}, tag_bindings, "0")
        b.deserialize(d)
        tag_bindings.value.append(b)
    tag_bindings.manually_emit()
