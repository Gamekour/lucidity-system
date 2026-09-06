@tool
extends EditorPlugin

func _enable_plugin() -> void:
	_add_input("move_forward", [KEY_W])
	_add_input("move_back", [KEY_S])
	_add_input("move_left", [KEY_A])
	_add_input("move_right", [KEY_D])
	_add_input("jump", [KEY_SPACE])
	_add_input("crouch", [KEY_C])
	_add_input("sprint", [KEY_SHIFT])
	_add_input("crawl", [KEY_Z])
	_add_input("grab", [], MOUSE_BUTTON_RIGHT)
	_add_input("attach", [KEY_Q])
	_add_input("drop", [KEY_G])
	_add_input("interact", [KEY_F])
	_add_input("respawn", [KEY_R])
	_add_input("hotbar_direct", [KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9])
	pass

func _add_input(name : String, keys : Array[int], mouse_button : int = -1):
	if (ProjectSettings.has_setting('input/' + name)): return
	
	var inputs : Array[InputEvent] = []
	
	for key in keys:
		var input_key = InputEventKey.new()
		input_key.physical_keycode = key
		inputs.append(input_key)
	var input_mouse = InputEventMouseButton.new()
	if (mouse_button != -1):
		input_mouse.button_index = mouse_button
		inputs.append(input_mouse)

	var input = {
		"deadzone": 0.5,
		"events": inputs
	}
	ProjectSettings.set_setting('input/' + name, input)
	ProjectSettings.save()

func _disable_plugin() -> void:
	# Remove autoloads here.
	pass

func _enter_tree() -> void:
	var plugin_repos:Dictionary = ProjectSettings.get_setting("plugin_updater/plugins", {})
	plugin_repos[get_plugin_path()] = "https://github.com/Gamekour/lucidity-system"
	ProjectSettings.set_setting("plugin_updater/plugins", plugin_repos)
	ProjectSettings.save()

func _exit_tree() -> void:
	var plugin_repos:Dictionary = ProjectSettings.get_setting("plugin_updater/plugins", {})
	plugin_repos.erase(get_plugin_path())
	ProjectSettings.set_setting("plugin_updater/plugins", plugin_repos)
	ProjectSettings.save()
	
func get_plugin_path() -> String:
	return get_script().resource_path.get_base_dir() + "/"
