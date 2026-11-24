extends RefCounted
## 메뉴 UI 공용 테마/위젯 — 카툰풍 (두꺼운 진한 외곽선 + 아래로 떨어지는 단단한 그림자)
##  - 제목·버튼 글꼴: Black Han Sans (fonts/BlackHanSans-Regular.ttf, SIL OFL)
##  - 본문 글꼴: Pretendard SemiBold (프로젝트 기본 글꼴)

const DISPLAY_FONT := preload("res://fonts/BlackHanSans-Regular.ttf")
## 본문 글꼴. Black Han Sans 에 없는 기호(● ★ · … — →)는 이 글꼴로 대신 그린다
const BODY_FONT := preload("res://fonts/Pretendard-SemiBold.otf")

const INK := Color(0.11, 0.12, 0.20)              # 외곽선·그림자
const CTA := Color(1.0, 0.82, 0.18)               # 가장 중요한 버튼 (노랑)
const CTA_HOVER := Color(1.0, 0.88, 0.38)
const PRIMARY := Color(1.0, 0.47, 0.32)           # 코랄
const PRIMARY_HOVER := Color(1.0, 0.58, 0.44)
const PRIMARY_PRESSED := Color(0.9, 0.4, 0.27)
const SECONDARY := Color(0.24, 0.58, 1.0)         # 파랑
const SECONDARY_HOVER := Color(0.4, 0.68, 1.0)
const GOOD := Color(0.24, 0.76, 0.42)
const DANGER := Color(0.92, 0.3, 0.3)
const PANEL := Color(1, 1, 1, 0.97)
const TEXT := Color(0.13, 0.14, 0.22)
const MUTED := Color(0.45, 0.48, 0.58)
const SOFT := Color(0.93, 0.95, 0.99)

const OUTLINE := 3
const DROP := 5            # 버튼 그림자 높이


## 둥근 상자. border/shadow 를 주면 카툰풍 외곽선·단단한 그림자
static func box(color: Color, radius: int = 12, pad: int = 12, border_color: Color = Color(0, 0, 0, 0),
        border: int = 0, shadow: int = 0) -> StyleBoxFlat:
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
    if shadow > 0:
        s.shadow_color = Color(INK.r, INK.g, INK.b, 0.9)
        s.shadow_size = 1
        s.shadow_offset = Vector2(0, shadow)
    return s


## 카툰 버튼 상태 상자. down: 눌린 상태(그림자가 줄고 살짝 내려앉은 느낌)
static func toon_box(color: Color, radius: int = 14, pad: int = 18, down: bool = false) -> StyleBoxFlat:
    var s := box(color, radius, pad, INK, OUTLINE, 2 if down else DROP)
    s.content_margin_top = pad * 0.5 + (3 if down else 0)
    s.content_margin_bottom = pad * 0.5 + (0 if down else 3)
    return s


static func _style_button(b: Control, kind: String, color: Color, hover: Color, font_color: Color, radius: int = 14) -> void:
    b.add_theme_stylebox_override("normal", toon_box(color, radius))
    b.add_theme_stylebox_override("hover", toon_box(hover, radius))
    b.add_theme_stylebox_override("pressed", toon_box(color.darkened(0.08), radius, 18, true))
    b.add_theme_stylebox_override("disabled", toon_box(Color(0.78, 0.8, 0.86), radius))
    b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
    for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
        b.add_theme_color_override(k, font_color)
    b.add_theme_color_override("font_disabled_color", Color(0.55, 0.57, 0.64))
    b.add_theme_font_override("font", DISPLAY_FONT)


## 제목 글꼴에 없는 글자를 본문 글꼴로 채우도록 연결 (안 하면 ●·★ 등이 네모/깨진 문자로 보임)
static func _link_font_fallbacks() -> void:
    var f: Font = DISPLAY_FONT
    if f.fallbacks.is_empty():
        f.fallbacks = [BODY_FONT]


