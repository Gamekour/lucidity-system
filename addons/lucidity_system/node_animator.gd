extends Node
class_name NodeAnimator

@export var target: Node3D
@export var origins: Array[Node3D] = []
@export var animation_index: int = 0
@export var animation_speed: float = 1.0
@export var active: bool = true
@export var local_to_global: bool = false

func _process(delta: float) -> void:
	if not active or not is_instance_valid(target):
		return
	if animation_index < 0 or animation_index >= origins.size():
		return
	var origin := origins[animation_index]
	if not is_instance_valid(origin):
		return
	if origin is PathFollow3D:
		(origin as PathFollow3D).progress += delta * animation_speed
	if origin is NodePathRotationSync:
		origin.path_follower.progress += delta * animation_speed
	target.global_transform = origin.global_transform

func set_animation_index(index: int) -> void:
	animation_index = index
