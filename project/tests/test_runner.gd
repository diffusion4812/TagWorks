# test/test_opc_ua_reactive_chain.gd
extends Node

@export var main_scene: PackedScene

func _ready() -> void:
    print("Starting instantiation...")
    var start_time = Time.get_ticks_msec()
    
    # Instantiate the root scene
    var instance = main_scene.instantiate()
    
    var end_time = Time.get_ticks_msec()
    print("Total instantiate time: ", end_time - start_time, " ms")
    
    # Optional: Test individual child branches if you suspect a specific sub-scene
    for child in instance.get_children():
        var child_start = Time.get_ticks_msec()
        # If they are heavy, separate them or test them alone
        print("Child node: ", child.name, " took time to evaluate")
