tool
extends EditorImportPlugin


func get_importer_name():
	return "import3d.coa"

func get_visible_name():
	return "Cutout Animation Tools 3D"

func get_recognized_extensions():
	return ["json"]

func get_save_extension():
	return "scn"

func get_resource_type():
	return "PackedScene"

func get_preset_count():
	return 0

func get_preset_name(preset):
	return "Unknown"

# Have to return at least one option?!
func get_import_options(preset):
	return [
			{
				"name": "option",
				"default_value": true
			},
	]

func get_option_visibility(option, options):
	return false


func import(source_file, save_path, options, r_platform_variants, r_gen_files):
	var json = File.new()
	var json_data

	if json.file_exists(source_file):

		json.open(source_file, File.READ)
		json_data = JSON.parse(json.get_as_text()).result
		json.close()

	var dir = Directory.new()
	dir.open("res://")

	var scene = Spatial.new()
	scene.set_name(json_data["name"] + "3d")

	var nodes = {}
	create_nodes(source_file, json_data["nodes"], scene, scene, false, nodes)

	### import animations and log
	if "animations" in json_data:
		import_animations(json_data["animations"], scene, nodes)

	var packed_scene = PackedScene.new()
	packed_scene.pack(scene)
	return ResourceSaver.save("%s.%s" % [save_path, get_save_extension()], packed_scene)


### recursive function that looks up if a node has BONE nodes as children
func has_bone_child(node):
	if "children" in node:
		for item in node["children"]:
			if item["type"] == "BONE":
				return true
			if "children" in item:
				has_bone_child(item)
	return false



### function to import animations -> this will create an AnimationPlayer Node and generate all animations with its tracks and values
func import_animations(animations, root, nodes):
	var anim_player = AnimationPlayer.new()
	root.add_child(anim_player)
	anim_player.set_owner(root)
	anim_player.set_name("AnimationPlayer")

	for anim in animations:
		anim_player.clear_caches()
		var anim_data = Animation.new()
		anim_data.set_loop(true)
		anim_data.set_length(anim["length"])
		for key in anim["keyframes"]:
			var track = anim["keyframes"][key]
			var channel = key.split(":")[-1]
			match channel:
				"transform/pos":
					key = key.left(key.length() - channel.length()) + "translation"
				"transform/rot":
					key = key.left(key.length() - channel.length()) + "rotation_degrees"
				"transform/scale":
					key = key.left(key.length() - channel.length()) + "scale"
				"z/z":
					key = key.left(key.length() - channel.length()) + "z_index"
			
			key = key.replace(".", "_")
			var node_path = key.split(":")[0]
			var idx = anim_data.add_track(Animation.TYPE_VALUE)
			anim_data.track_set_path(idx,key)
			for time in track:
				var value = track[time]["value"]
				if typeof(value) == TYPE_ARRAY:
					if key.find("trans") != -1:
						var node = nodes[node_path]
						anim_data.track_insert_key(idx,float(time),Vector3(value[0]*0.01, -value[1]*0.01, node["z"]*0.01))
					elif key.find("scale") != -1:
						anim_data.track_insert_key(idx,float(time),Vector3(value[0], value[1], 1))
					elif key.find("modulate") != -1:
						anim_data.track_insert_key(idx,float(time),Color(value[0], value[1], value[2], 1.0))
				elif typeof(value) == TYPE_REAL:
					if key.find("rot") != -1:
						anim_data.track_insert_key(idx,float(time),Vector3(0, 0, rad2deg(value)))
					else:
						anim_data.track_insert_key(idx,float(time),value)
				else:
					anim_data.track_insert_key(idx,float(time),value)

				if key.find(":frame") != -1 or key.find(":z/z") != -1:
					anim_data.track_set_interpolation_type(idx, Animation.INTERPOLATION_NEAREST)
				else:
					anim_data.track_set_interpolation_type(idx, Animation.INTERPOLATION_LINEAR)

				if key.find(":visible") != -1:
					anim_data.value_track_set_update_mode(idx, 1)

		anim_player.add_animation(anim["name"],anim_data)
		anim_player.set_meta(anim["name"],true)
		anim_player.clear_caches()

