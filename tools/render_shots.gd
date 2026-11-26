extends SceneTree
## 개발용: 소개 페이지(deploy/web-landing/about/)용 게임 스크린샷
##   xvfb-run godot --rendering-method gl_compatibility --resolution 1280x720 --fixed-fps 60 --path . -s tools/render_shots.gd
##   → deploy/web-landing/about/shot_1~3.png (jpg 로 변환해서 사용)
var m: Node
var g
var frame := 0
var t0 := -1
var cam: Camera3D
var hud_layers: Array = []
# [찍을 프레임(경기 시작 후), 카메라 위치, 바라볼 곳, HUD 표시]  — 위치가 null 이면 기본 플레이어 카메라
var shots := [
    [50, Vector3(0.0, 17.0, 17.0), Vector3(0, 0, -1.0), false],
    [100, Vector3(5.5, 2.6, 6.5), Vector3(-0.5, 1.2, 0.0), false],
    [170, Vector3(8.0, 7.5, 12.5), Vector3(-0.5, 0.6, 0.0), false],
]
var idx := 0

func _initialize() -> void:
    m = load("res://scenes/match.tscn").instantiate()
    root.add_child(m)

func _process(_d) -> bool:
    frame += 1
    if g == null:
        g = m.get_node_or_null("Game")
        if g:
            g.countdown_time = 0.05
        return false
    if t0 < 0 and g.is_playing():
        t0 = frame
        for c in g.get_children():
            if c is CanvasLayer:
                hud_layers.append(c)
        cam = Camera3D.new()
        cam.fov = 55.0
        g.add_child(cam)
    if t0 > 0 and idx < shots.size():
        var s = shots[idx]
        var el: int = frame - t0
        if el == s[0] - 3:
            for c in hud_layers:
                c.visible = s[3]
            if s[1] != null:
                cam.global_position = s[1]
                cam.look_at(s[2], Vector3.UP)
                cam.current = true
            else:
                cam.current = false
                var h = g.get("human")
                if h and h.has_node("SpringArm3D/Camera3D"):
                    h.get_node("SpringArm3D/Camera3D").current = true
        if el == s[0]:
            var dir := ProjectSettings.globalize_path("res://deploy/web-landing/about")
            DirAccess.make_dir_recursive_absolute(dir)
            root.get_texture().get_image().save_png(dir + "/shot_%d.png" % (idx + 1))
            print("saved shot ", idx + 1)
            idx += 1
    if idx >= shots.size() or frame > 3000:
        quit()
    return false
