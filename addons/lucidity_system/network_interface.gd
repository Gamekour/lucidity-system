class_name NetworkInterface extends Node

@export var ip_setting : TextEdit
var target_ip : String = "127.0.0.1"
var target_port : int = 6677

func _create_game() -> void: NetworkManager.create_game(target_port, target_ip)
func _join_game() -> void:
	NetworkManager.join_game(target_ip)
func _on_ip_setting_text_changed() -> void: target_ip = ip_setting.text
