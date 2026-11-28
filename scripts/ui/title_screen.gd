extends Control
## 1단계: 닉네임 입력 + 서버 선택(이름만 노출) + 접속

const UI := preload("res://scripts/ui/ui_kit.gd")
const GameRegistry := preload("res://scripts/core/game_registry.gd")
const UpdatePanel := preload("res://scripts/ui/update_panel.gd")
const NewsUI := preload("res://scripts/ui/news_ui.gd")

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
var _card_row: HBoxContainer


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
    var news := NewsUI.new()
    news.app = app
    top.add_child(news.news_button)
    top.add_child(UI.sound_button())
    var help_btn := UI.pill_button("조작법", UI.YELLOW, UI.INK)
    help_btn.pressed.connect(_show_help)
    top.add_child(help_btn)
    var info_btn := UI.pill_button("정보")
    info_btn.pressed.connect(func(): _info.visible = true)
    top.add_child(info_btn)
    # PC 앱: 게임 끄기 (웹·모바일은 브라우저/OS 가 닫으므로 없음)
    if not OS.has_feature("web") and not OS.has_feature("mobile"):
        var quit_btn := UI.pill_button("게임 종료", UI.RED)
        quit_btn.pressed.connect(func(): get_tree().quit())
        top.add_child(quit_btn)

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
    var tag := UI.badge("피하고, 치고, 멈추고, 터뜨리고! 친구들과 한 판씩 파티 게임", UI.INK, UI.CREAM)
    (tag.get_child(0) as Label).add_theme_font_size_override("font_size", 19)
    tag_row.add_child(tag)

    # 접속 카드: 서버 · 닉네임 · 출발!
    var card_row := UI.hbox(0)
    card_row.alignment = BoxContainer.ALIGNMENT_CENTER
    col.add_child(card_row)
    _card_row = card_row
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

    # 계정: 온라인 대전은 구글·Apple 로그인 필요 (혼자 연습은 로그인 없이)
    _account_row = UI.hbox(10)
    cv.add_child(_account_row)
    Account.changed.connect(_refresh_account)
    Account.providers_loaded.connect(func(_l): _refresh_account())
    Account.login_waiting.connect(func(_p): _refresh_account())
    Account.login_failed.connect(func(m):
        _set_status(m, UI.DANGER)
        _refresh_account())
    _refresh_account()
    if Account.is_logged_in():
        Account.refresh()

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
    _build_info()
    if OS.has_feature("web"):
        _build_web_promo()
    _build_update_ui()
    add_child(news)                       # 공지 띠·소식 창 (맨 위에 그려지게 마지막에)

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
        ["3D 돌피하기", ""],
        ["이동", "WASD  ·  모바일: 왼쪽 화면 스틱. 캐릭터는 움직이는 방향을 바라봐요"],
        ["카메라", "마우스  ·  모바일: 오른쪽 화면 드래그 (버튼을 누른 채 끌어도 됨)"],
        ["점프", "Space  ·  모바일: 점프 버튼"],
        ["밀치기", "좌클릭/E 짧게 = 제자리 밀기, 길게 = 차징 돌진. 바라보는 방향으로 나가요"],
        ["뒷북의 달인", ""],
        ["둥", "Space 또는 F  ·  모바일: 화면 왼쪽 아래 큰 버튼 (주황 노트)"],
        ["딱", "Enter 또는 J  ·  모바일: 화면 오른쪽 아래 큰 버튼 (보라 노트)"],
        ["피버", "노란 노트는 누르고 있다가 끝 박자에 떼요"],
        ["무궁화 꽃이 피었습니다", ""],
        ["달리기", "돌피하기와 같은 조작. 술래가 외치는 동안(초록불)만 달리고, 돌아보면(빨간불) 손을 떼요"],
        ["크레이지 봄버", ""],
        ["폭탄", "좌클릭/E  ·  모바일: 던지기 버튼. 탭하면 발밑에 놓고, 누르고 있다가 떼면 멀리 던져요 (3×3 범위로 펑! 내 폭탄엔 안 맞아요)"],
        ["점프", "Space  ·  모바일: 점프 버튼. 블록 두 층까지 한 번에 올라가요"],
        ["카메라", "기본은 멀리서 내려다봐요. 마우스로 돌리고 휠로 당기거나 밀어요"],
        ["유령", "탈락하면 바깥 테두리를 돌며 던지기 키로 안쪽에 폭탄을 던져요"],
    ]
    for r in rows:
        if String(r[1]) == "":          # 게임 이름 (구역 제목)
            var sec := UI.label(r[0], 20, UI.INK)
            sec.add_theme_font_override("font", UI.DISPLAY_FONT)
            v.add_child(sec)
            continue
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