static func make_theme() -> Theme:
    _link_font_fallbacks()
    var t := Theme.new()
    t.default_font_size = 18

    t.set_color("font_color", "Label", TEXT)

    # 기본 버튼 = 흰 카툰 버튼
    t.set_stylebox("normal", "Button", toon_box(Color.WHITE))
    t.set_stylebox("hover", "Button", toon_box(Color(0.93, 0.96, 1.0)))
    t.set_stylebox("pressed", "Button", toon_box(Color(0.88, 0.91, 0.97), 14, 18, true))
    t.set_stylebox("disabled", "Button", toon_box(Color(0.86, 0.87, 0.9)))
    t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
    t.set_font("font", "Button", DISPLAY_FONT)
    t.set_font_size("font_size", "Button", 20)
    for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
        t.set_color(k, "Button", TEXT)
    t.set_color("font_disabled_color", "Button", Color(0.6, 0.62, 0.7))

    # 드롭다운
    for st in ["normal", "hover", "pressed", "disabled"]:
        t.set_stylebox(st, "OptionButton", toon_box(Color.WHITE if st != "hover" else Color(0.93, 0.96, 1.0), 14, 18, st == "pressed"))
    t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
    t.set_font("font", "OptionButton", DISPLAY_FONT)
    t.set_font_size("font_size", "OptionButton", 19)
    for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
        t.set_color(k, "OptionButton", TEXT)
    t.set_stylebox("panel", "PopupMenu", box(Color.WHITE, 12, 8, INK, OUTLINE, 4))
    t.set_stylebox("hover", "PopupMenu", box(Color(1.0, 0.92, 0.6), 8, 8))
    t.set_color("font_color", "PopupMenu", TEXT)
    t.set_color("font_hover_color", "PopupMenu", TEXT)
    t.set_font_size("font_size", "PopupMenu", 19)

    # 입력칸
    t.set_stylebox("normal", "LineEdit", box(Color.WHITE, 14, 16, INK, OUTLINE, 0))
    t.set_stylebox("focus", "LineEdit", box(Color.WHITE, 14, 16, SECONDARY, OUTLINE + 1, 0))
    t.set_stylebox("read_only", "LineEdit", box(SOFT, 14, 16, Color(INK, 0.4), OUTLINE, 0))
    t.set_color("font_color", "LineEdit", TEXT)
    t.set_color("font_placeholder_color", "LineEdit", Color(0.6, 0.63, 0.72))
    t.set_color("caret_color", "LineEdit", SECONDARY)
    t.set_font_size("font_size", "LineEdit", 20)

    # 패널 = 흰 카드 + 진한 외곽선 + 그림자
    t.set_stylebox("panel", "PanelContainer", box(PANEL, 22, 24, INK, OUTLINE, 6))

    t.set_color("font_color", "CheckBox", TEXT)
    t.set_color("font_hover_color", "CheckBox", TEXT)
    t.set_color("font_pressed_color", "CheckBox", TEXT)
    t.set_color("font_hover_pressed_color", "CheckBox", TEXT)
    for st in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
        t.set_stylebox(st, "CheckBox", StyleBoxEmpty.new())

    t.set_color("default_color", "RichTextLabel", TEXT)
    t.set_stylebox("normal", "RichTextLabel", box(SOFT, 12, 12, Color(INK, 0.15), 2))
    t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())

    # 툴팁
    t.set_stylebox("panel", "TooltipPanel", box(INK, 8, 10))
    t.set_color("font_color", "TooltipLabel", Color.WHITE)
    return t


static func colored_button(text: String, color: Color, hover: Color, _pressed: Color = Color(0, 0, 0, 0),
        font_color: Color = Color.WHITE) -> Button:
    var b := Button.new()
    b.text = text
    _style_button(b, "", color, hover, font_color)
    b.custom_minimum_size.y = 50
    b.add_theme_font_size_override("font_size", 21)
    if font_color == Color.WHITE:
        b.add_theme_color_override("font_outline_color", Color(INK, 0.55))
        b.add_theme_constant_override("outline_size", 4)
    return b


