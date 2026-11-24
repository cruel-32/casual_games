extends ColorRect
## 휴대폰·태블릿을 세로로 들었을 때 "가로로 돌려주세요" 안내 (가로가 되면 자동으로 사라짐)

const UI := preload("res://scripts/ui/ui_kit.gd")


func _ready() -> void:
    color = Color(0.08, 0.12, 0.22, 0.92)
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP     # 세로일 땐 뒤 화면 조작을 막음
    z_index = 100
    var l := UI.label("화면을 가로로 돌려 주세요\n\n가로 화면에서 플레이할 수 있습니다", 30, Color.WHITE)
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(l)
    visible = false


func _process(_delta: float) -> void:
    var s := DisplayServer.window_get_size()
    visible = Fighter.touch_device() and s.y > s.x
