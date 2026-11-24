extends Node3D
## 야숨 스타일 그래픽 프로토타입
## 툰 셰이딩 + 그림 같은 하늘 + 대기 원근(안개) + 절차적 지형 + 바람 풀 + 임시 나무/바위/유적

const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const TERRAIN_SCRIPT := preload("res://scripts/terrain.gd")
const GRASS_SCRIPT := preload("res://scripts/grass.gd")
const Toon := preload("res://scripts/toon.gd")
const SKY_SHADER := preload("res://shaders/sky.gdshader")
const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const GRASS_SHADER := preload("res://shaders/grass.gdshader")

const GRASS_A := Color(0.22, 0.42, 0.13)
const GRASS_B := Color(0.36, 0.53, 0.16)

@export var grass_density := 2.5     # m²당 풀 덩어리 수 (덩어리 = 3가닥). 사양 낮으면 1.0
@export var grass_radius := 110.0
@export var tree_count := 55
@export var rock_count := 35

var terrain: Node
var player: CharacterBody3D
var noise_tex: NoiseTexture2D
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 20261124
	_setup_input()
	noise_tex = _make_noise_texture(512, 0.012, 3, 7)
	_build_environment()
	_build_terrain()
	_build_grass()
	_scatter_trees()
	_scatter_rocks()
	_build_ruins()
	_spawn_player()
	_build_hud()


# ---------------------------------------------------------------- 입력
func _setup_input() -> void:
	_add_key_action(&"move_forward", [KEY_W, KEY_UP])
	_add_key_action(&"move_back", [KEY_S, KEY_DOWN])
	_add_key_action(&"move_left", [KEY_A, KEY_LEFT])
	_add_key_action(&"move_right", [KEY_D, KEY_RIGHT])
	_add_key_action(&"jump", [KEY_SPACE])
	_add_key_action(&"sprint", [KEY_SHIFT])


func _add_key_action(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _make_noise_texture(px: int, freq: float, octaves: int, seed_value: int) -> NoiseTexture2D:
	var fn := FastNoiseLite.new()
	fn.seed = seed_value
	fn.frequency = freq
	fn.fractal_octaves = octaves
	var tex := NoiseTexture2D.new()
	tex.width = px
	tex.height = px
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.noise = fn
	return tex


# ---------------------------------------------------------------- 하늘 / 조명 / 후처리
func _build_environment() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("cloud_noise", _make_noise_texture(512, 0.006, 5, 99))

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0

	# 대기 원근: 멀리 있는 산이 푸르게 바래 보이게
	env.fog_enabled = true
	env.fog_light_color = Color(0.70, 0.80, 0.93)
	env.fog_density = 0.0028
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.25
	env.fog_height = 2.0
	env.fog_height_density = 0.02

	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.3

	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.05

	# Forward+ 전용 효과 (Compatibility 렌더러에선 지원 안 됨)
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		env.ssao_enabled = true
		env.ssao_radius = 1.5
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.006
		env.volumetric_fog_albedo = Color(0.95, 0.97, 1.0)
		env.volumetric_fog_anisotropy = 0.6
		env.volumetric_fog_length = 120.0

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-38.0, -40.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)


# ---------------------------------------------------------------- 지형 / 풀
func _build_terrain() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	mat.set_shader_parameter("noise_tex", noise_tex)
	mat.set_shader_parameter("grass_a", GRASS_A)
	mat.set_shader_parameter("grass_b", GRASS_B)
	mat.set_shader_parameter("shade_softness", 0.25)
	mat.set_shader_parameter("rim_strength", 0.0)
	mat.set_shader_parameter("snow_height", 36.0)

	terrain = TERRAIN_SCRIPT.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.generate(mat)


func _build_grass() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = GRASS_SHADER
	mat.set_shader_parameter("noise_tex", noise_tex)
	mat.set_shader_parameter("grass_a", GRASS_A)
	mat.set_shader_parameter("grass_b", GRASS_B)
	mat.set_shader_parameter("tip_color", Color(0.60, 0.70, 0.30))
	mat.set_shader_parameter("rim_strength", 0.0)
	mat.set_shader_parameter("shade_softness", 0.25)

	var grass := GRASS_SCRIPT.new()
	grass.name = "Grass"
	add_child(grass)
	grass.generate(terrain, mat, grass_density, grass_radius, rng)


# ---------------------------------------------------------------- 나무 / 바위 / 유적 (임시 에셋)
func _ground_point(x: float, z: float) -> Vector3:
	return Vector3(x, terrain.get_height(x, z), z)


func _scatter_trees() -> void:
	var trunk_mat := Toon.make(Color(0.42, 0.30, 0.20), {"rim_strength": 0.15})
	var leaf_mats: Array[ShaderMaterial] = [
		Toon.make(Color(0.26, 0.47, 0.17), {"shade_softness": 0.15, "rim_strength": 0.45}),
		Toon.make(Color(0.34, 0.54, 0.19), {"shade_softness": 0.15, "rim_strength": 0.45}),
		Toon.make(Color(0.42, 0.58, 0.20), {"shade_softness": 0.15, "rim_strength": 0.45}),
	]
	var placed := 0
	var tries := 0
	while placed < tree_count and tries < 3000:
		tries += 1
		var x := rng.randf_range(-100.0, 100.0)
		var z := rng.randf_range(-100.0, 100.0)
		var d := Vector2(x, z).length()
		if d < 16.0 or d > 95.0:
			continue
		if terrain.get_slope(x, z) > 0.25 or terrain.get_height(x, z) > 14.0:
			continue
		_make_tree(_ground_point(x, z), rng.randf_range(0.8, 1.4), trunk_mat,
				leaf_mats[rng.randi() % leaf_mats.size()])
		placed += 1


