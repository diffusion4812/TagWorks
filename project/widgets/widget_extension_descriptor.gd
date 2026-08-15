# widget_extension_descriptor.gd
class_name WidgetExtensionDescriptor
extends RefCounted

var id: String
var display_name: String
var version: String
var is_container: bool
var icon: Texture2D
var content_scene: PackedScene
var install_path: String
var host_scene: PackedScene
