extends SceneTree
## 개발용: 메뉴 UI에 쓰는 이미지 렌더링 (게임 빌드에는 포함되지 않음)
##   xvfb-run godot --rendering-method gl_compatibility --path . -s tools/render_assets.gd
## - ui/portraits/slot_N.png : 슬롯 색별 캐릭터 초상화 (투명 배경, 256x256)
## - ui/portraits/me.png     : 흰색 (내 캐릭터)
## ICON=경로 를 주면 대신 앱 아이콘용 얼굴 클로즈업 1장 (--resolution 1024x1024, tools/make_icons.py 가 합성)
const SIZE := 256
var holder: Node3D
var _f
var F  # Fighter 스크립트 (Sfx 오토로드를 참조하므로 -s 스크립트에서는 실행 중에 불러와야 한다)
var _jobs: Array = []
var _wait := 0

func _initialize() -> void:
    pass


func _setup() -> void:
    F = load("res://scripts/character/fighter.gd")
    var icon_out := OS.get_environment("ICON")
    if icon_out != "":
        _jobs.append([icon_out, F.SLOT_COLORS[0], 0])
    else:
        for i in F.SLOT_COLORS.size():
            _jobs.append(["res://ui/portraits/slot_%d.png" % i, F.SLOT_COLORS[i], i])
        _jobs.append(["res://ui/portraits/me.png", Color(0.95, 0.95, 0.92), 0])
    # 창(루트 뷰포트)에 직접 그린다 — 실행 시 --resolution 256x256
    root.transparent_bg = OS.get_environment("OPAQUE") == ""
    root.msaa_3d = Viewport.MSAA_4X
    holder = Node3D.new()
    root.add_child(holder)
    var env := Environment.new()
    env.background_mode = Environment.BG_CLEAR_COLOR
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.75, 0.8, 0.95)
    env.ambient_light_energy = 0.6
    var we := WorldEnvironment.new()
    we.environment = env
    holder.add_child(we)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-35, 150, 0)
    sun.light_energy = 1.1
    holder.add_child(sun)
    var cam := Camera3D.new()
    cam.fov = 27.0
    cam.position = Vector3(0.7, 1.45, -3.1)
    holder.add_child(cam)
    cam.look_at(Vector3(0.1, 1.08, 0), Vector3.UP)
    if icon_out != "":
        cam.position = Vector3(0.38, 1.32, -2.3)
        cam.look_at(Vector3(0.04, 1.08, 0), Vector3.UP)
    cam.current = true
    _next()

func _next() -> void:
    if _f:
        _f.queue_free()
    if _jobs.is_empty():
        quit()
        return
    _f = F.new()
    _f.body_color = _jobs[0][1]
    _f.look = _jobs[0][2]
    _f.display_name = ""
    holder.add_child(_f)
    _f.set_physics_process(false)
    _f.rotation.y = -0.15   # 카메라 쪽을 살짝 비스듬히
    _f.name_tag.visible = false
    _wait = 0

var _started := false
func _process(_d) -> bool:
    if not _started:
        _started = true
        _setup()
        return false
    _wait += 1
    if _wait == 6 and not _jobs.is_empty():
        var img := root.get_texture().get_image()
        var path: String = _jobs[0][0]
        img.save_png(path if path.begins_with("/") else ProjectSettings.globalize_path(path))
        print("saved ", path)
        _jobs.pop_front()
        _next()
    return false