### this function generates the complete node structure that is stored in a json file. Generates SPRITE and BONE nodes.
func create_nodes(source_file, nodes, root, parent, copy_images=true, nodesDict={},i=0):
	for node in nodes:
		node["name"] = node["name"].replace(".", "_")
		var pos = Vector3(node["position"][0]*0.01, -node["position"][1]*0.01, node["z"]*0.01)
		
		#node["position"][0] = pos.x
		#node["position"][1] = pos.y
		#print("name: " + node["name"] + ", pos0: " + str(pos.y))

		var new_node
		var offset = Vector3(0,0,0)
		if "offset" in node:
			offset = Vector3(node["offset"][0],node["offset"][1], 0)
		if node["type"] == "BONE":
			new_node = Spatial.new()
			new_node.set_meta("imported_from_blender",true)
			new_node.set_name(node["name"])
			new_node.translate(pos)
			#new_node.set_rotation(Vector3(0, 0, rad2deg(node["rotation"])))
			new_node.set_scale(Vector3(node["scale"][0],node["scale"][1], 1))
			#new_node.z_index = node["z"]
			parent.add_child(new_node)
			new_node.set_owner(root)

			### handle bone drawing
			if new_node.get_parent() != null and node["bone_connected"]:
				new_node.set_meta("_edit_bone_",true)
			if !(has_bone_child(node)) or node["draw_bone"]:
				#node["position_tip"][0] = node["position_tip"][0]*0.01
				#node["position_tip"][1] = node["position_tip"][1]*0.01
				var posTip = Vector3(node["position_tip"][0]*0.01, node["position_tip"][1]*0.01, 0)
				#node["position_tip"][0] = posTip.x
				#node["position_tip"][1] = posTip.y

				var draw_bone = Spatial.new()
				draw_bone.set_meta("_edit_bone_",true)
				draw_bone.set_name(str(node["name"],"_tail"))

				draw_bone.translate(posTip)
				draw_bone.hide()

				new_node.add_child(draw_bone)
				draw_bone.set_owner(root)

		if node["type"] == "SPRITE":
			new_node = Sprite3D.new()
			var sprite_path = source_file.get_base_dir().plus_file(node["resource_path"])

			### set sprite texture
			var tex = load(sprite_path)
			new_node.set_texture(tex)

			new_node.set_meta("imported_from_blender",true)
			new_node.set_name(node["name"])
			# new_node.set_hframes(node["tiles_x"])
			# new_node.set_vframes(node["tiles_y"])
			# new_node.set_frame(node["frame_index"])
			new_node.set_centered(false)
			new_node.set_offset(Vector2(0, -tex.get_size().y))
			new_node.translate(pos)
			new_node.set_rotation(Vector3(0, 0, node["rotation"]))
			new_node.set_scale(Vector3(node["scale"][0],node["scale"][1], 1))
			#new_node.z_index = node["z"]

			parent.add_child(new_node)
			new_node.set_owner(root)

		if node["type"] == "SLOTSPRITE":
			new_node = AnimatedSprite3D.new()

			var spriteFrame = SpriteFrames.new()
			# spriteFrame.add_animation("default")
			var tex
			for s in node["slotitems"]:
				var sprite_path = source_file.get_base_dir().plus_file(s["resource_path"])
				### set sprite texture
				tex = load(sprite_path)
				spriteFrame.add_frame("default", tex, s["frame_index"])

			new_node.set_sprite_frames(spriteFrame)
			new_node.set_meta("imported_from_blender",true)
			new_node.set_name(node["name"])
			# new_node.set_hframes(node["tiles_x"])
			# new_node.set_vframes(node["tiles_y"])
			# new_node.set_frame(node["frame_index"])
			new_node.set_centered(false)
			#new_node.set_offset(Vector3(node["pivot_offset"][0],node["pivot_offset"][1], 0))
			new_node.set_offset(Vector2(0, -tex.get_size().y))
			new_node.translate(pos)
			new_node.set_rotation(Vector3(0, 0, node["rotation"]))
			new_node.set_scale(Vector3(node["scale"][0],node["scale"][1], 1))
			#new_node.z_index = node["z"]

			parent.add_child(new_node)
			new_node.set_owner(root)

		nodesDict[node["node_path"].replace(".", "_")] = node

		if "children" in node and node["children"].size() > 0:
			i+=1
			create_nodes(source_file, node["children"], root, new_node, copy_images, nodesDict, i)

