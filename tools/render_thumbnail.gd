extends SceneTree
## 개발용: 게임 선택 카드용 썸네일 (games/rock_dodge/thumbnail.png)
##   xvfb-run godot --rendering-method gl_compatibility --resolution 640x360 --fixed-fps 60 --path . -s tools/render_thumbnail.gd
var m: Node
var g
var frame := 0
var t0 := -1
var cam: Camera3D

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
                c.visible = false          # HUD 숨김
        cam = Camera3D.new()
        cam.fov = 55.0
        g.add_child(cam)
        cam.global_position = Vector3(8.0, 7.5, 12.5)
        cam.look_at(Vector3(-0.5, 0.6, 0.0), Vector3.UP)
        cam.current = true
    if t0 > 0 and frame - t0 == 170:
        root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://games/rock_dodge/thumbnail.png"))
        print("saved thumbnail")
        quit()
    if frame > 2000:
        quit()
    return false
