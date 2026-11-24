extends Control
## 2단계: 로비 — 방 목록(실시간), 방 만들기, 입장

const UI := preload("res://scripts/ui/ui_kit.gd")
const GameRegistry := preload("res://scripts/core/game_registry.gd")

var app: Node
var _list: VBoxContainer
var _empty: Label
var _count_label: Label
var _dialog: Control
var _d_name: LineEdit
var _d_max: SpinBox
var _d_bots: CheckBox
var _d_game: OptionButton
var _d_game_desc: Label


func _ready() -> void:
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 40)
    add_child(margin)
    var root := UI.vbox(18)
    margin.add_child(root)

    # 상단 바
    var top := UI.hbox(12)
    root.add_child(top)
    var t := UI.title("로비", 40)
    t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    top.add_child(t)
    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top.add_child(spacer)
    var me_text := ("%s  ·  ● %s" % [Net.server_name, Net.nickname]) if Net.server_name != "" else ("● %s" % Net.nickname)
    var me := UI.badge(me_text, Color(0.2, 0.3, 0.5, 0.6))
    me.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    top.add_child(me)
    var logout := UI.plain_button("접속 끊기")
    logout.pressed.connect(_on_logout)
    top.add_child(logout)

    # 본문 패널
    var panel := PanelContainer.new()
    panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(panel)
    var v := UI.vbox(14)
    panel.add_child(v)

    var bar := UI.hbox(10)
    v.add_child(bar)
    _count_label = UI.label("방 목록", 22)
    bar.add_child(_count_label)
    var s2 := Control.new()
    s2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bar.add_child(s2)
    var refresh := UI.plain_button("새로고침")
    refresh.pressed.connect(func(): Net.request_rooms())
    bar.add_child(refresh)
    var create := UI.primary_button("방 만들기")
    create.custom_minimum_size.x = 160
    create.pressed.connect(_open_dialog)
    bar.add_child(create)

    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    v.add_child(scroll)
    _list = UI.vbox(10)
    _list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(_list)

    _empty = UI.label("열린 방이 없습니다. 방을 만들어 보세요!", 20, UI.MUTED)
    _empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    v.add_child(_empty)

    _build_dialog()
    Net.room_list_updated.connect(_on_rooms)
    _on_rooms(Net.rooms)
    Net.request_rooms()


func _exit_tree() -> void:
    Net.room_list_updated.disconnect(_on_rooms)


func _on_rooms(list: Array) -> void:
    for c in _list.get_children():
        c.queue_free()
    _empty.visible = list.is_empty()
    _count_label.text = "방 목록 (%d)" % list.size()
    for r in list:
        _list.add_child(_make_row(r))


func _make_row(r: Dictionary) -> Control:
    var row := PanelContainer.new()
    row.add_theme_stylebox_override("panel", UI.box(UI.SOFT, 14, 18))
    var h := UI.hbox(14)
    row.add_child(h)

    var info := UI.vbox(2)
    info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    h.add_child(info)
    info.add_child(UI.label(String(r.name), 22))
    var sub := "%s  ·  방장 %s" % [GameRegistry.display_name(String(r.get("game", ""))), r.host_nick]
    if r.bot_fill:
        sub += "  ·  빈자리 봇 채우기"
    info.add_child(UI.label(sub, 15, UI.MUTED))

    var playing: bool = r.state == "playing"
    var full: bool = int(r.count) >= int(r.max)
    var state_badge := UI.badge("게임 중" if playing else ("가득 참" if full else "대기 중"),
            UI.DANGER if playing else (UI.MUTED if full else UI.GOOD))
    state_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    h.add_child(state_badge)

    var count := UI.label("%d / %d" % [r.count, r.max], 22)
    count.custom_minimum_size.x = 80
    count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    h.add_child(count)

    var join := UI.secondary_button("입장")
    join.custom_minimum_size.x = 110
    join.disabled = playing or full
    var rid := int(r.id)
    join.pressed.connect(func(): Net.join_room(rid))
    h.add_child(join)
    return row


# ---------------------------------------------------------------- 방 만들기 창
func _build_dialog() -> void:
    _dialog = ColorRect.new()
    (_dialog as ColorRect).color = Color(0.05, 0.08, 0.15, 0.45)
    _dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _dialog.visible = false
    add_child(_dialog)
    var v := UI.centered_panel(_dialog, 440)

    v.add_child(UI.label("방 만들기", 26))
    v.add_child(UI.label("게임", 16, UI.MUTED))
    _d_game = OptionButton.new()
    _d_game.custom_minimum_size.y = 46
    for m in GameRegistry.all():
        _d_game.add_item(m.display_name)
    _d_game.item_selected.connect(_on_dialog_game_changed)
    v.add_child(_d_game)
    _d_game_desc = UI.label("", 14, UI.MUTED)
    _d_game_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    v.add_child(_d_game_desc)
    v.add_child(UI.label("방 이름", 16, UI.MUTED))
    _d_name = UI.line_edit("방 이름", "", Net.ROOM_NAME_MAX)
    _d_name.text_submitted.connect(func(_t): _on_create())
    v.add_child(_d_name)

    v.add_child(UI.label("최대 인원 (2~%d명)" % Net.MAX_PLAYERS_LIMIT, 16, UI.MUTED))
    _d_max = SpinBox.new()
    _d_max.min_value = 2
    _d_max.max_value = Net.MAX_PLAYERS_LIMIT
    _d_max.value = 8
    _d_max.custom_minimum_size.y = 46
    v.add_child(_d_max)

    _d_bots = CheckBox.new()
    _d_bots.text = "빈 자리를 봇으로 채우기"
    v.add_child(_d_bots)

    var h := UI.hbox(10)
    v.add_child(h)
    var cancel := UI.plain_button("취소")
    cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    cancel.pressed.connect(func(): _dialog.visible = false)
    h.add_child(cancel)
    var ok := UI.primary_button("만들기")
    ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    ok.pressed.connect(_on_create)
    h.add_child(ok)


func _dialog_module():
    return GameRegistry.all()[maxi(_d_game.selected, 0)]


func _on_dialog_game_changed(_i: int) -> void:
    var m = _dialog_module()
    _d_game_desc.text = m.description
    _d_max.max_value = mini(Net.MAX_PLAYERS_LIMIT, m.max_players)
    _d_bots.disabled = not m.supports_bots
    if not m.supports_bots:
        _d_bots.button_pressed = false


func _open_dialog() -> void:
    _on_dialog_game_changed(_d_game.selected)
    _d_name.text = "%s의 방" % Net.nickname
    _dialog.visible = true
    _d_name.grab_focus()
    _d_name.select_all()


func _on_create() -> void:
    _dialog.visible = false
    Net.create_room(_d_name.text, int(_d_max.value), _d_bots.button_pressed, _dialog_module().id)


func _on_logout() -> void:
    Net.disconnect_from_server()
    app.show_screen("title")
