class_name ReactiveVariantCodec
extends RefCounted

## Converts complex Godot Variant types (Color, Vector2, Vector3, etc.) to
## and from plain, JSON-safe Dictionary/primitive representations, so saved
## project files remain human-readable/editable and round-trip correctly
## through serializers that don't natively support these types (e.g. JSON).
##
## Primitives (int, float, bool, String, null) pass through unchanged.
## Complex types are tagged with "__type" so decode_variant() can restore
## the exact original type rather than guessing from shape.

static func encode_variant(v: Variant) -> Variant:
    match typeof(v):
        TYPE_COLOR:
            var c: Color = v
            return { "__type": "Color", "value": c.to_html(true) }

        TYPE_VECTOR2:
            var vec: Vector2 = v
            return { "__type": "Vector2", "x": vec.x, "y": vec.y }

        TYPE_VECTOR2I:
            var vec: Vector2i = v
            return { "__type": "Vector2i", "x": vec.x, "y": vec.y }

        TYPE_VECTOR3:
            var vec: Vector3 = v
            return { "__type": "Vector3", "x": vec.x, "y": vec.y, "z": vec.z }

        TYPE_VECTOR3I:
            var vec: Vector3i = v
            return { "__type": "Vector3i", "x": vec.x, "y": vec.y, "z": vec.z }

        TYPE_RECT2:
            var r: Rect2 = v
            return { "__type": "Rect2", "x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y }

        TYPE_DICTIONARY:
            # Recurse so nested Dictionaries containing complex types
            # (rare, but possible via SCRIPT results) still encode safely.
            var out: Dictionary = {}
            for k in (v as Dictionary).keys():
                out[str(k)] = encode_variant((v as Dictionary)[k])
            return out

        _:
            # int, float, bool, String, null — already JSON-safe as-is.
            return v

static func decode_variant(v: Variant) -> Variant:
    if v is Dictionary and (v as Dictionary).has("__type"):
        var d: Dictionary = v as Dictionary
        match d["__type"]:
            "Color":
                return Color(d["value"])
            "Vector2":
                return Vector2(d["x"], d["y"])
            "Vector2i":
                return Vector2i(d["x"], d["y"])
            "Vector3":
                return Vector3(d["x"], d["y"], d["z"])
            "Vector3i":
                return Vector3i(d["x"], d["y"], d["z"])
            "Rect2":
                return Rect2(d["x"], d["y"], d["w"], d["h"])
            _:
                return v  # unknown tag — return as-is rather than throw

    if v is Dictionary:
        # Plain nested dictionary (no __type tag) — decode recursively.
        var out: Dictionary = {}
        for k in (v as Dictionary).keys():
            out[k] = decode_variant((v as Dictionary)[k])
        return out

    return v
