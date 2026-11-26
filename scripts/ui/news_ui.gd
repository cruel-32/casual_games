extends Control
## 공지·소식 (관리 페이지 https://spw.cloudish.cloud/admin/ 에서 등록 → /api/notices)
##  - 배너(banner)·점검 안내: 첫 화면 위쪽 띠 (닫기 가능)
##  - "소식" 버튼: 공지·패치 노트·팝업 목록 창. 안 읽은 게 있으면 버튼에 개수 표시
##  - 팝업(popup): 처음 한 번 자동으로 소식 창을 연다
## 읽은 공지는 기기 설정(app.save_setting)에 기억한다. 서버에 연결하지 못하면 조용히 숨는다.

const UI := preload("res://scripts/ui/ui_kit.gd")
const SITE := "https://spw.cloudish.cloud"     ## 개발용으로 SPW_SITE 환경 변수로 바꿀 수 있음

var app: Node                        ## load_setting / save_setting 을 가진 노드 (app.gd)
var news_button: Button              ## 상단 메뉴에 넣을 "소식" 버튼 (title_screen 이 붙인다)

var _notices: Array = []
var _banner: PanelContainer
var _banner_text: Label
var _banner_ids: Array = []
var _dialog: Control
var _list: VBoxContainer
var _http: HTTPRequest


func _init() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    news_button = UI.pill_button("소식", Color.WHITE)
    news_button.visible = false
    news_button.pressed.connect(open_news)


func _ready() -> void:
    _build_banner()
    _build_dialog()
    _http = HTTPRequest.new()
    _http.timeout = 8.0
    add_child(_http)
    _http.request_completed.connect(_on_loaded)
    var site := OS.get_environment("SPW_SITE") if OS.get_environment("SPW_SITE") != "" else SITE
    var url := "%s/api/notices?platform=%s&version=%s" % [site, platform(), Boot.version().uri_encode()]
    if _http.request(url) != OK:
        queue_free()


static func platform() -> String:
    if OS.has_feature("web"):
        return "web"
    if OS.has_feature("android"):
        return "android"
    if OS.has_feature("ios"):
        return "ios"
    return "pc"


