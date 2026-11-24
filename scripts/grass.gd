extends Node3D
## 16m 청크 단위 MultiMesh 풀밭. 청크로 나눠 화면 밖/먼 거리 청크는 그리지 않는다.

const CHUNK := 16.0


func generate(terrain: Node, material: Material, density: float, radius: float,
        rng: RandomNumberGenerator) -> void:
    var mesh := _make_clump_mesh()
    mesh.surface_set_material(0, material)

    var per_chunk := int(CHUNK * CHUNK * density)
    var cells := int(ceil(radius / CHUNK))

    for cz in range(-cells, cells):
        for cx in range(-cells, cells):
            var center := Vector2((cx + 0.5) * CHUNK, (cz + 0.5) * CHUNK)
            if center.length() > radius + CHUNK:
                continue

            var buf := PackedFloat32Array()
            buf.resize(per_chunk * 12)
            var count := 0
            var min_y := INF
            var max_y := -INF

            for i in per_chunk:
                var lx := rng.randf_range(-CHUNK * 0.5, CHUNK * 0.5)
                var lz := rng.randf_range(-CHUNK * 0.5, CHUNK * 0.5)
                var wx := center.x + lx
                var wz := center.y + lz
                if Vector2(wx, wz).length() > radius:
                    continue
                var slope: float = terrain.get_slope(wx, wz)
                if slope > 0.3:
                    continue
                var h: float = terrain.get_height(wx, wz)
                if h > 18.0:
                    continue

                var rot := rng.randf() * TAU
                var s := rng.randf_range(0.7, 1.3)
                var sy := s * rng.randf_range(0.8, 1.35)
                var c := cos(rot)
                var sn := sin(rot)
                var o := count * 12
                # Transform3D 행 우선 3x4: [basis 행 | origin]
                buf[o + 0] = c * s;   buf[o + 1] = 0.0; buf[o + 2] = sn * s;  buf[o + 3] = lx
                buf[o + 4] = 0.0;     buf[o + 5] = sy;  buf[o + 6] = 0.0;     buf[o + 7] = h - 0.05
                buf[o + 8] = -sn * s; buf[o + 9] = 0.0; buf[o + 10] = c * s;  buf[o + 11] = lz
                count += 1
                min_y = minf(min_y, h)
                max_y = maxf(max_y, h)

            if count == 0:
                continue
            buf.resize(count * 12)

            var mm := MultiMesh.new()
            mm.transform_format = MultiMesh.TRANSFORM_3D
            mm.mesh = mesh
            mm.instance_count = count
            mm.buffer = buf

            var mmi := MultiMeshInstance3D.new()
            mmi.multimesh = mm
            mmi.position = Vector3(center.x, 0.0, center.y)
            mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            mmi.visibility_range_end = 80.0
            mmi.custom_aabb = AABB(Vector3(-CHUNK * 0.5 - 1.0, min_y - 1.0, -CHUNK * 0.5 - 1.0),
                    Vector3(CHUNK + 2.0, max_y - min_y + 3.0, CHUNK + 2.0))
            add_child(mmi)


## 가닥 3개를 120°씩 돌려 묶은 풀 덩어리. UV.y: 뿌리 1 → 끝 0
func _make_clump_mesh() -> ArrayMesh:
    var verts := PackedVector3Array()
    var uvs := PackedVector2Array()
    var normals := PackedVector3Array()
    var idx := PackedInt32Array()

    var offsets: Array[Vector3] = [Vector3(0, 0, 0), Vector3(0.08, 0, 0.05), Vector3(-0.06, 0, 0.07)]
    var blade_heights: Array[float] = [0.55, 0.45, 0.62]
    var rows: Array[float] = [0.0, 0.35, 0.7]
    var width := 0.07

    for b in 3:
        var rot := Basis(Vector3.UP, b * TAU / 3.0 + 0.3)
        var hgt := blade_heights[b]
        var start := verts.size()
        for t in rows:
            var half_w := width * (1.0 - t) * 0.5
            var bend_z := t * t * 0.12
            for side: float in [-1.0, 1.0]:
                verts.append(offsets[b] + rot * Vector3(side * half_w, t * hgt, bend_z))
                uvs.append(Vector2((side + 1.0) * 0.5, 1.0 - t))
                normals.append(Vector3.UP)
        verts.append(offsets[b] + rot * Vector3(0.0, hgt, 0.12))
        uvs.append(Vector2(0.5, 0.0))
        normals.append(Vector3.UP)

        for r in 2:
            var a := start + r * 2
            idx.append_array(PackedInt32Array([a, a + 2, a + 1, a + 1, a + 2, a + 3]))
        idx.append_array(PackedInt32Array([start + 4, start + 6, start + 5]))

    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = verts
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = idx
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh
