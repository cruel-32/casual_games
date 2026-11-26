extends PanelContainer
## 새 버전 안내 카드 (첫 화면 접속 카드 아래). Updater 상태에 따라 스스로 보였다 숨었다 한다.
##   [새 버전] 0.2.0 → 0.3.0  바뀐 점 한두 줄      [업데이트]
## min_supported 보다 낮으면 "업데이트해야 온라인으로 할 수 있어요" 를 빨갛게 띄운다.

const UI := preload("res://scripts/ui/ui_kit.gd")

var _badge: PanelContainer
var _title: Label
var _notes: Label
var _warn: Label
var _btn: Button
var _bar: ProgressBar


func _ready() -> void:
    visible = false
    add_theme_stylebox_override("panel", UI.box(UI.CREAM, 18, 16, UI.INK, UI.OUTLINE, 6))
    add_to_group("touch_block")
    var row := UI.hbox(14)
    add_child(row)
    var v := UI.vbox(4)
    v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(v)
    var head := UI.hbox(8)
    v.add_child(head)
    _badge = UI.badge("새 버전", UI.TEAL)
    head.add_child(_badge)
    _title = UI.label("", 17, UI.INK)
    _title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    head.add_child(_title)
    _notes = UI.label("", 14, UI.MUTED)
    _notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    v.add_child(_notes)
    _warn = UI.label("", 14, UI.DANGER)
    _warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    v.add_child(_warn)
    _bar = ProgressBar.new()
    _bar.custom_minimum_size.y = 10
    _bar.show_percentage = false
    _bar.max_value = 1.0
    _bar.visible = false
    v.add_child(_bar)
    _btn = UI.cta_button("업데이트")
    _btn.custom_minimum_size = Vector2(150, 56)
    _btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _btn.add_theme_font_size_override("font_size", 21)
    _btn.pressed.connect(func(): Updater.start())
    row.add_child(_btn)
    Updater.checked.connect(_refresh)
    Updater.progress.connect(func(r: float): _bar.value = r)
    _refresh()


func _refresh() -> void:
    visible = Updater.has_update()
    if not visible:
        return
    _title.text = "%s → %s" % [Updater.current_version(), Updater.latest]
    var lines := Updater.notes()
    var shown := PackedStringArray()
    for i in mini(lines.size(), 2):
        shown.append(lines[i])
    if lines.size() > 2:
        shown.append("그 밖에 %d가지" % (lines.size() - 2))
    _notes.text = " · ".join(shown)
    _notes.visible = not shown.is_empty()
    var st: int = Updater.state
    if st == Updater.State.FAILED:
        _warn.text = Updater.message
    elif st == Updater.State.READY:
        _warn.text = "다 받았어요. 다시 시작하면 새 버전으로 바뀌어요"
    elif Updater.required:
        _warn.text = "업데이트해야 온라인 접속이 돼요 (혼자 연습은 가능)"
    else:
        _warn.text = ""
    _warn.add_theme_color_override("font_color", UI.TEAL if st == Updater.State.READY else UI.DANGER)
    _warn.visible = _warn.text != ""
    _bar.visible = st == Updater.State.DOWNLOADING
    _btn.text = Updater.button_text()
    _btn.disabled = st == Updater.State.DOWNLOADING or Updater.method() == ""
