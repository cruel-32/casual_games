extends RefCounted
## 메뉴 UI 공용 테마/위젯 — '레트로 장난감' 스타일
##  - 크림색 바탕, 원색(빨강·파랑·노랑·청록) 플라스틱 버튼: 같은 색의 진한 테두리 + 아래 두꺼운 턱(눌리면 내려감)
##  - 카드: 크림색 + 남색 테두리 + 오른쪽 아래로 비스듬한 반투명 그림자(스티커 느낌)
##  - 제목·버튼 글꼴: Jua (fonts/Jua-Regular.ttf, SIL OFL) / 본문: Pretendard SemiBold

const DISPLAY_FONT := preload("res://fonts/Jua-Regular.ttf")
## 본문 글꼴. Jua 에 없는 기호(● · … — → ×)와 드문 한글은 이 글꼴로 대신 그린다
const BODY_FONT := preload("res://fonts/Pretendard-SemiBold.otf")

const INK := Color(0.114, 0.208, 0.341)            # 남색: 글자·테두리
const CREAM := Color(1.0, 0.969, 0.91)
const RED := Color(0.902, 0.224, 0.275)
const BLUE := Color(0.271, 0.482, 0.616)
const YELLOW := Color(1.0, 0.718, 0.012)
const TEAL := Color(0.165, 0.616, 0.561)
const GREEN := Color(0.42, 0.69, 0.30)

const CTA := TEAL                                  # 가장 중요한 버튼 (출발, 게임 시작, 만들기)
const CTA_HOVER := Color(0.22, 0.70, 0.64)
const PRIMARY := RED
const PRIMARY_HOVER := Color(0.95, 0.33, 0.37)
const PRIMARY_PRESSED := Color(0.82, 0.18, 0.23)
const SECONDARY := BLUE
const SECONDARY_HOVER := Color(0.35, 0.57, 0.71)
const GOOD := GREEN
const DANGER := RED
const PANEL := CREAM
const TEXT := INK
const MUTED := Color(0.42, 0.47, 0.56)
const SOFT := Color(0.98, 0.93, 0.83)              # 카드 안 옅은 칸

const OUTLINE := 3
const LIP := 7             # 플라스틱 버튼 아래 턱 두께


## 둥근 상자. border 를 주면 테두리, sticker > 0 이면 오른쪽 아래로 비스듬한 그림자
static func box(color: Color, radius: int = 12, pad: int = 12, border_color: Color = Color(0, 0, 0, 0),
        border: int = 0, sticker: int = 0) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = color
    s.set_corner_radius_all(radius)
    s.content_margin_left = pad
    s.content_margin_right = pad
    s.content_margin_top = pad * 0.6
    s.content_margin_bottom = pad * 0.6
    s.anti_aliasing = true
    if border > 0:
        s.border_color = border_color
        s.set_border_width_all(border)
    if sticker > 0:
        s.shadow_color = Color(INK, 0.22)
        s.shadow_size = 1
        s.shadow_offset = Vector2(sticker, sticker)
    return s


## 플라스틱 버튼 상자: 같은 색의 진한 테두리 + 아래 두꺼운 턱. down: 눌린 상태(턱이 얇아지고 글자가 내려감)
static func toy_box(color: Color, radius: int = 24, pad: int = 20, down: bool = false) -> StyleBoxFlat:
    var s := box(color, radius, pad, color.darkened(0.32), OUTLINE)
    var lip := 3 if down else LIP
    s.border_width_bottom = lip
    s.content_margin_top = pad * 0.45 + (LIP - lip)
    s.content_margin_bottom = pad * 0.45
    return s


## (예전 이름 호환)
static func toon_box(color: Color, radius: int = 24, pad: int = 20, down: bool = false) -> StyleBoxFlat:
    return toy_box(color, radius, pad, down)


