@tool
extends EditorScenePostImport
## Mixamo characters embed 4096² body textures (~50 MB of video memory per character). Scale them down at
## import: 2048 for the player, 1024 for everyone else (they are rarely seen up close), re-compressed as
## Basis Universal so the .pck stays small too.

const PLAYER := "ch08_nonpbr"


func _post_import(scene: Node) -> Object:
	var limit := 2048 if get_source_file().get_file().get_basename() == PLAYER else 1024
	var done := {}
	for mi: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i) as BaseMaterial3D
			if m == null or done.has(m):
				continue
			done[m] = true
			for p in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture", "ao_texture"]:
				var t := m.get(p) as Texture2D
				if t == null or maxi(t.get_width(), t.get_height()) <= limit:
					continue
				var img := t.get_image()
				if img == null:
					continue
				if img.is_compressed():
					img.decompress()
				var k := float(limit) / maxi(img.get_width(), img.get_height())
				img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
				var nt := PortableCompressedTexture2D.new()
				nt.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_BASIS_UNIVERSAL, p == "normal_texture")
				m.set(p, nt)
	return scene
