@tool
extends EditorPlugin


func _enable_plugin() -> void:
	# Add autoloads here.
	pass


func _disable_plugin() -> void:
	# Remove autoloads here.
	pass

func _enter_tree() -> void:
	var plugin_repos:Dictionary = ProjectSettings.get_setting("plugin_updater/plugins", {})
	plugin_repos[get_plugin_path()] = "https://github.com/{USERNAME}/{REPO_NAME}"
	ProjectSettings.set_setting("plugin_updater/plugins", plugin_repos)
	ProjectSettings.save()

func _exit_tree() -> void:
	var plugin_repos:Dictionary = ProjectSettings.get_setting("plugin_updater/plugins", {})
	plugin_repos.erase(get_plugin_path())
	ProjectSettings.set_setting("plugin_updater/plugins", plugin_repos)
	ProjectSettings.save()
	
func get_plugin_path() -> String:
	return get_script().resource_path.get_base_dir() + "/"
