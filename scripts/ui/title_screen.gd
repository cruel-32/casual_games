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
var _kids: Array[TextureRect] = []
var _t := 0.0


func _ready() -> void:
    # 오른쪽 위: 메뉴 버튼
    var top := UI.hbox(10)
    top.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 18)
    top.grow_horizontal = Control.GROW_DIRECTION_BEGIN
    add_child(top)
    # 개발용: 에디터/디버그 빌드에서만 표시 (릴리스·웹 빌드에선 숨김)
    if Net.is_dev_build():
        var local_btn := UI.pill_button("이 PC 서버로 테스트", UI.BLUE)
        local_btn.pressed.connect(_on_local_pressed)
        top.add_child(local_btn)
        _buttons.append(local_btn)
    var offline_btn := UI.pill_button("혼자 연습")
    offline_btn.pressed.connect(_on_offline_pressed.bind(offline_btn))
    top.add_child(offline_btn)
    _buttons.append(offline_btn)
    var sound_btn := UI.pill_button("", UI.BLUE)
    var set_sound_text := func(): sound_btn.text = "소리 켬" if Sfx.enabled else "소리 끔"
    set_sound_text.call()
    sound_btn.pressed.connect(func():
        Sfx.set_enabled(not Sfx.enabled)
        set_sound_text.call())
    top.add_child(sound_btn)
    var help_btn := UI.pill_button("조작법", UI.YELLOW, UI.INK)
    help_btn.pressed.connect(_show_help)
    top.add_child(help_btn)

    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    center.offset_bottom = -110          # 아래 체크 띠 위에 놓이게
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(center)
    var col := UI.vbox(18)
    col.alignment = BoxContainer.ALIGNMENT_CENTER
    center.add_child(col)

    # 로고 양옆으로 아이들 (통통 튀는 초상화)
    var hero := UI.hbox(26)
    hero.alignment = BoxContainer.ALIGNMENT_CENTER
    col.add_child(hero)
    var left := UI.hbox(-34)
    hero.add_child(left)
    hero.add_child(UI.logo(84))
    var right := UI.hbox(-34)
    hero.add_child(right)
    var kids := [0, 1, 4, 2, 3, 6]
    for i in kids.size():
        var t := TextureRect.new()
        t.texture = UI.portrait(kids[i])
        t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        t.custom_minimum_size = Vector2(118, 150)
        t.flip_h = i >= 3
        (left if i < 3 else right).add_child(t)
        _kids.append(t)

    var tag_row := UI.hbox(0)
    tag_row.alignment = BoxContainer.ALIGNMENT_CENTER
    col.add_child(tag_row)
    var tag := UI.badge("떨어지는 돌을 피하고, 밀쳐내고, 끝까지 살아남자!", UI.INK, UI.CREAM)
    (tag.get_child(0) as Label).add_theme_font_size_override("font_size", 19)
    tag_row.add_child(tag)

    # 접속 카드: 서버 · 닉네임 · 출발!
    var card_row := UI.hbox(0)
    card_row.alignment = BoxContainer.ALIGNMENT_CENTER
    col.add_child(card_row)
    var card := PanelContainer.new()
    card.custom_minimum_size.x = 560
    card_row.add_child(card)
    var cv := UI.vbox(12)
    card.add_child(cv)

    var server_row := UI.hbox(10)
    cv.add_child(server_row)
    server_row.add_child(UI.badge("서버", UI.BLUE))
    # 서버 선택: 이름만 보여주고 주소는 숨긴다
    _server = OptionButton.new()
    _server.custom_minimum_size = Vector2(200, 46)
    _server.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _servers = Net.available_servers()
    var saved := String(app.load_setting("server_name", ""))
    for i in _servers.size():
        _server.add_item(String(_servers[i].name), i)
        if _servers[i].name == saved:
            _server.select(i)
    server_row.add_child(_server)

    var entry := UI.hbox(12)
    cv.add_child(entry)
    _nick = UI.line_edit("닉네임 (2~12자)", String(app.load_setting("nickname", "")), Net.NICK_MAX)
    _nick.custom_minimum_size = Vector2(0, 62)
    _nick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _nick.add_theme_font_size_override("font_size", 22)
    _nick.text_submitted.connect(func(_t): _on_connect_pressed())
    entry.add_child(_nick)
    var connect_btn := UI.cta_button("출발!")
    connect_btn.custom_minimum_size = Vector2(150, 66)
    connect_btn.add_theme_font_size_override("font_size", 30)
    connect_btn.pressed.connect(_on_connect_pressed)
    entry.add_child(connect_btn)
    _buttons.append(connect_btn)

    _status = UI.label("", 16, UI.MUTED)
    _status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _status.custom_minimum_size = Vector2(0, 24)
    _status.visible = false
    cv.add_child(_status)

    _build_help()
    if OS.has_feature("web"):
        _build_web_promo()

    Net.connected.connect(_on_connected)
    Net.connection_failed.connect(_on_failed)
    Net.login_result.connect(_on_login_result)
    if not Fighter.touch_device():
        _nick.grab_focus.call_deferred()


