# app_settings.gd — Autoload singleton
extends Node

const SETTINGS_PATH: String = "user://settings.cfg"

var preferred_locale: ReactiveString = ReactiveString.new("")

func _ready() -> void:
    _load()
    if not preferred_locale.value.is_empty():
        TranslationServer.set_locale(preferred_locale.value)
    else:
        _apply_os_default_locale()

    # Persist automatically whenever the value changes, from anywhere in the app.
    preferred_locale.connect_self_changed(
        func(_origin: Reactive) -> void:
            _save()
    )


func _apply_os_default_locale() -> void:
    var os_locale: String = OS.get_locale_language()
    if TranslationServer.get_loaded_locales().has(os_locale):
        TranslationServer.set_locale(os_locale)
        preferred_locale.value = os_locale


func set_locale(locale: String) -> void:
    TranslationServer.set_locale(locale)
    preferred_locale.value = locale  # triggers _save() via the binding above


func _load() -> void:
    var config: ConfigFile = ConfigFile.new()
    if config.load(SETTINGS_PATH) == OK:
        preferred_locale.value = config.get_value("app", "locale", "")


func _save() -> void:
    var config: ConfigFile = ConfigFile.new()
    config.set_value("app", "locale", preferred_locale.value)
    config.save(SETTINGS_PATH)