static func _style_button(b: Control, _kind: String, color: Color, hover: Color, font_color: Color, radius: int = 24) -> void:
    b.add_theme_stylebox_override("normal", toy_box(color, radius))
    b.add_theme_stylebox_override("hover", toy_box(hover, radius))
    b.add_theme_stylebox_override("pressed", toy_box(color.darkened(0.06), radius, 20, true))
    b.add_theme_stylebox_override("disabled", toy_box(Color(0.82, 0.8, 0.76), radius))
    b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
    for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
        b.add_theme_color_override(k, font_color)
    b.add_theme_color_override("font_disabled_color", Color(0.58, 0.56, 0.52))
    b.add_theme_font_override("font", DISPLAY_FONT)


## 제목 글꼴에 없는 글자를 본문 글꼴로 채우도록 연결 (안 하면 ●·… 등이 네모/깨진 문자로 보임)
static func _link_font_fallbacks() -> void:
    var f: Font = DISPLAY_FONT
    if f.fallbacks.is_empty():
        f.fallbacks = [BODY_FONT]


static func make_theme() -> Theme:
    _link_font_fallbacks()
    var t := Theme.new()
    t.default_font_size = 18

    t.set_color("font_color", "Label", TEXT)

    # 기본 버튼 = 크림색 플라스틱 버튼
    t.set_stylebox("normal", "Button", toy_box(Color(1.0, 0.99, 0.96)))
    t.set_stylebox("hover", "Button", toy_box(Color(1.0, 0.95, 0.84)))
    t.set_stylebox("pressed", "Button", toy_box(Color(0.97, 0.92, 0.82), 24, 20, true))
    t.set_stylebox("disabled", "Button", toy_box(Color(0.88, 0.86, 0.82)))
    t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
    t.set_font("font", "Button", DISPLAY_FONT)
    t.set_font_size("font_size", "Button", 20)
    for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
        t.set_color(k, "Button", TEXT)
    t.set_color("font_disabled_color", "Button", Color(0.6, 0.58, 0.54))

    # 드롭다운
    for st in ["normal", "hover", "pressed", "disabled"]:
        t.set_stylebox(st, "OptionButton", toy_box(Color(1.0, 0.99, 0.96) if st != "hover" else Color(1.0, 0.95, 0.84), 24, 20, st == "pressed"))
    t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
    t.set_font("font", "OptionButton", DISPLAY_FONT)
    t.set_font_size("font_size", "OptionButton", 19)
    for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
        t.set_color(k, "OptionButton", TEXT)
    t.set_stylebox("panel", "PopupMenu", box(CREAM, 14, 8, INK, OUTLINE, 5))
    t.set_stylebox("hover", "PopupMenu", box(YELLOW, 10, 8))
    t.set_color("font_color", "PopupMenu", TEXT)
    t.set_color("font_hover_color", "PopupMenu", TEXT)
    t.set_font_size("font_size", "PopupMenu", 19)

    # 입력칸
    t.set_stylebox("normal", "LineEdit", box(Color.WHITE, 28, 20, INK, OUTLINE, 0))
    t.set_stylebox("focus", "LineEdit", box(Color.WHITE, 28, 20, TEAL, OUTLINE + 1, 0))
    t.set_stylebox("read_only", "LineEdit", box(SOFT, 28, 20, Color(INK, 0.4), OUTLINE, 0))
    t.set_color("font_color", "LineEdit", TEXT)
    t.set_color("font_placeholder_color", "LineEdit", Color(0.62, 0.62, 0.62))
    t.set_color("caret_color", "LineEdit", RED)
    t.set_font_size("font_size", "LineEdit", 20)

    # 패널 = 크림색 카드 + 남색 테두리 + 비스듬한 스티커 그림자
    t.set_stylebox("panel", "PanelContainer", box(PANEL, 20, 24, INK, OUTLINE, 8))

    t.set_color("font_color", "CheckBox", TEXT)
    t.set_color("font_hover_color", "CheckBox", TEXT)
    t.set_color("font_pressed_color", "CheckBox", TEXT)
    t.set_color("font_hover_pressed_color", "CheckBox", TEXT)
    for st in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
        t.set_stylebox(st, "CheckBox", StyleBoxEmpty.new())

    t.set_color("default_color", "RichTextLabel", TEXT)
    t.set_stylebox("normal", "RichTextLabel", box(Color.WHITE, 14, 12, Color(INK, 0.25), 2))
    t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())

    # 툴팁
    t.set_stylebox("panel", "TooltipPanel", box(INK, 10, 10))
    t.set_color("font_color", "TooltipLabel", Color.WHITE)
    return t


