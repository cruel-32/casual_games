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


func _ready() -> void:
    if Net.is_server:
        return
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    set_anchors_preset(Control.PRESET_FULL_RECT)
    theme = UI.make_theme()

    var bg := TextureRect.new()
    var grad := Gradient.new()
    grad.set_color(0, Color(0.42, 0.68, 0.98))
    grad.set_color(1, Color(0.72, 0.93, 0.82))
    var gt := GradientTexture2D.new()
    gt.gradient = grad
    gt.fill_from = Vector2(0.5, 0.0)
    gt.fill_to = Vector2(0.5, 1.0)
    bg.texture = gt
    bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    bg.stretch_mode = TextureRect.STRETCH_SCALE
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(bg)

    _toast = UI.label("", 18, Color.WHITE)
    _toast.add_theme_stylebox_override("normal", UI.box(Color(0.15, 0.18, 0.28, 0.85), 12, 18))
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
    _toast.add_theme_stylebox_override("normal", UI.box(color, 12, 18))
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
