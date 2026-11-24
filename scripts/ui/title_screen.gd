extends Control
## 1단계: 닉네임 입력 + 서버 선택(이름만 노출) + 접속

const UI := preload("res://scripts/ui/ui_kit.gd")
const GameRegistry := preload("res://scripts/core/game_registry.gd")

var app: Node
var _nick: LineEdit
var _server: OptionButton
var _servers: Array = []
var _status: Label
var _buttons: Array[Button] = []
var _pending_nick := ""
var _retry_left := 0
var _retry_url := ""
var _retry_name := ""
var _login_try := 0


func _ready() -> void:
    # 상단 왼쪽: 알약 메뉴
    var top := UI.hbox(10)
    top.position = Vector2(20, 18)
    add_child(top)
    var help_btn := UI.pill_button("조작법")
    help_btn.pressed.connect(_show_help)
    top.add_child(help_btn)
    var offline_btn := UI.pill_button("오프라인 연습")
    offline_btn.pressed.connect(_on_offline_pressed.bind(offline_btn))
    top.add_child(offline_btn)
    _buttons.append(offline_btn)
    # 개발용: 에디터/디버그 빌드에서만 표시 (릴리스·웹 빌드에선 숨김)
    if Net.is_dev_build():
        var local_btn := UI.pill_button("이 PC 서버로 테스트", UI.SECONDARY, Color.WHITE)
        local_btn.pressed.connect(_on_local_pressed)
        top.add_child(local_btn)
        _buttons.append(local_btn)

    var root := UI.vbox(0)
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(root)

    # 가운데: 로고 + 한 줄 소개
    var mid := UI.vbox(14)
    mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
    mid.alignment = BoxContainer.ALIGNMENT_CENTER
    mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(mid)
    mid.add_child(UI.logo(96))
    var tag := UI.title("친구들과 즐기는 캐주얼 파티 게임 모음  ·  떨어지는 돌을 피하고, 밀쳐내고, 살아남자!", 22)
    tag.add_theme_constant_override("outline_size", 7)
    mid.add_child(tag)

    # 아래: 서버 선택 + 닉네임 + 입장하기
    var bottom := UI.vbox(12)
    bottom.alignment = BoxContainer.ALIGNMENT_CENTER
    root.add_child(bottom)

    var server_row := UI.hbox(10)
    server_row.alignment = BoxContainer.ALIGNMENT_CENTER
    bottom.add_child(server_row)
    var sl := UI.title("서버", 18)
    sl.add_theme_constant_override("outline_size", 6)
    server_row.add_child(sl)
    # 서버 선택: 이름만 보여주고 주소는 숨긴다
    _server = OptionButton.new()
    _server.custom_minimum_size = Vector2(200, 44)
    _servers = Net.available_servers()
    var saved := String(app.load_setting("server_name", ""))
    for i in _servers.size():
        _server.add_item(String(_servers[i].name), i)
        if _servers[i].name == saved:
            _server.select(i)
    server_row.add_child(_server)

    var entry := UI.hbox(12)
    entry.alignment = BoxContainer.ALIGNMENT_CENTER
    bottom.add_child(entry)
    _nick = UI.line_edit("닉네임 (2~12자)", String(app.load_setting("nickname", "")), Net.NICK_MAX)
    _nick.custom_minimum_size = Vector2(340, 58)
    _nick.add_theme_font_size_override("font_size", 22)
    _nick.text_submitted.connect(func(_t): _on_connect_pressed())
    entry.add_child(_nick)
    var connect_btn := UI.cta_button("입장하기")
    connect_btn.custom_minimum_size = Vector2(190, 58)
    connect_btn.pressed.connect(_on_connect_pressed)
    entry.add_child(connect_btn)
    _buttons.append(connect_btn)

    _status = UI.title("", 17)
    _status.add_theme_constant_override("outline_size", 6)
    _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _status.custom_minimum_size = Vector2(0, 30)
    bottom.add_child(_status)
    var pad := Control.new()
    pad.custom_minimum_size.y = 26
    bottom.add_child(pad)

    _build_help()

    Net.connected.connect(_on_connected)
    Net.connection_failed.connect(_on_failed)
    Net.login_result.connect(_on_login_result)
    if not Fighter.touch_device():
        _nick.grab_focus.call_deferred()


# ---- 조작법 창
var _help: Control


func _build_help() -> void:
    _help = ColorRect.new()
    (_help as ColorRect).color = Color(0.05, 0.08, 0.15, 0.5)
    _help.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _help.visible = false
    add_child(_help)
    var v := UI.centered_panel(_help, 560)
    v.add_child(UI.heading("조작법", 30))
    var rows := [
        ["이동", "WASD  ·  모바일: 왼쪽 화면 스틱"],
        ["시점", "마우스  ·  모바일: 오른쪽 화면 드래그 (버튼을 누른 채 끌어도 됨)"],
        ["점프", "Space  ·  모바일: 점프 버튼"],
        ["밀치기", "좌클릭/E 짧게 = 제자리 밀기, 길게 = 차징 돌진 (공중에선 불가)"],
    ]
    for r in rows:
        var h := UI.hbox(14)
        var k := UI.badge(r[0], UI.SECONDARY)
        k.custom_minimum_size.x = 84
        h.add_child(k)
        var d := UI.label(r[1], 17)
        d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        h.add_child(d)
        v.add_child(h)
    var close := UI.cta_button("확인")
    close.pressed.connect(func(): _help.visible = false)
    v.add_child(close)