static func colored_button(text: String, color: Color, hover: Color, _pressed: Color = Color(0, 0, 0, 0),
        font_color: Color = Color.WHITE) -> Button:
    var b := Button.new()
    b.text = text
    _style_button(b, "", color, hover, font_color)
    b.custom_minimum_size.y = 50
    b.add_theme_font_size_override("font_size", 21)
    return b


## 가장 중요한 행동 (출발, 게임 시작, 만들기): 청록 + 흰 글자
static func cta_button(text: String) -> Button:
    var b := colored_button(text, CTA, CTA_HOVER, Color(0, 0, 0, 0), Color.WHITE)
    b.custom_minimum_size.y = 58
    b.add_theme_font_size_override("font_size", 26)
    return b


static func primary_button(text: String) -> Button:
    return colored_button(text, PRIMARY, PRIMARY_HOVER, PRIMARY_PRESSED)


static func secondary_button(text: String) -> Button:
    return colored_button(text, SECONDARY, SECONDARY_HOVER)


static func good_button(text: String) -> Button:
    return colored_button(text, GOOD, GOOD.lightened(0.15))


static func yellow_button(text: String) -> Button:
    return colored_button(text, YELLOW, YELLOW.lightened(0.15), Color(0, 0, 0, 0), INK)


static func plain_button(text: String) -> Button:
    var b := Button.new()
    b.text = text
    b.custom_minimum_size.y = 50
    return b


## 소리 켜기/끄기 알약 버튼 (누르면 글자도 바뀜). 설정은 저장된다
static func sound_button() -> Button:
    var b := pill_button("", BLUE)
    var refresh := func(): b.text = "소리 켬" if Sfx.enabled else "소리 끔"
    refresh.call()
    b.pressed.connect(func():
        Sfx.set_enabled(not Sfx.enabled)
        refresh.call())
    return b


## 작은 알약 버튼 (메뉴: 조작법, 나가기 …). 기본 = 남색 + 크림 글자
static func pill_button(text: String, color: Color = INK, font_color: Color = CREAM) -> Button:
    var b := Button.new()
    b.text = text
    if color == Color.WHITE:
        color = Color(1.0, 0.99, 0.96)
        if font_color == CREAM:
            font_color = INK
    _style_button(b, "", color, color.lightened(0.12), font_color, 20)
    for st in ["normal", "hover", "pressed", "disabled"]:
        var sb: StyleBoxFlat = b.get_theme_stylebox(st)
        var down: bool = st == "pressed"
        sb.border_width_bottom = 2 if down else 5
        sb.content_margin_left = 16
        sb.content_margin_right = 16
        sb.content_margin_top = 5 + (3 if down else 0)
        sb.content_margin_bottom = 5
    b.add_theme_font_size_override("font_size", 16)
    return b


static func label(text: String, size: int = 18, color: Color = TEXT) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", color)
    return l


## 제목 글자 (Jua)
static func heading(text: String, size: int = 26, color: Color = TEXT) -> Label:
    var l := label(text, size, color)
    l.add_theme_font_override("font", DISPLAY_FONT)
    return l


## 크림 배경 위 큰 제목: 남색 글자 (외곽선 없음). 사진·3D 위에 띄울 땐 outline() 을 따로 건다
static func title(text: String, size: int = 56, color: Color = INK) -> Label:
    var l := heading(text, size, color)
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    return l


## 크림색 테두리 + 비스듬한 남색 그림자 (밝은 글자를 복잡한 배경 위에 띄울 때)
static func outline(l: Label, width: int = 8) -> void:
    l.add_theme_color_override("font_outline_color", INK)
    l.add_theme_constant_override("outline_size", width)
    l.add_theme_color_override("font_shadow_color", Color(INK, 0.45))
    l.add_theme_constant_override("shadow_offset_x", maxi(2, width / 3))
    l.add_theme_constant_override("shadow_offset_y", maxi(2, width / 3))
    l.add_theme_constant_override("shadow_outline_size", width)


