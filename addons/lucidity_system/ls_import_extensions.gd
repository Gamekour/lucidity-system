@tool
extends EditorScenePostImport

func _post_import(scene: Node) -> Object:
	print("Importing scene: ", scene.name)
	
	for node in scene.get_children():
		if (node.name.ends_with("-conv_no_wrap")):
			var mesh := node as MeshInstance3D
			mesh.create_convex_collision()
			var static_body = mesh.find_child(node.name + "_col")
			var cshape := mesh.find_child("CollisionShape3D")
			cshape.owner = null
			static_body.remove_child(cshape)
			scene.add_child(cshape)
			static_body.queue_free()
			cshape.owner = scene
	return scene 
