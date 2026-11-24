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


func _ready() -> void:
    var root := UI.vbox(28)
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.alignment = BoxContainer.ALIGNMENT_CENTER
    add_child(root)

    var title := UI.title("Small Party World", 64)
    root.add_child(title)

    var center := CenterContainer.new()
    root.add_child(center)
    var panel := PanelContainer.new()
    panel.custom_minimum_size.x = 440
    center.add_child(panel)
    var v := UI.vbox(12)
    panel.add_child(v)

    v.add_child(UI.label("닉네임", 16, UI.MUTED))
    _nick = UI.line_edit("2~12자 (한글/영문/숫자)", String(app.load_setting("nickname", "")), Net.NICK_MAX)
    _nick.text_submitted.connect(func(_t): _on_connect_pressed())
    v.add_child(_nick)

    # 서버 선택: 이름만 보여주고 주소는 숨긴다
    v.add_child(UI.label("서버", 16, UI.MUTED))
    _server = OptionButton.new()
    _server.custom_minimum_size.y = 46
    _servers = Net.available_servers()
    var saved := String(app.load_setting("server_name", ""))
    for i in _servers.size():
        _server.add_item(String(_servers[i].name), i)
        if _servers[i].name == saved:
            _server.select(i)
    v.add_child(_server)

    v.add_child(Control.new())
    var connect_btn := UI.primary_button("접속하기")
    connect_btn.pressed.connect(_on_connect_pressed)
    v.add_child(connect_btn)
    _buttons.append(connect_btn)

    # 개발용: 에디터/디버그 빌드에서만 표시 (릴리스·웹 빌드에선 숨김)
    if Net.is_dev_build():
        var local_btn := UI.secondary_button("이 PC에서 서버 열고 접속 (테스트)")
        local_btn.pressed.connect(_on_local_pressed)
        v.add_child(local_btn)
        _buttons.append(local_btn)

    var offline_btn := UI.plain_button("오프라인 연습 (봇과 대결)")
    offline_btn.pressed.connect(_on_offline_pressed.bind(offline_btn))
    v.add_child(offline_btn)
    _buttons.append(offline_btn)

    _status = UI.label("", 16, UI.MUTED)
    _status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    v.add_child(_status)

    Net.connected.connect(_on_connected)
    Net.connection_failed.connect(_on_failed)
    Net.login_result.connect(_on_login_result)
    _nick.grab_focus.call_deferred()


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


func _on_failed(reason: String) -> void:
    if _retry_left > 0:
        _retry_left -= 1
        await get_tree().create_timer(1.0).timeout
        Net.connect_to_server(_retry_url, _retry_name)
        return
    _set_busy(false)
    _set_status("%s: %s" % [_retry_name, reason], UI.DANGER)


func _on_login_result(ok: bool, message: String) -> void:
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
        b.disabled = busy
    _nick.editable = not busy
    _server.disabled = busy


func _set_status(text: String, color: Color) -> void:
    _status.text = text
    _status.add_theme_color_override("font_color", color)