func _make_tree(pos: Vector3, s: float, trunk_mat: Material, leaf_mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = rng.randf() * TAU
	add_child(body)

	var trunk_h := 3.4 * s
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16 * s
	trunk.bottom_radius = 0.30 * s
	trunk.height = trunk_h
	var tmi := MeshInstance3D.new()
	tmi.mesh = trunk
	tmi.material_override = trunk_mat
	tmi.position.y = trunk_h * 0.5 - 0.2
	body.add_child(tmi)

	var shape := CylinderShape3D.new()
	shape.radius = 0.3 * s
	shape.height = trunk_h
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = trunk_h * 0.5
	body.add_child(col)

	# 잎: 구를 뭉쳐 부드러운 덩어리 실루엣
	var blobs: Array = [[Vector3(0, 3.7, 0), 1.6], [Vector3(0, 4.8, 0.1), 1.1]]
	for i in 5:
		var a := i * TAU / 5.0 + rng.randf() * 0.5
		blobs.append([Vector3(cos(a) * 1.1, 3.3 + rng.randf() * 0.7, sin(a) * 1.1), rng.randf_range(0.9, 1.25)])
	for blob in blobs:
		var r: float = blob[1] * s
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 20
		sm.rings = 10
		var lmi := MeshInstance3D.new()
		lmi.mesh = sm
		lmi.material_override = leaf_mat
		lmi.position = (blob[0] as Vector3) * s
		body.add_child(lmi)


func _make_rock_mesh(seed_value: int) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 9
	sphere.rings = 6
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	var nz := FastNoiseLite.new()
	nz.seed = seed_value
	nz.frequency = 0.9
	for i in verts.size():
		var v := verts[i]
		var k := 1.0 + nz.get_noise_3dv(v) * 0.4
		verts[i] = Vector3(v.x * k * 1.2, v.y * k * 0.7, v.z * k)

	# 면 단위 노멀(로우폴리 각진 바위)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		var nrm := (b - a).cross(c - a)
		if nrm.length() < 0.000001:
			continue
		nrm = nrm.normalized()
		if nrm.dot((a + b + c) / 3.0) < 0.0:
			nrm = -nrm
		for v in [a, b, c]:
			st.set_normal(nrm)
			st.add_vertex(v)
	return st.commit()


func _scatter_rocks() -> void:
	var rock_mats: Array[ShaderMaterial] = [
		Toon.make(Color(0.44, 0.43, 0.45), {"shade_softness": 0.04, "rim_strength": 0.25}),
		Toon.make(Color(0.50, 0.48, 0.45), {"shade_softness": 0.04, "rim_strength": 0.25}),
	]
	var meshes: Array[ArrayMesh] = []
	for i in 4:
		meshes.append(_make_rock_mesh(100 + i))

	var placed := 0
	var tries := 0
	while placed < rock_count and tries < 3000:
		tries += 1
		var x := rng.randf_range(-105.0, 105.0)
		var z := rng.randf_range(-105.0, 105.0)
		if Vector2(x, z).length() < 8.0:
			continue
		var s := rng.randf_range(0.5, 2.6)
		var mesh: ArrayMesh = meshes[rng.randi() % meshes.size()]

		var body := StaticBody3D.new()
		body.position = _ground_point(x, z) - Vector3(0, 0.25 * s, 0)
		body.rotation.y = rng.randf() * TAU
		body.scale = Vector3.ONE * s
		add_child(body)

		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = rock_mats[rng.randi() % rock_mats.size()]
		body.add_child(mi)
		var col := CollisionShape3D.new()
		col.shape = mesh.create_convex_shape()
		body.add_child(col)
		placed += 1


func _build_ruins() -> void:
	var stone := Toon.make(Color(0.60, 0.58, 0.53), {"shade_softness": 0.05, "rim_strength": 0.3})
	var center := _ground_point(22.0, -18.0)

	var base := CylinderMesh.new()
	base.top_radius = 7.0
	base.bottom_radius = 7.4
	base.height = 0.6
	var base_body := StaticBody3D.new()
	base_body.position = center + Vector3(0, 0.1, 0)
	add_child(base_body)
	var bmi := MeshInstance3D.new()
	bmi.mesh = base
	bmi.material_override = stone
	base_body.add_child(bmi)
	var bcol := CollisionShape3D.new()
	bcol.shape = base.create_convex_shape()
	base_body.add_child(bcol)

	var pillar_heights: Array[float] = [5.0, 2.2, 4.6, 1.4, 5.0, 3.1, 0.8]
	for i in pillar_heights.size():
		var a := i * TAU / pillar_heights.size()
		var h := pillar_heights[i]
		var p := center + Vector3(cos(a) * 5.5, 0.4 + h * 0.5, sin(a) * 5.5)
		var pm := CylinderMesh.new()
		pm.top_radius = 0.45
		pm.bottom_radius = 0.5
		pm.height = h
		pm.radial_segments = 12
		var body := StaticBody3D.new()
		body.position = p
		add_child(body)
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = stone
		body.add_child(mi)
		var shape := CylinderShape3D.new()
		shape.radius = 0.5
		shape.height = h
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)


# ---------------------------------------------------------------- 플레이어 / HUD
func _spawn_player() -> void:
	player = PLAYER_SCRIPT.new()
	player.name = "Player"
	player.position = _ground_point(0.0, 10.0) + Vector3(0, 0.5, 0)
	add_child(player)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var help := Label.new()
	help.text = "WASD 이동  |  마우스 시점  |  Space 점프  |  Shift 달리기  |  휠 줌  |  Esc 마우스 해제 (클릭으로 복귀)"
	help.position = Vector2(16, 12)
	help.add_theme_color_override("font_color", Color.WHITE)
	help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	help.add_theme_constant_override("outline_size", 5)
	layer.add_child(help)
