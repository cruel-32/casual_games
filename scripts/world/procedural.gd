extends RefCounted
## 절차적 메시 생성 헬퍼

## 노이즈로 찌그러뜨린 로우폴리 바위 (면 단위 노멀)
static func make_rock_mesh(seed_value: int) -> ArrayMesh:
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
        verts[i] = Vector3(v.x * k * 1.15, v.y * k * 0.8, v.z * k)

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


## XZ 평면 위 -Z 방향을 가리키는 삼각형 (화살촉)
static func make_arrow_head(width: float, length: float) -> ArrayMesh:
    var verts := PackedVector3Array([
        Vector3(-width * 0.5, 0, 0), Vector3(width * 0.5, 0, 0), Vector3(0, 0, -length)])
    var normals := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = verts
    arrays[Mesh.ARRAY_NORMAL] = normals
    var m := ArrayMesh.new()
    m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return m
