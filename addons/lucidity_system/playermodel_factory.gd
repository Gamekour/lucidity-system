extends RefCounted
class_name PlayerModelFactory

## Minimal set of bone names required for a valid Godot humanoid retarget.
## (Subset of SkeletonProfileHumanoid's bone list - fingers/twist bones are optional.)
const REQUIRED_HUMANOID_BONES : PackedStringArray = [
	"Hips", "Spine", "Chest", "Head",
	"LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot",
]

const HIP_BONE_NAME : String = "Hips"


## Instantiates model_scene, validates + rebuilds it into a PlayerModel, and
## parents the result under `parent`. Returns null (and pushes an error) on failure.
static func spawn_player_model(model_scene: PackedScene, parent: Node) -> PlayerModel:
	if model_scene == null:
		push_error("PlayerModelFactory: model_scene is null.")
		return null

	var instance := model_scene.instantiate()
	if instance == null:
		push_error("PlayerModelFactory: Failed to instantiate model_scene '%s'." % model_scene.resource_path)
		return null

	var skeleton := _find_skeleton(instance)
	if skeleton == null:
		push_error("PlayerModelFactory: No Skeleton3D found anywhere in '%s'." % model_scene.resource_path)
		instance.free()
		return null

	if not _is_humanoid_retargeted(skeleton):
		push_error(
			"PlayerModelFactory: Skeleton '%s' in '%s' is not retargeted to Godot's built-in humanoid bone map. "
			% [skeleton.name, model_scene.resource_path]
			+ "Retarget it (Skeleton3D > 'Set Bone Mapping' / Humanoid profile) before use."
		)
		instance.free()
		return null

	# Record the hip bone's position (relative to the skeleton) before we touch the hierarchy.
	var hip_idx := skeleton.find_bone(HIP_BONE_NAME)
	var hip_local_pos := skeleton.get_bone_global_pose(hip_idx).origin

	# Fold every ancestor's transform into the skeleton's own transform, warning about
	# (and preserving positioning for) any ancestor that isn't a pure empty wrapper.
	var baked_transform := _strip_empty_parents(skeleton, instance)

	# Shift on the Y axis so the hip bone ends up sitting at the node's own origin.
	baked_transform.origin.y -= hip_local_pos.y
	baked_transform.basis = Basis.IDENTITY.rotated(Vector3.UP, PI)
	skeleton.transform = baked_transform

	# Attach the PlayerModel script directly to the existing Skeleton3D node. This is the
	# same node instance, so all bone data (rest poses, bone tree, skinned meshes) carries
	# over untouched - there's no need to rebuild the skeleton from scratch.
	skeleton.set_script(PlayerModel)
	var player_model := skeleton as PlayerModel

	skeleton.get_parent().remove_child(skeleton)
	parent.add_child(player_model)
	player_model.owner = parent.owner if parent.owner else parent
	_set_owner_recursive(player_model, player_model.owner)

	if instance != skeleton:
		instance.free()

	return player_model


## Depth-first search for the first Skeleton3D in the hierarchy.
static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


## Checks the skeleton contains every bone name Godot's humanoid profile requires.
static func _is_humanoid_retargeted(skeleton: Skeleton3D) -> bool:
	for bone_name in REQUIRED_HUMANOID_BONES:
		if skeleton.find_bone(bone_name) == -1:
			push_warning("PlayerModelFactory: missing required humanoid bone '%s'." % bone_name)
			return false
	return true


## Walks up from `skeleton` to `scene_root`, folding each ancestor's local transform
## into the result. Warns (but still bakes the transform) if an ancestor isn't a pure
## single-child wrapper, since its other children will be discarded with the scene root.
static func _strip_empty_parents(skeleton: Skeleton3D, scene_root: Node) -> Transform3D:
	var combined := Transform3D.IDENTITY
	var node : Node = skeleton

	while node != null:
		if node is Node3D:
			combined = (node as Node3D).transform * combined

		if node == scene_root:
			break

		var parent := node.get_parent()
		if parent == null:
			break

		if parent.get_child_count() != 1:
			push_warning(
				"PlayerModelFactory: parent node '%s' has extra children besides the rig chain; "
				% parent.name + "they will be discarded when the wrapper is stripped."
			)
		if parent.get_script() != null:
			push_warning("PlayerModelFactory: stripped parent node '%s' had a script attached to it." % parent.name)

		node = parent

	return combined


static func _set_owner_recursive(node: Node, owner: Node) -> void:
	if owner == null:
		return
	for child in node.get_children():
		child.owner = owner
		_set_owner_recursive(child, owner)