# ---- 계정 줄
var _account_row: HBoxContainer
const PROVIDER_COLORS := {"google": Color(0.26, 0.52, 0.96), "apple": Color(0.1, 0.1, 0.12)}


func _refresh_account() -> void:
    if _account_row == null:
        return
    for c in _account_row.get_children():
        c.queue_free()
    _account_row.add_child(UI.badge("계정", UI.BLUE))
    if Account.is_logged_in():
        var name := String(Account.info.get("provider_name", ""))
        var t := UI.label(("%s 계정으로 로그인됨" % name if name != "" else "로그인됨") + ("  ·  " + Account.plays_text() if Account.plays_text() != "" else ""), 16)
        t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        t.clip_text = true
        t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
        _account_row.add_child(t)
        var p: Dictionary = Account.info.get("plays", {})
        if Account.plays_left() == 0 and bool(p.get("ads_enabled", false)):
            var ad := UI.pill_button("광고 보고 +%d판" % int(p.get("ad_reward", 1)), UI.TEAL)
            ad.pressed.connect(_on_ad_pressed)
            _account_row.add_child(ad)
        var out := UI.pill_button("로그아웃", UI.MUTED)
        out.pressed.connect(func(): Account.logout())
        _account_row.add_child(out)
    elif Account.is_waiting():
        var t := UI.label("브라우저에서 로그인을 마치고 돌아와 주세요…", 16, UI.MUTED)
        t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _account_row.add_child(t)
        var cancel := UI.pill_button("취소", UI.MUTED)
        cancel.pressed.connect(func():
            Account.cancel_login()
            _refresh_account())
        _account_row.add_child(cancel)
    elif Account.providers.is_empty():
        var t := UI.label("로그인 서버에 연결하는 중… (혼자 연습은 로그인 없이 가능)", 15, UI.MUTED)
        t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _account_row.add_child(t)
    else:
        var t := UI.label("온라인 대전 로그인", 16, UI.MUTED)
        t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _account_row.add_child(t)
        for pv in Account.providers:
            var id := String(pv.id)
            var col: Color = PROVIDER_COLORS.get(id, UI.INK)
            var b := UI.pill_button(String(pv.name), col, Color.WHITE)
            b.pressed.connect(func():
                _set_status("", UI.MUTED)
                Account.start_login(id))
            _account_row.add_child(b)


func _on_ad_pressed() -> void:
    if not Ads.reward_done.is_connected(_on_ad_done):
        Ads.reward_done.connect(_on_ad_done, CONNECT_ONE_SHOT)
    Ads.show_rewarded()


func _on_ad_done(ok: bool, message: String) -> void:
    _set_status(message if message != "" else ("판수가 늘었어요!" if ok else ""), UI.MUTED if ok else UI.DANGER)
    if ok:
        await get_tree().create_timer(2.0).timeout      # 서버가 AdMob 확인을 받을 시간
        Account.refresh()


## 정보: 버전, 문의처, 개인정보처리방침·이용약관 (스토어 심사·법적 고지용)
const CONTACT_EMAIL := "cshee8508@gmail.com"
var _info: Control


