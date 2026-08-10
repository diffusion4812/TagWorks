extends Node

const SDK_API_VERSION: String  = "1"
const EXTENSIONS_DIR: String   = "user://extensions/"

signal extension_registered(descriptor: WidgetExtensionDescriptor)
signal extension_import_failed(reason: String)

var _descriptors: Dictionary = {} # id -> WidgetExtensionDescriptor

func get_descriptor(id: String) -> WidgetExtensionDescriptor:
    return _descriptors.get(id, null)

func _register_descriptor(descriptor: WidgetExtensionDescriptor) -> bool:
    if _descriptors.has(descriptor.id):
        return false
    _descriptors[descriptor.id] = descriptor
    extension_registered.emit(descriptor)
    return true

func import_extension_zip(zip_path: String) -> WidgetExtensionDescriptor:
    var reader: ZIPReader = ZIPReader.new()
    if reader.open(zip_path) != OK or not reader.file_exists("manifest.json"):
        extension_import_failed.emit("Invalid or unreadable extension package.")
        return null

    var manifest: Variant = JSON.parse_string(
        reader.read_file("manifest.json").get_string_from_utf8()
    )
    if typeof(manifest) != TYPE_DICTIONARY:
        extension_import_failed.emit("manifest.json is malformed.")
        reader.close(); return null

    var error: String = _validate_manifest(manifest)
    if error != "":
        extension_import_failed.emit(error)
        reader.close(); return null

    var id: String = manifest["id"]
    if _descriptors.has(id):
        extension_import_failed.emit("Extension '%s' is already registered." % id)
        reader.close(); return null

    var install_dir: String = EXTENSIONS_DIR.path_join(id)
    if _extract_all(reader, install_dir) != OK:
        extension_import_failed.emit("Failed to extract extension files.")
        reader.close(); return null
    reader.close()

    var descriptor: WidgetExtensionDescriptor = _build_descriptor(manifest, install_dir)
    if descriptor == null:
        extension_import_failed.emit("Failed to load entry scene for '%s'." % id)
        return null

    _run_plugin_hook(manifest, install_dir)

    _descriptors[id] = descriptor
    extension_registered.emit(descriptor)
    return descriptor

func _validate_manifest(manifest: Dictionary) -> String:
    for key: String in ["id", "name", "version", "api_version", "entry_scene"]:
        if not manifest.has(key) or String(manifest[key]).is_empty():
            return "manifest.json missing required field '%s'." % key
    if String(manifest["api_version"]) != SDK_API_VERSION:
        return "Incompatible api_version '%s' (host supports '%s')." \
            % [manifest["api_version"], SDK_API_VERSION]
    return ""

func _extract_all(reader: ZIPReader, install_dir: String) -> Error:
    DirAccess.make_dir_recursive_absolute(install_dir)
    for path: String in reader.get_files():
        if path.ends_with("/"):
            continue
        var dest: String = install_dir.path_join(path)
        DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
        var file: FileAccess = FileAccess.open(dest, FileAccess.WRITE)
        if file == null:
            return FileAccess.get_open_error()
        file.store_buffer(reader.read_file(path))
        file.close()
    return OK

func _build_descriptor(manifest: Dictionary, install_dir: String) -> WidgetExtensionDescriptor:
    var scene_path: String = install_dir.path_join(String(manifest["entry_scene"]))
    var content_scene: Resource = ResourceLoader.load(scene_path, "PackedScene")
    if not (content_scene is PackedScene):
        return null

    var probe: Node = (content_scene as PackedScene).instantiate()
    var valid: bool = probe is Control
    probe.queue_free()
    if not valid:
        return null

    var d: WidgetExtensionDescriptor = WidgetExtensionDescriptor.new()
    d.id            = manifest["id"]
    d.display_name  = manifest["name"]
    d.version       = manifest["version"]
    d.is_container  = manifest.get("is_container", false)
    d.content_scene = content_scene
    d.install_path  = install_dir
    d.icon          = _load_icon(install_dir, manifest.get("icon", "icon.svg"))
    return d

func _load_icon(install_dir: String, filename: String) -> Texture2D:
    var path: String = install_dir.path_join(filename)
    if not FileAccess.file_exists(path):
        return null
    var image: Image = Image.new()
    if image.load_svg_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
        return null
    return ImageTexture.create_from_image(image)

func _run_plugin_hook(manifest: Dictionary, install_dir: String) -> void:
    var plugin_script_name: String = manifest.get("plugin_script", "")
    if plugin_script_name.is_empty():
        return

    var script: Script = ResourceLoader.load(install_dir.path_join(plugin_script_name)) as Script
    if script == null:
        return

    var instance: WidgetExtensionPlugin = script.new() as WidgetExtensionPlugin
    if instance == null:
        return

    var context: WidgetExtensionContext = WidgetExtensionContext.new(
        self, manifest["id"], install_dir
    )
    instance.on_load(context)