# ---- 웹 체험판 안내: PC는 Windows 다운로드, 모바일은 앱 설치로 유도
# 주소는 웹 서버의 /links.json (deploy/web-landing/links.json)
var _promo: PanelContainer
var _promo_text: Label
var _promo_btn: Button
var _promo_url := ""


func _build_web_promo() -> void:
    _promo = PanelContainer.new()
    _promo.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 18)
    _promo.custom_minimum_size.x = 300
    _promo.visible = false
    var sb := UI.box(UI.CREAM, 18, 16, UI.INK, UI.OUTLINE, 6)
    _promo.add_theme_stylebox_override("panel", sb)
    add_child(_promo)
    var v := UI.vbox(8)
    _promo.add_child(v)
    var head := UI.hbox(8)
    v.add_child(head)
    head.add_child(UI.badge("웹 체험판", UI.RED))
    _promo_text = UI.label("", 15, UI.MUTED)
    _promo_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _promo_text.custom_minimum_size.x = 268
    v.add_child(_promo_text)
    _promo_btn = UI.cta_button("")
    _promo_btn.custom_minimum_size.y = 50
    _promo_btn.add_theme_font_size_override("font_size", 21)
    _promo_btn.pressed.connect(func():
        if _promo_url != "":
            # 같은 탭에서 이동 (새 창은 팝업 차단될 수 있음). zip 은 다운로드만 되고 페이지는 그대로
            JavaScriptBridge.eval("window.location.href = %s;" % JSON.stringify(_promo_url)))
    v.add_child(_promo_btn)

    var origin := str(JavaScriptBridge.eval("window.location.origin", true))
    var http := HTTPRequest.new()
    add_child(http)
    http.request_completed.connect(func(result, code, _h, body):
        var links: Dictionary = {}
        if result == HTTPRequest.RESULT_SUCCESS and code == 200:
            var d = JSON.parse_string(body.get_string_from_utf8())
            if d is Dictionary:
                links = d
        _show_web_promo(links)
        http.queue_free())
    if http.request(origin + "/links.json") != OK:
        _show_web_promo({})


func _show_web_promo(links: Dictionary) -> void:
    var windows := String(links.get("windows", "/download/SmallPartyWorld-windows.zip"))
    if Fighter.touch_device():
        var ios := OS.has_feature("web_ios")
        var url := String(links.get("ios" if ios else "android", ""))
        if url == "":
            _promo_text.text = "모바일 앱을 준비하고 있어요. 앱이 나오면 더 부드럽게 즐길 수 있어요!"
            _promo_btn.visible = false
        else:
            _promo_text.text = "앱으로 설치하면 더 부드럽고 조작도 편해요."
            _promo_btn.text = "앱 설치하기"
            _promo_url = url
    elif OS.has_feature("web_windows"):
        _promo_text.text = "PC 버전이 훨씬 부드럽고 그래픽도 좋아요. 압축을 풀고 SmallPartyWorld.exe 실행!"
        _promo_btn.text = "PC 버전 다운로드"
        _promo_url = windows
    else:
        _promo_text.text = "PC 버전은 현재 Windows 전용이에요. 이 기기에서는 웹 체험판으로 즐겨 주세요."
        _promo_btn.visible = false
    _promo.visible = true


# ---- 조작법 창
var _help: Control


func _build_help() -> void:
    _help = ColorRect.new()
    (_help as ColorRect).color = Color(UI.INK, 0.55)
    _help.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _help.visible = false
    add_child(_help)
    var v := UI.centered_panel(_help, 560)
    v.add_child(UI.heading("조작법", 30))
    var rows := [
        ["이동", "WASD  ·  모바일: 왼쪽 화면 스틱"],
        ["시점", "마우스  ·  모바일: 오른쪽 화면 드래그 (버튼을 누른 채 끌어도 됨)"],
        ["점프", "Space  ·  모바일: 점프 버튼"],
        ["밀치기", "좌클릭/E 짧게 = 제자리 밀기, 길게 = 차징 돌진 (공중에서도 가능)"],
    ]
    for r in rows:
        var h := UI.hbox(14)
        var k := UI.badge(r[0], UI.BLUE)
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
    _status.visible = text != ""
    _status.add_theme_color_override("font_color", UI.RED if color == UI.DANGER else UI.MUTED)


## 아이들이 차례로 통통 뛴다
func _process(delta: float) -> void:
    _t += delta
    for i in _kids.size():
        var ph := _t * 3.2 - i * 0.55
        var hop := maxf(sin(ph), 0.0)
        _kids[i].pivot_offset = _kids[i].size * Vector2(0.5, 1.0)
        _kids[i].position.y = -hop * 16.0
        _kids[i].rotation = sin(ph * 0.5) * 0.04