func _on_loaded(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
    if result != HTTPRequest.RESULT_SUCCESS or code != 200:
        return
    var d = JSON.parse_string(body.get_string_from_utf8())
    if not d is Dictionary:
        return
    _notices = d.get("notices", [])
    var m: Dictionary = d.get("maintenance", {})
    # 위쪽 띠: 점검 안내 > 배너 공지
    var lines := PackedStringArray()
    _banner_ids.clear()
    if bool(m.get("on", false)):
        lines.append("서버 점검 중" + (": " + String(m.get("message", "")) if String(m.get("message", "")) != "" else ""))
    var closed: Array = _setting("news_banner_closed", [])
    for n in _notices:
        if n.kind == "banner" and not closed.has(int(n.id)):
            lines.append(String(n.title) + ("  " + String(n.body) if String(n.body) != "" else ""))
            _banner_ids.append(int(n.id))
    _banner_text.text = "\n".join(lines)
    _banner.visible = not lines.is_empty()
    _banner.add_theme_stylebox_override("panel", UI.box(UI.RED if bool(m.get("on", false)) else UI.YELLOW, 16, 14, UI.INK, UI.OUTLINE, 4))
    _banner_text.add_theme_color_override("font_color", UI.CREAM if bool(m.get("on", false)) else UI.INK)
    # 소식 버튼: 배너를 뺀 공지 개수 · 안 읽은 개수
    var listed := _listed()
    news_button.visible = not listed.is_empty()
    _update_button()
    # 팝업: 안 본 팝업이 있으면 한 번 연다
    var seen_popups: Array = _setting("news_popup_seen", [])
    for n in listed:
        if n.kind == "popup" and not seen_popups.has(int(n.id)):
            open_news()
            break


func _listed() -> Array:
    return _notices.filter(func(n): return n.kind != "banner")


func _update_button() -> void:
    var seen: Array = _setting("news_seen", [])
    var unread := 0
    for n in _listed():
        if not seen.has(int(n.id)):
            unread += 1
    news_button.text = "소식 %d" % unread if unread > 0 else "소식"


func open_news() -> void:
    for c in _list.get_children():
        c.queue_free()
    var seen: Array = _setting("news_seen", [])
    var popups: Array = _setting("news_popup_seen", [])
    for n in _listed():
        _list.add_child(_item(n, not seen.has(int(n.id))))
        if not seen.has(int(n.id)):
            seen.append(int(n.id))
        if n.kind == "popup" and not popups.has(int(n.id)):
            popups.append(int(n.id))
    _save("news_seen", seen.slice(-200))
    _save("news_popup_seen", popups.slice(-200))
    _update_button()
    _dialog.visible = true


func _item(n: Dictionary, unread: bool) -> Control:
    var box := PanelContainer.new()
    box.add_theme_stylebox_override("panel", UI.box(UI.SOFT, 14, 14))
    var v := UI.vbox(6)
    box.add_child(v)
    var head := UI.hbox(8)
    v.add_child(head)
    var kinds := {"notice": ["공지", UI.BLUE], "patch": ["패치 노트", UI.TEAL], "popup": ["알림", UI.RED]}
    var k: Array = kinds.get(n.kind, ["공지", UI.BLUE])
    head.add_child(UI.badge(k[0], k[1]))
    if unread:
        head.add_child(UI.badge("새 글", UI.RED))
    var title := UI.label(String(n.title), 19, UI.INK)
    title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(title)
    var date := UI.label(String(n.get("updated_at", "")).left(10), 13, UI.MUTED)
    head.add_child(date)
    if String(n.body) != "":
        var body := UI.label(String(n.body), 15, UI.TEXT)
        body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        v.add_child(body)
    return box


func _build_banner() -> void:
    _banner = PanelContainer.new()
    _banner.visible = false
    _banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 70)
    _banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
    _banner.add_to_group("touch_block")
    add_child(_banner)
    var row := UI.hbox(10)
    _banner.add_child(row)
    _banner_text = UI.label("", 16, UI.INK)
    _banner_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _banner_text.custom_minimum_size.x = 520
    _banner_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(_banner_text)
    var close := UI.pill_button("닫기", UI.INK)
    close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    close.pressed.connect(func():
        var closed: Array = _setting("news_banner_closed", [])
        for id in _banner_ids:
            if not closed.has(id):
                closed.append(id)
        _save("news_banner_closed", closed.slice(-200))
        _banner.visible = false)
    row.add_child(close)


func _build_dialog() -> void:
    _dialog = ColorRect.new()
    (_dialog as ColorRect).color = Color(UI.INK, 0.45)
    _dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _dialog.visible = false
    _dialog.add_to_group("touch_block")
    add_child(_dialog)
    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _dialog.add_child(center)
    var panel := PanelContainer.new()
    panel.add_theme_stylebox_override("panel", UI.box(UI.CREAM, 22, 22, UI.INK, UI.OUTLINE, 8))
    center.add_child(panel)
    var v := UI.vbox(12)
    panel.add_child(v)
    var head := UI.hbox(10)
    v.add_child(head)
    var t := UI.heading("소식", 28)
    t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(t)
    var close := UI.pill_button("닫기", UI.INK)
    close.pressed.connect(func(): _dialog.visible = false)
    head.add_child(close)
    var scroll := ScrollContainer.new()
    scroll.custom_minimum_size = Vector2(640, 420)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    v.add_child(scroll)
    _list = UI.vbox(10)
    _list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(_list)


func _setting(key: String, default_value: Variant) -> Variant:
    if app and app.has_method("load_setting"):
        var v = app.load_setting(key, default_value)
        return v if typeof(v) == typeof(default_value) else default_value
    return default_value


func _save(key: String, value: Variant) -> void:
    if app and app.has_method("save_setting"):
        app.save_setting(key, value)