## 게임 로고 (두 줄): "Small Party" (빨강·파랑) / "World" (노랑 + 남색 테두리), 살짝 기울임
static func logo(size: int = 88) -> Control:
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", -int(size * 0.28))
    v.alignment = BoxContainer.ALIGNMENT_CENTER
    var top := hbox(int(size * 0.18))
    top.alignment = BoxContainer.ALIGNMENT_CENTER
    v.add_child(top)
    for part in [["Small", RED], ["Party", BLUE]]:
        var l := heading(part[0], size, part[1])
        l.add_theme_color_override("font_shadow_color", Color(INK, 0.25))
        l.add_theme_constant_override("shadow_offset_x", maxi(3, size / 22))
        l.add_theme_constant_override("shadow_offset_y", maxi(3, size / 22))
        top.add_child(l)
    var w := heading("World", int(size * 1.12), YELLOW)
    w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    w.add_theme_color_override("font_outline_color", INK)
    w.add_theme_constant_override("outline_size", maxi(6, size / 9))
    w.add_theme_color_override("font_shadow_color", Color(INK, 0.35))
    w.add_theme_constant_override("shadow_offset_x", maxi(4, size / 16))
    w.add_theme_constant_override("shadow_offset_y", maxi(4, size / 16))
    w.add_theme_constant_override("shadow_outline_size", maxi(6, size / 9))
    v.add_child(w)
    return v


## 둥근 알약 배지 (상태 표시)
static func badge(text: String, color: Color, font_color: Color = Color.WHITE) -> PanelContainer:
    var p := PanelContainer.new()
    var sb := box(color, 20, 12)
    sb.content_margin_top = 3
    sb.content_margin_bottom = 4
    p.add_theme_stylebox_override("panel", sb)
    var l := heading(text, 15, font_color)
    p.add_child(l)
    p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    return p


static func line_edit(placeholder: String, text: String = "", max_len: int = 0) -> LineEdit:
    var e := LineEdit.new()
    e.placeholder_text = placeholder
    e.text = text
    if max_len > 0:
        e.max_length = max_len
    e.custom_minimum_size.y = 52
    return e


static func vbox(sep: int = 12) -> VBoxContainer:
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", sep)
    return v


static func hbox(sep: int = 12) -> HBoxContainer:
    var h := HBoxContainer.new()
    h.add_theme_constant_override("separation", sep)
    return h


static func spacer() -> Control:
    var c := Control.new()
    c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return c


## 이미지를 둥근 테두리 카드 안에 (모서리를 잘라 보여줌)
static func image_card(tex: Texture2D, min_size: Vector2, bg: Color = SOFT, radius: int = 14,
        stretch: TextureRect.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_COVERED) -> PanelContainer:
    var p := PanelContainer.new()
    var sb := box(bg, radius, 0, INK, OUTLINE)
    p.add_theme_stylebox_override("panel", sb)
    p.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
    p.custom_minimum_size = min_size
    if tex:
        var r := TextureRect.new()
        r.texture = tex
        r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        r.stretch_mode = stretch
        r.custom_minimum_size = min_size
        p.add_child(r)
    return p


## 캐릭터 초상화 (ui/portraits/slot_N.png — tools/render_assets.gd 로 생성)
static func portrait(slot: int) -> Texture2D:
    var path := "res://ui/portraits/slot_%d.png" % (slot % 12) if slot >= 0 else "res://ui/portraits/me.png"
    return load(path) if ResourceLoader.exists(path) else null


static func centered_panel(parent: Control, width: float) -> VBoxContainer:
    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    parent.add_child(center)
    var panel := PanelContainer.new()
    panel.custom_minimum_size.x = width
    center.add_child(panel)
    var v := vbox(14)
    panel.add_child(v)
    return v