func _build_info() -> void:
    _info = ColorRect.new()
    (_info as ColorRect).color = Color(UI.INK, 0.55)
    _info.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _info.visible = false
    add_child(_info)
    var v := UI.centered_panel(_info, 520)
    v.add_child(UI.heading("정보", 30))
    v.add_child(UI.label("Small Party World  v%s" % Boot.version(), 18))
    var mail := UI.label("문의·신고·데이터 삭제 요청: %s" % CONTACT_EMAIL, 16, UI.MUTED)
    mail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    v.add_child(mail)
    _info_account = UI.label("", 15, UI.MUTED)
    _info_account.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    v.add_child(_info_account)
    _info_delete = UI.secondary_button("계정 삭제")
    _info_delete.pressed.connect(_on_delete_account)
    v.add_child(_info_delete)
    var site: String = Updater.site
    var links := [
        ["개인정보처리방침", site + "/privacy/"],
        ["이용약관", site + "/terms/"],
        ["문의·지원", site + "/support/"],
        ["이메일 보내기", "mailto:" + CONTACT_EMAIL + "?subject=%5BSmall%20Party%20World%5D%20"],
    ]
    var grid := GridContainer.new()
    grid.columns = 2
    grid.add_theme_constant_override("h_separation", 10)
    grid.add_theme_constant_override("v_separation", 10)
    for l in links:
        var b := UI.secondary_button(l[0])
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        var url: String = l[1]
        b.pressed.connect(func(): OS.shell_open(url))
        grid.add_child(b)
    v.add_child(grid)
    var close := UI.cta_button("닫기")
    close.pressed.connect(func(): _info.visible = false)
    v.add_child(close)
    _info.visibility_changed.connect(_update_info_account)
    Account.changed.connect(_update_info_account)


var _info_account: Label
var _info_delete: Button
var _delete_armed := false


func _update_info_account() -> void:
    _delete_armed = false
    if Account.is_logged_in():
        _info_account.text = "계정 번호 %s (%s 로그인) — 문의·결제 확인 때 알려 주세요" % [String(Account.info.get("id", "…")), String(Account.info.get("provider_name", ""))]
        _info_delete.visible = true
        _info_delete.text = "계정 삭제"
    else:
        _info_account.text = "로그인하지 않았어요"
        _info_delete.visible = false


## 계정 삭제: 두 번 눌러야 지움 (판수 기록·로그인 정보 삭제, 되돌릴 수 없음)
func _on_delete_account() -> void:
    if not _delete_armed:
        _delete_armed = true
        _info_delete.text = "정말 삭제할까요? 한 번 더 누르면 삭제돼요"
        return
    _delete_armed = false
    _info_delete.disabled = true
    var ok := await Account.delete_account()
    _info_delete.disabled = false
    _info_account.text = "계정을 삭제했어요" if ok else "삭제하지 못했어요. 잠시 뒤 다시 시도하거나 문의해 주세요"
    _info_delete.visible = not ok


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
    if not Account.is_logged_in():
        _set_status("온라인 대전은 로그인이 필요해요. 위에서 로그인해 주세요 (혼자 연습은 로그인 없이 할 수 있어요)", UI.DANGER)
        return
    if Updater.required:
        _set_status("새 버전이 나왔어요. 왼쪽 아래 업데이트 버튼을 눌러 주세요 (혼자 연습은 가능)", UI.DANGER)
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


# ---- 버전 표시 + 새 버전 안내 (Updater)
func _build_update_ui() -> void:
    # 새 버전 카드: 접속 카드 바로 아래 (새 버전이 있을 때만 보임)
    var panel := UpdatePanel.new()
    panel.custom_minimum_size.x = 560
    var row := UI.hbox(0)
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    row.add_child(panel)
    _card_row.get_parent().add_child(row)
    _card_row.get_parent().move_child(row, _card_row.get_index() + 1)
    # 오른쪽 아래 작은 버전 표시
    var ver := UI.label("v" + Boot.version(), 14, UI.MUTED)
    ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
    ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
    ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
    ver.position.y -= 108                 # 아래 체크 띠 위
    ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(ver)