## 가장 중요한 행동 (입장하기, 게임 시작, 만들기): 노랑 + 진한 글자
static func cta_button(text: String) -> Button:
    var b := colored_button(text, CTA, CTA_HOVER, Color(0, 0, 0, 0), INK)
    b.custom_minimum_size.y = 58
    b.add_theme_font_size_override("font_size", 26)
    return b


static func primary_button(text: String) -> Button:
    return colored_button(text, PRIMARY, PRIMARY_HOVER, PRIMARY_PRESSED)


static func secondary_button(text: String) -> Button:
    return colored_button(text, SECONDARY, SECONDARY_HOVER)


static func good_button(text: String) -> Button:
    return colored_button(text, GOOD, GOOD.lightened(0.15))


static func plain_button(text: String) -> Button:
    var b := Button.new()
    b.text = text
    b.custom_minimum_size.y = 50
    return b


## 작은 알약 버튼 (상단 메뉴: 조작법, 나가기 …)
static func pill_button(text: String, color: Color = Color.WHITE, font_color: Color = TEXT) -> Button:
    var b := Button.new()
    b.text = text
    _style_button(b, "", color, color.lightened(0.12) if color != Color.WHITE else Color(0.93, 0.96, 1.0), font_color, 22)
    for st in ["normal", "hover", "pressed", "disabled"]:
        var sb: StyleBoxFlat = b.get_theme_stylebox(st)
        sb.content_margin_left = 16
        sb.content_margin_right = 16
        sb.content_margin_top = 6 + (2 if st == "pressed" else 0)
        sb.content_margin_bottom = 8 - (2 if st == "pressed" else 0)
        sb.shadow_offset = Vector2(0, 1 if st == "pressed" else 3)
    b.add_theme_font_size_override("font_size", 16)
    return b


static func label(text: String, size: int = 18, color: Color = TEXT) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", color)
    return l


## 굵은 제목 글자 (Black Han Sans)
static func heading(text: String, size: int = 26, color: Color = TEXT) -> Label:
    var l := label(text, size, color)
    l.add_theme_font_override("font", DISPLAY_FONT)
    return l


## 배경 위에 띄우는 큰 제목: 흰 글자 + 진한 외곽선 + 아래 그림자
static func title(text: String, size: int = 56, color: Color = Color.WHITE) -> Label:
    var l := heading(text, size, color)
    outline(l, maxi(6, size / 7))
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    return l


static func outline(l: Label, width: int = 8) -> void:
    l.add_theme_color_override("font_outline_color", INK)
    l.add_theme_constant_override("outline_size", width)
    l.add_theme_color_override("font_shadow_color", INK)
    l.add_theme_constant_override("shadow_offset_x", 0)
    l.add_theme_constant_override("shadow_offset_y", maxi(3, width / 2))
    l.add_theme_constant_override("shadow_outline_size", width)


## 게임 로고: Small(파랑) Party(노랑) World(코랄)
static func logo(size: int = 88) -> HBoxContainer:
    var h := hbox(int(size * 0.22))
    h.alignment = BoxContainer.ALIGNMENT_CENTER
    for part in [["Small", Color(0.3, 0.68, 1.0)], ["Party", CTA], ["World", PRIMARY]]:
        var l := heading(part[0], size, part[1])
        outline(l, maxi(8, size / 6))
        h.add_child(l)
    return h


## 둥근 알약 배지 (상태 표시)
static func badge(text: String, color: Color, font_color: Color = Color.WHITE) -> PanelContainer:
    var p := PanelContainer.new()
    var sb := box(color, 20, 12, INK, 2, 0)
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
    var sb := box(bg, radius, 0, INK, OUTLINE, 0)
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
    var path := "res://ui/portraits/slot_%d.png" % (slot % 8) if slot >= 0 else "res://ui/portraits/me.png"
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
