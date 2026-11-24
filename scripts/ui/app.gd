extends Control
## 클라이언트 메뉴 앱: 타이틀(닉네임/접속) → 로비 → 방 화면 전환, 알림(토스트), 게임 씬 진입.
## 전용 서버(--server)로 실행되면 UI를 만들지 않는다.

const UI := preload("res://scripts/ui/ui_kit.gd")
const TITLE := preload("res://scripts/ui/title_screen.gd")
const LOBBY := preload("res://scripts/ui/lobby_screen.gd")
const ROOM := preload("res://scripts/ui/room_screen.gd")
const GAME_SCENE := "res://scenes/match.tscn"
const GameRegistry := preload("res://scripts/core/game_registry.gd")
const SETTINGS_PATH := "user://settings.cfg"

var current_name := ""
var _current: Control
var _toast: Label
var _toast_tween: Tween
var local_server_pid := -1
var _sky: Control
var _backdrop: Node


func _gradient_rect(colors: Array) -> TextureRect:
    var grad := Gradient.new()
    grad.remove_point(1)
    grad.set_color(0, colors[0])
    for i in range(1, colors.size()):
        grad.add_point(float(i) / (colors.size() - 1), colors[i])
    var gt := GradientTexture2D.new()
    gt.gradient = grad
    gt.fill_from = Vector2(0.5, 0.0)
    gt.fill_to = Vector2(0.5, 1.0)
    var r := TextureRect.new()
    r.texture = gt
    r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    r.stretch_mode = TextureRect.STRETCH_SCALE
    r.mouse_filter = Control.MOUSE_FILTER_IGNORE
    r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    return r


## 메뉴 뒤에 살아 움직이는 3D 아레나 (첫 화면이 먼저 뜬 다음 만든다)
func _spawn_backdrop() -> void:
    await get_tree().process_frame
    await get_tree().process_frame
    if not is_inside_tree() or _backdrop:
        return
    var world: Node = load(GAME_SCENE).instantiate()
    world.set("menu_mode", true)
    add_child(world)
    move_child(world, 0)
    _backdrop = world
    _sky.visible = false


func _ready() -> void:
    if Net.is_server:
        return
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    set_anchors_preset(Control.PRESET_FULL_RECT)
    theme = UI.make_theme()

    # 배경: 3D 월드가 뜨기 전까지 보이는 하늘색 그라데이션 + 그 위 글자가 잘 보이게 위·아래를 살짝 어둡게
    _sky = _gradient_rect([Color(0.42, 0.68, 0.98), Color(0.72, 0.93, 0.82)])
    add_child(_sky)
    var shade := _gradient_rect([Color(0.05, 0.08, 0.2, 0.35), Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0.05, 0.08, 0.2, 0.45)])
    add_child(shade)

    _toast = UI.heading("", 20, Color.WHITE)
    _toast.add_theme_stylebox_override("normal", UI.box(Color(0.15, 0.18, 0.28, 0.92), 16, 20, UI.INK, 3, 4))
    _toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _toast.modulate.a = 0.0
    _toast.z_index = 10

    Net.disconnected.connect(_on_disconnected)
    Net.error_message.connect(_on_error)
    Net.game_started.connect(_on_game_started)
    Net.left_room.connect(_on_left_room)
    Net.room_updated.connect(_on_room_updated)

    if Net.is_logged_in():
        show_screen("room" if Net.in_room() else "lobby")
    else:
        show_screen("title")
    _spawn_backdrop.call_deferred()
    add_child(_toast)
    if Fighter.touch_device():
        add_child(load("res://scripts/ui/rotate_hint.gd").new())


func show_screen(screen: String) -> void:
    if _current:
        _current.queue_free()
    var s: Control
    match screen:
        "title":
            s = TITLE.new()
        "lobby":
            s = LOBBY.new()
        "room":
            s = ROOM.new()
    s.set("app", self)
    s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(s)
    if _toast and _toast.get_parent() == self:
        move_child(_toast, -1)
    _current = s
    current_name = screen


func toast(text: String, color: Color = Color(0.15, 0.18, 0.28, 0.85)) -> void:
    _toast.text = text
    _toast.add_theme_stylebox_override("normal", UI.box(color, 16, 20, UI.INK, 3, 4))
    _toast.size = _toast.get_minimum_size()
    _toast.position = Vector2((get_viewport_rect().size.x - _toast.size.x) * 0.5, get_viewport_rect().size.y - 90)
    if _toast_tween:
        _toast_tween.kill()
    _toast.modulate.a = 1.0
    _toast_tween = create_tween()
    _toast_tween.tween_interval(2.4)
    _toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


# ---- 설정 저장 (닉네임, 서버 주소)
func load_setting(key: String, default_value: Variant) -> Variant:
    var cfg := ConfigFile.new()
    if cfg.load(SETTINGS_PATH) != OK:
        return default_value
    return cfg.get_value("client", key, default_value)


func save_setting(key: String, value: Variant) -> void:
    var cfg := ConfigFile.new()
    cfg.load(SETTINGS_PATH)
    cfg.set_value("client", key, value)
    cfg.save(SETTINGS_PATH)


## 테스트용: 이 PC에서 헤드리스 서버 프로세스를 띄운다
func start_local_server(port: int) -> bool:
    if local_server_pid > 0 and OS.is_process_running(local_server_pid):
        return true
    var args := PackedStringArray(["--headless"])
    if OS.has_feature("editor"):
        args.append_array(["--path", ProjectSettings.globalize_path("res://")])
    args.append_array(["--", "--server", "--port", str(port)])
    local_server_pid = OS.create_process(OS.get_executable_path(), args)
    get_tree().root.set_meta("local_server_pid", local_server_pid)
    return local_server_pid > 0


func start_offline_practice(game_id: String = "") -> void:
    Net.match_config = {}
    load("res://scripts/world/world.gd").offline_game_id = game_id if game_id != "" else GameRegistry.default_id()
    get_tree().change_scene_to_file(GAME_SCENE)


func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        var pid := int(get_tree().root.get_meta("local_server_pid", -1))
        if pid > 0:
            OS.kill(pid)


func _on_disconnected() -> void:
    show_screen("title")
    toast("서버와 연결이 끊어졌습니다", UI.DANGER)


func _on_error(text: String) -> void:
    toast(text, UI.DANGER)


func _on_left_room(reason: String) -> void:
    show_screen("lobby")
    if reason != "":
        toast(reason, UI.DANGER)


func _on_room_updated(_room: Dictionary) -> void:
    if current_name != "room":
        show_screen("room")


func _on_game_started(_room: Dictionary) -> void:
    get_tree().change_scene_to_file(GAME_SCENE)