func _show_help() -> void:
    _help.visible = true


func _exit_tree() -> void:
    Net.connected.disconnect(_on_connected)
    Net.connection_failed.disconnect(_on_failed)
    Net.login_result.disconnect(_on_login_result)


## 게임이 하나면 바로 시작, 여러 개면 고르는 메뉴
func _on_offline_pressed(btn: Button) -> void:
    var mods: Array = GameRegistry.all()
    if mods.size() == 1:
        app.start_offline_practice(mods[0].id)
        return
    var menu := PopupMenu.new()
    menu.add_theme_font_size_override("font_size", 20)
    for i in mods.size():
        menu.add_item(mods[i].display_name, i)
    menu.id_pressed.connect(func(i): app.start_offline_practice(mods[i].id))
    add_child(menu)
    menu.popup(Rect2i(Vector2i(btn.global_position + Vector2(0, btn.size.y)), Vector2i(int(btn.size.x), 0)))


func _selected_server() -> Dictionary:
    var i := maxi(_server.selected, 0)
    return _servers[i]


func _check_nick() -> bool:
    var n := _nick.text.strip_edges()
    if n.length() < Net.NICK_MIN:
        _set_status("닉네임을 %d자 이상 입력하세요" % Net.NICK_MIN, UI.DANGER)
        _nick.grab_focus()
        return false
    return true


func _on_connect_pressed() -> void:
    if not _check_nick():
        return
    var s := _selected_server()
    _start_connect(String(s.url), String(s.name), 0)


func _on_local_pressed() -> void:
    if not _check_nick():
        return
    if not app.start_local_server(Net.DEFAULT_PORT):
        _set_status("서버 프로세스를 시작하지 못했습니다", UI.DANGER)
        return
    _set_status("로컬 서버를 여는 중…", UI.MUTED)
    _set_busy(true)
    # 서버가 뜰 때까지 잠시 기다린 뒤 몇 번 재시도
    await get_tree().create_timer(1.5).timeout
    _start_connect(String(Net.LOCAL_TEST_SERVER.url), String(Net.LOCAL_TEST_SERVER.name), 4)


func _start_connect(url: String, display_name: String, retries: int) -> void:
    _pending_nick = _nick.text.strip_edges()
    _retry_left = retries
    _retry_url = url
    _retry_name = display_name
    app.save_setting("nickname", _pending_nick)
    app.save_setting("server_name", display_name)
    _set_status("%s에 접속 중…" % display_name, UI.MUTED)
    _set_busy(true)
    Net.connect_to_server(url, display_name)


func _on_connected() -> void:
    _set_status("로그인 중…", UI.MUTED)
    Net.login(_pending_nick)
    # 응답이 없으면(서버가 예전 버전이라 요청을 못 알아듣는 경우 등) 무한 대기하지 않게
    var my_try := _login_try + 1
    _login_try = my_try
    await get_tree().create_timer(Net.LOGIN_TIMEOUT).timeout
    if is_inside_tree() and _login_try == my_try and not Net.is_logged_in() and Net.is_online():
        Net.disconnect_from_server()
        _set_busy(false)
        _set_status("%s 응답 없음 — 서버와 게임 버전이 다를 수 있습니다 (서버 업데이트 필요)" % _retry_name, UI.DANGER)


func _on_failed(reason: String) -> void:
    if _retry_left > 0:
        _retry_left -= 1
        await get_tree().create_timer(1.0).timeout
        Net.connect_to_server(_retry_url, _retry_name)
        return
    _set_busy(false)
    _set_status("%s: %s" % [_retry_name, reason], UI.DANGER)


func _on_login_result(ok: bool, message: String) -> void:
    _login_try += 1
    if ok:
        app.show_screen("lobby")
        app.toast("%s 님, 환영합니다!" % message, UI.GOOD)
    else:
        Net.disconnect_from_server()
        _set_busy(false)
        _set_status(message, UI.DANGER)
        _nick.grab_focus()


func _set_busy(busy: bool) -> void:
    for b in _buttons:
        if is_instance_valid(b):
            b.disabled = busy
    _nick.editable = not busy
    _server.disabled = busy


func _set_status(text: String, color: Color) -> void:
    _status.text = text
    # 배경 위 글자: 흰색(일반) / 연한 빨강(오류)
    _status.add_theme_color_override("font_color", Color(1.0, 0.75, 0.72) if color == UI.DANGER else Color.WHITE)
