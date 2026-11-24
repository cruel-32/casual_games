extends RefCounted
## 메뉴 UI 공용 테마/위젯

const PRIMARY := Color(0.98, 0.52, 0.33)
const PRIMARY_HOVER := Color(1.0, 0.62, 0.43)
const PRIMARY_PRESSED := Color(0.88, 0.44, 0.27)
const SECONDARY := Color(0.33, 0.58, 0.95)
const SECONDARY_HOVER := Color(0.43, 0.66, 1.0)
const PANEL := Color(1, 1, 1, 0.94)
const TEXT := Color(0.17, 0.19, 0.27)
const MUTED := Color(0.47, 0.5, 0.6)
const GOOD := Color(0.27, 0.72, 0.43)
const DANGER := Color(0.88, 0.33, 0.33)
const SOFT := Color(0.94, 0.95, 0.98)


static func box(color: Color, radius: int = 12, pad: int = 12, border_color: Color = Color(0, 0, 0, 0),
        border: int = 0, shadow: int = 0) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = color
    s.set_corner_radius_all(radius)
    s.content_margin_left = pad
    s.content_margin_right = pad
    s.content_margin_top = pad * 0.6
    s.content_margin_bottom = pad * 0.6
    if border > 0:
        s.border_color = border_color
        s.set_border_width_all(border)
    if shadow > 0:
        s.shadow_color = Color(0.1, 0.15, 0.3, 0.18)
        s.shadow_size = shadow
        s.shadow_offset = Vector2(0, shadow * 0.4)
    return s


static func make_theme() -> Theme:
    var t := Theme.new()
    t.default_font_size = 18

    t.set_color("font_color", "Label", TEXT)

    t.set_stylebox("normal", "Button", box(SOFT, 12, 16))
    t.set_stylebox("hover", "Button", box(Color(0.89, 0.91, 0.97), 12, 16))
    t.set_stylebox("pressed", "Button", box(Color(0.83, 0.86, 0.94), 12, 16))
    t.set_stylebox("disabled", "Button", box(Color(0.92, 0.92, 0.94, 0.7), 12, 16))
    t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
    t.set_color("font_color", "Button", TEXT)
    t.set_color("font_hover_color", "Button", TEXT)
    t.set_color("font_pressed_color", "Button", TEXT)
    t.set_color("font_focus_color", "Button", TEXT)
    t.set_color("font_disabled_color", "Button", Color(0.6, 0.62, 0.7))

    t.set_stylebox("normal", "LineEdit", box(Color.WHITE, 10, 12, Color(0.8, 0.83, 0.9), 2))
    t.set_stylebox("focus", "LineEdit", box(Color.WHITE, 10, 12, PRIMARY, 2))
    t.set_stylebox("read_only", "LineEdit", box(SOFT, 10, 12, Color(0.85, 0.87, 0.92), 2))
    t.set_color("font_color", "LineEdit", TEXT)
    t.set_color("font_placeholder_color", "LineEdit", Color(0.6, 0.63, 0.72))
    t.set_color("caret_color", "LineEdit", PRIMARY)

    t.set_stylebox("panel", "PanelContainer", box(PANEL, 20, 24, Color(0, 0, 0, 0), 0, 14))

    t.set_color("font_color", "CheckBox", TEXT)
    t.set_color("font_hover_color", "CheckBox", TEXT)
    t.set_color("font_pressed_color", "CheckBox", TEXT)
    t.set_stylebox("normal", "CheckBox", StyleBoxEmpty.new())
    t.set_stylebox("hover", "CheckBox", StyleBoxEmpty.new())
    t.set_stylebox("pressed", "CheckBox", StyleBoxEmpty.new())
    t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())

    t.set_color("default_color", "RichTextLabel", TEXT)
    t.set_stylebox("normal", "RichTextLabel", box(SOFT, 10, 12))
    t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
    return t


static func colored_button(text: String, color: Color, hover: Color, pressed: Color = Color(0, 0, 0, 0)) -> Button:
    var b := Button.new()
    b.text = text
    b.add_theme_stylebox_override("normal", box(color, 12, 18))
    b.add_theme_stylebox_override("hover", box(hover, 12, 18))
    b.add_theme_stylebox_override("pressed", box(pressed if pressed.a > 0 else color.darkened(0.1), 12, 18))
    for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
        b.add_theme_color_override(k, Color.WHITE)
    b.custom_minimum_size.y = 46
    return b


static func primary_button(text: String) -> Button:
    return colored_button(text, PRIMARY, PRIMARY_HOVER, PRIMARY_PRESSED)


static func secondary_button(text: String) -> Button:
    return colored_button(text, SECONDARY, SECONDARY_HOVER)


static func plain_button(text: String) -> Button:
    var b := Button.new()
    b.text = text
    b.custom_minimum_size.y = 46
    return b


static func label(text: String, size: int = 18, color: Color = TEXT) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", color)
    return l


static func title(text: String, size: int = 56) -> Label:
    var l := label(text, size, Color.WHITE)
    l.add_theme_color_override("font_outline_color", Color(0.15, 0.25, 0.45, 0.55))
    l.add_theme_constant_override("outline_size", 12)
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    return l


static func badge(text: String, color: Color) -> PanelContainer:
    var p := PanelContainer.new()
    p.add_theme_stylebox_override("panel", box(color, 8, 10))
    var l := label(text, 14, Color.WHITE)
    p.add_child(l)
    return p


static func line_edit(placeholder: String, text: String = "", max_len: int = 0) -> LineEdit:
    var e := LineEdit.new()
    e.placeholder_text = placeholder
    e.text = text
    if max_len > 0:
        e.max_length = max_len
    e.custom_minimum_size.y = 46
    return e


static func vbox(sep: int = 12) -> VBoxContainer:
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", sep)
    return v


static func hbox(sep: int = 12) -> HBoxContainer:
    var h := HBoxContainer.new()
    h.add_theme_constant_override("separation", sep)
    return h


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
