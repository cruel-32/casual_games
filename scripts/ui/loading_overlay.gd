extends CanvasLayer
## 게임을 여는 동안 보이는 "불러오는 중" 화면 (화면 전체를 살짝 어둡게 + 가운데 빙글빙글 도는 표시와 글자)
## 씬이 바뀌어도 남도록 루트 바로 아래에 붙는다. 경기 화면이 준비되면(시작 신호를 받으면) PartyGame 이 닫는다
##   LoadingOverlay.open(tree, "게임 불러오는 중…")   /   LoadingOverlay.close(tree)
## 씬을 바꾸기 전에 열고 두 프레임 기다려야 실제로 화면에 그려진 뒤 (멈춰 있는) 씬 불러오기가 시작된다

const UI := preload("res://scripts/ui/ui_kit.gd")
const NODE_NAME := "LoadingOverlay"

var _label: Label
var _spin: Control
var _t := 0.0


static func open(tree: SceneTree, text: String) -> void:
    var o: CanvasLayer = tree.root.get_node_or_null(NODE_NAME)
    if o == null:
        o = load("res://scripts/ui/loading_overlay.gd").new()
        o.name = NODE_NAME
        tree.root.add_child(o)
    o.call("set_text", text)


static func close(tree: SceneTree) -> void:
    var o: Node = tree.root.get_node_or_null(NODE_NAME)
    if o:
        o.queue_free()


static func is_open(tree: SceneTree) -> bool:
    return tree.root.get_node_or_null(NODE_NAME) != null


## 열고 화면에 그려질 때까지 기다림 (씬 바꾸기 전에 await)
static func open_and_wait(tree: SceneTree, text: String) -> void:
    open(tree, text)
    await tree.process_frame
    await tree.process_frame


func _init() -> void:
    layer = 120
    process_mode = Node.PROCESS_MODE_ALWAYS
    var dim := ColorRect.new()
    dim.color = Color(0.06, 0.08, 0.14, 0.55)
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(dim)
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(center)
    var panel := PanelContainer.new()
    panel.add_theme_stylebox_override("panel", UI.box(UI.CREAM, 22, 26, UI.INK, 3, 6))
    center.add_child(panel)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 18)
    panel.add_child(row)
    _spin = Control.new()
    _spin.custom_minimum_size = Vector2(46, 46)
    _spin.draw.connect(_draw_spin)
    row.add_child(_spin)
    _label = Label.new()
    _label.add_theme_font_override("font", UI.DISPLAY_FONT)
    _label.add_theme_font_size_override("font_size", 30)
    _label.add_theme_color_override("font_color", UI.INK)
    _label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    row.add_child(_label)


func set_text(text: String) -> void:
    _label.text = text


func _process(delta: float) -> void:
    _t += delta
    _spin.queue_redraw()
    # 아직 메뉴인데 오래 기다리면 (시작이 거절됨 등) 스스로 닫음
    var cur := get_tree().current_scene
    if _t > 10.0 and cur and cur.scene_file_path != "res://scenes/match.tscn":
        queue_free()


func _draw_spin() -> void:
    var c := _spin.size * 0.5
    var r := minf(c.x, c.y) - 4.0
    _spin.draw_arc(c, r, 0.0, TAU, 40, Color(UI.INK, 0.15), 7.0, true)
    var a := _t * 6.0
    _spin.draw_arc(c, r, a, a + PI * 0.65, 24, UI.YELLOW, 7.0, true)
    # 점 세 개가 차례로 커짐
    for i in 3:
        var k := 0.5 + 0.5 * sin(_t * 7.0 - i * 0.9)
        _spin.draw_circle(c + Vector2((i - 1) * 9.0, 0), 1.5 + k * 2.2, UI.INK)
