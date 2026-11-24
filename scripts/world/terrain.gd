extends StaticBody3D
## 절차적 높이맵 지형. 중앙은 완만한 초원, 바깥으로 갈수록 언덕 → 가장자리는 눈 덮인 산맥(분지형).

@export var size := 256          # 한 변 길이(m). 1m 간격 정점
@export var noise_seed := 1337
@export var flat_half := 22.0     # 이 사각형 안쪽은 거의 평평하게 (대결 아레나)

var headless := false             # 서버: 보이는 메시 없이 충돌만
var n := 0                        # 한 변 정점 수
var half := 0.0
var heights := PackedFloat32Array()

var _hills: FastNoiseLite
var _detail: FastNoiseLite


func generate(material: Material) -> void:
    n = size + 1
    half = size * 0.5

    _hills = FastNoiseLite.new()
    _hills.seed = noise_seed
    _hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
    _hills.frequency = 0.006
    _hills.fractal_octaves = 5

    _detail = FastNoiseLite.new()
    _detail.seed = noise_seed + 1
    _detail.frequency = 0.05

    heights.resize(n * n)
    for z in n:
        for x in n:
            heights[z * n + x] = _height_fn(x - half, z - half)

    if not headless:
        _build_mesh(material)
    _build_collision()


func _height_fn(x: float, z: float) -> float:
    var d := Vector2(x, z).length()
    var h := _hills.get_noise_2d(x, z) * 11.0 + _detail.get_noise_2d(x, z) * 0.5
    var box_d := maxf(absf(x), absf(z))
    h *= lerpf(0.0, 1.0, smoothstep(flat_half, flat_half + 28.0, box_d))    # 아레나는 완전히 평평 (회전 기둥용)
    var ridge := smoothstep(70.0, 126.0, d)
    h += ridge * ridge * 48.0 * (0.75 + 0.35 * _hills.get_noise_2d(x * 2.5, z * 2.5))
    return h


func _build_mesh(material: Material) -> void:
    var verts := PackedVector3Array()
    var normals := PackedVector3Array()
    var uvs := PackedVector2Array()
    verts.resize(n * n)
    normals.resize(n * n)
    uvs.resize(n * n)

    for z in n:
        for x in n:
            var i := z * n + x
            verts[i] = Vector3(x - half, heights[i], z - half)
            var hl := heights[z * n + maxi(x - 1, 0)]
            var hr := heights[z * n + mini(x + 1, n - 1)]
            var hd := heights[maxi(z - 1, 0) * n + x]
            var hu := heights[mini(z + 1, n - 1) * n + x]
            normals[i] = Vector3(hl - hr, 2.0, hd - hu).normalized()
            uvs[i] = Vector2(float(x) / size, float(z) / size)

    var indices := PackedInt32Array()
    indices.resize(size * size * 6)
    var k := 0
    for z in size:
        for x in size:
            var a := z * n + x
            var b := a + 1
            var c := a + n
            var d := c + 1
            indices[k] = a; indices[k + 1] = b; indices[k + 2] = c
            indices[k + 3] = b; indices[k + 4] = d; indices[k + 5] = c
            k += 6

    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = verts
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = indices

    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    mesh.surface_set_material(0, material)

    var mi := MeshInstance3D.new()
    mi.name = "TerrainMesh"
    mi.mesh = mesh
    add_child(mi)


func _build_collision() -> void:
    var shape := HeightMapShape3D.new()
    shape.map_width = n
    shape.map_depth = n
    shape.map_data = heights
    var col := CollisionShape3D.new()
    col.shape = shape
    add_child(col)


## 월드 좌표 (x, z)의 지형 높이 (쌍선형 보간)
func get_height(x: float, z: float) -> float:
    var fx := clampf(x + half, 0.0, size - 0.001)
    var fz := clampf(z + half, 0.0, size - 0.001)
    var ix := int(fx)
    var iz := int(fz)
    var tx := fx - ix
    var tz := fz - iz
    var h00 := heights[iz * n + ix]
    var h10 := heights[iz * n + ix + 1]
    var h01 := heights[(iz + 1) * n + ix]
    var h11 := heights[(iz + 1) * n + ix + 1]
    return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## 0 = 평지, 1 = 수직 벽
func get_slope(x: float, z: float) -> float:
    var nrm := Vector3(get_height(x - 1.0, z) - get_height(x + 1.0, z), 2.0,
            get_height(x, z - 1.0) - get_height(x, z + 1.0)).normalized()
    return 1.0 - nrm.y


func get_normal(x: float, z: float) -> Vector3:
    return Vector3(get_height(x - 1.0, z) - get_height(x + 1.0, z), 2.0,
            get_height(x, z - 1.0) - get_height(x, z + 1.0)).normalized()
