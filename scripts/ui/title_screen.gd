extends Control
## 1단계: 닉네임 입력 + 서버 접속

const UI := preload("res://scripts/ui/ui_kit.gd")

var app: Node
var _nick: LineEdit
var _addr: LineEdit
var _status: Label
var _buttons: Array[Button] = []
var _pending_nick := ""
var _retry_left := 0
var _retry_url := ""


func _ready() -> void:
    var root := UI.vbox(28)
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.alignment = BoxContainer.ALIGNMENT_CENTER
    add_child(root)

    var title := UI.title("Small Party World", 64)
    root.add_child(title)
    var sub := UI.title("3D 돌피하기 대결", 24)
    root.add_child(sub)

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

    v.add_child(UI.label("서버 주소", 16, UI.MUTED))
    _addr = UI.line_edit("예: spwsv.cloudish.cloud  /  127.0.0.1:7777", String(app.load_setting("server_url", Net.DEFAULT_SERVER)))
    _addr.text_submitted.connect(func(_t): _on_connect_pressed())
    v.add_child(_addr)

    v.add_child(Control.new())
    var connect_btn := UI.primary_button("접속하기")
    connect_btn.pressed.connect(_on_connect_pressed)
    v.add_child(connect_btn)

    var local_btn := UI.secondary_button("이 PC에서 서버 열고 접속 (테스트)")
    local_btn.pressed.connect(_on_local_pressed)
    v.add_child(local_btn)

    var offline_btn := UI.plain_button("오프라인 연습 (봇과 대결)")
    offline_btn.pressed.connect(func(): app.start_offline_practice())
    v.add_child(offline_btn)
    _buttons = [connect_btn, local_btn, offline_btn]

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


func _local_port() -> int:
    # 주소 칸에 127.0.0.1:포트 를 적었으면 그 포트, 아니면 기본 포트
    var t := _addr.text.strip_edges()
    var idx := t.rfind(":")
    if (t.contains("127.0.0.1") or t.contains("localhost")) and idx > 0:
        var p := int(t.substr(idx + 1))
        if p > 0:
            return p
    return Net.DEFAULT_PORT


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
    _start_connect(Net.normalize_url(_addr.text), 0)


func _on_local_pressed() -> void:
    if not _check_nick():
        return
    var port := _local_port()
    if not app.start_local_server(port):
        _set_status("서버 프로세스를 시작하지 못했습니다", UI.DANGER)
        return
    _addr.text = "ws://127.0.0.1:%d" % port
    _set_status("로컬 서버를 여는 중…", UI.MUTED)
    _set_busy(true)
    # 서버가 뜰 때까지 잠시 기다린 뒤 몇 번 재시도
    await get_tree().create_timer(1.5).timeout
    _start_connect(_addr.text, 4)


func _start_connect(url: String, retries: int) -> void:
    _pending_nick = _nick.text.strip_edges()
    _retry_left = retries
    _retry_url = Net.normalize_url(url)
    app.save_setting("nickname", _pending_nick)
    app.save_setting("server_url", _addr.text.strip_edges())
    _set_status("%s 에 접속 중…" % _retry_url, UI.MUTED)
    _set_busy(true)
    Net.connect_to_server(_retry_url)


func _on_connected() -> void:
    _set_status("로그인 중…", UI.MUTED)
    Net.login(_pending_nick)


func _on_failed(reason: String) -> void:
    if _retry_left > 0:
        _retry_left -= 1
        await get_tree().create_timer(1.0).timeout
        Net.connect_to_server(_retry_url)
        return
    _set_busy(false)
    _set_status(reason, UI.DANGER)


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
    _addr.editable = not busy


func _set_status(text: String, color: Color) -> void:
    _status.text = text
    _status.add_theme_color_override("font_color", color)
