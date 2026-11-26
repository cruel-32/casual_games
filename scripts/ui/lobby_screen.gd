extends Control
## 2단계: 로비 — 방 목록(실시간, 게임 썸네일 카드), 방 만들기, 입장

const UI := preload("res://scripts/ui/ui_kit.gd")
const GameRegistry := preload("res://scripts/core/game_registry.gd")

var app: Node
var _grid: GridContainer
var _empty: Control
var _count_label: Label
var _dialog: Control
var _d_name: LineEdit
var _d_max: SpinBox
var _d_bots: CheckBox
var _d_game_index := 0
var _d_game_cards: Array[Button] = []
var _d_game_desc: Label


func _ready() -> void:
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for side in ["left", "right"]:
        margin.add_theme_constant_override("margin_" + side, 36)
    margin.add_theme_constant_override("margin_top", 20)
    margin.add_theme_constant_override("margin_bottom", 28)
    add_child(margin)
    var root := UI.vbox(16)
    margin.add_child(root)

    # 상단 바: 로고 · 내 정보 · 나가기
    var top := UI.hbox(12)
    root.add_child(top)
    var logo := UI.logo(40)
    top.add_child(logo)
    top.add_child(UI.spacer())
    var me_text := ("%s  ·  %s" % [Net.server_name, Net.nickname]) if Net.server_name != "" else Net.nickname
    var me := UI.badge("●  " + me_text, UI.BLUE)
    top.add_child(me)
    var snd := UI.sound_button()
    snd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    top.add_child(snd)
    var logout := UI.pill_button("나가기")
    logout.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
    _count_label = UI.heading("방 목록", 30)
    bar.add_child(_count_label)
    bar.add_child(UI.spacer())
    var refresh := UI.plain_button("새로고침")
    refresh.custom_minimum_size.x = 120
    refresh.pressed.connect(func(): Net.request_rooms())
    bar.add_child(refresh)
    var create := UI.cta_button("+  방 만들기")
    create.custom_minimum_size = Vector2(200, 54)
    create.add_theme_font_size_override("font_size", 23)
    create.pressed.connect(_open_dialog)
    bar.add_child(create)

    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    v.add_child(scroll)
    var pad := MarginContainer.new()          # 카드 그림자가 잘리지 않게 여백
    pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    pad.add_theme_constant_override("margin_bottom", 8)
    pad.add_theme_constant_override("margin_right", 6)
    scroll.add_child(pad)
    _grid = GridContainer.new()
    _grid.columns = 2
    _grid.add_theme_constant_override("h_separation", 14)
    _grid.add_theme_constant_override("v_separation", 14)
    _grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    pad.add_child(_grid)

    # 방이 없을 때: 캐릭터들 + 안내
    _empty = UI.vbox(10)
    _empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _empty.alignment = BoxContainer.ALIGNMENT_CENTER
    v.add_child(_empty)
    var faces := UI.hbox(-28)
    faces.alignment = BoxContainer.ALIGNMENT_CENTER
    for i in 5:
        var t := TextureRect.new()
        t.texture = UI.portrait(i)
        t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        t.custom_minimum_size = Vector2(110, 110)
        faces.add_child(t)
    _empty.add_child(faces)
    var el := UI.heading("열린 방이 없어요. 첫 방을 만들어 보세요!", 24, UI.MUTED)
    el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _empty.add_child(el)

    _build_dialog()
    Net.room_list_updated.connect(_on_rooms)
    _on_rooms(Net.rooms)
    Net.request_rooms()
    resized.connect(_update_columns)
    _update_columns()


func _exit_tree() -> void:
    Net.room_list_updated.disconnect(_on_rooms)


func _update_columns() -> void:
    if _grid:
        _grid.columns = 2 if size.x >= 1100 else 1


func _on_rooms(list: Array) -> void:
    for c in _grid.get_children():
        c.queue_free()
    _empty.visible = list.is_empty()
    _count_label.text = "방 목록  %d" % list.size()
    for r in list:
        _grid.add_child(_make_card(r))


func _make_card(r: Dictionary) -> Control:
    var module = GameRegistry.get_or_default(String(r.get("game", "")))
    var playing: bool = r.state == "playing"
    var full: bool = int(r.count) >= int(r.max)

    var card := PanelContainer.new()
    card.add_theme_stylebox_override("panel", UI.box(Color.WHITE, 18, 12, UI.INK, UI.OUTLINE, 4))
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var h := UI.hbox(14)
    card.add_child(h)

    h.add_child(UI.image_card(module.thumbnail(), Vector2(168, 96), module.accent))

    var info := UI.vbox(4)
    info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    info.alignment = BoxContainer.ALIGNMENT_CENTER
    h.add_child(info)
    var name_l := UI.heading(String(r.name), 24)
    name_l.clip_text = true
    name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    info.add_child(name_l)
    info.add_child(UI.label("%s  ·  방장 %s" % [module.display_name, r.host_nick], 15, UI.MUTED))
    var chips := UI.hbox(6)
    info.add_child(chips)
    chips.add_child(UI.badge("게임 중" if playing else ("가득 참" if full else "대기 중"),
            UI.DANGER if playing else (UI.MUTED if full else UI.GOOD)))
    if r.bot_fill:
        chips.add_child(UI.badge("봇 채우기", UI.SECONDARY))

    var right := UI.vbox(6)
    right.alignment = BoxContainer.ALIGNMENT_CENTER
    h.add_child(right)
    var count := UI.heading("%d / %d" % [r.count, r.max], 26)
    count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    right.add_child(count)
    var join := UI.secondary_button("입장")
    join.custom_minimum_size = Vector2(110, 48)
    join.disabled = playing or full
    var rid := int(r.id)
    join.pressed.connect(func(): Net.join_room(rid))
    right.add_child(join)
    return card


# ---------------------------------------------------------------- 방 만들기 창
func _build_dialog() -> void:
    _dialog = ColorRect.new()
    (_dialog as ColorRect).color = Color(UI.INK, 0.55)
    _dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _dialog.visible = false
    add_child(_dialog)
    var v := UI.centered_panel(_dialog, 520)

    v.add_child(UI.heading("방 만들기", 30))

    # 게임 고르기: 썸네일 카드
    var games := UI.hbox(10)
    v.add_child(games)
    var mods: Array = GameRegistry.all()
    for i in mods.size():
        var m = mods[i]
        var b := Button.new()
        b.toggle_mode = true
        b.custom_minimum_size = Vector2(150, 0)
        b.add_theme_stylebox_override("normal", UI.box(Color.WHITE, 14, 6, UI.INK, 2, 4))
        b.add_theme_stylebox_override("hover", UI.box(Color(1.0, 0.97, 0.9), 14, 6, UI.INK, 2, 4))
        b.add_theme_stylebox_override("pressed", UI.box(Color(1.0, 0.9, 0.62), 14, 6, UI.TEAL, 4, 4))
        b.add_theme_stylebox_override("hover_pressed", UI.box(Color(1.0, 0.9, 0.62), 14, 6, UI.TEAL, 4, 4))
        b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
        var bv := UI.vbox(4)
        bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
        bv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
        b.add_child(bv)
        var img := UI.image_card(m.thumbnail(), Vector2(138, 78), m.accent, 10)
        img.mouse_filter = Control.MOUSE_FILTER_IGNORE
        bv.add_child(img)
        var nl := UI.heading(m.display_name, 17)
        nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        bv.add_child(nl)
        b.custom_minimum_size.y = 128
        b.pressed.connect(_select_game.bind(i))
        games.add_child(b)
        _d_game_cards.append(b)
    _d_game_desc = UI.label("", 15, UI.MUTED)
    _d_game_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    v.add_child(_d_game_desc)

    v.add_child(UI.heading("방 이름", 18, UI.MUTED))
    _d_name = UI.line_edit("방 이름", "", Net.ROOM_NAME_MAX)
    _d_name.text_submitted.connect(func(_t): _on_create())
    v.add_child(_d_name)

    var row := UI.hbox(14)
    v.add_child(row)
    var mv := UI.vbox(6)
    row.add_child(mv)
    mv.add_child(UI.heading("최대 인원", 18, UI.MUTED))
    _d_max = SpinBox.new()
    _d_max.min_value = 2
    _d_max.max_value = Net.MAX_PLAYERS_LIMIT
    _d_max.value = 8
    _d_max.suffix = "명"
    _d_max.custom_minimum_size = Vector2(150, 52)
    mv.add_child(_d_max)
    _d_bots = CheckBox.new()
    _d_bots.text = "빈 자리를 봇으로 채우기"
    _d_bots.add_theme_font_size_override("font_size", 18)
    _d_bots.size_flags_vertical = Control.SIZE_SHRINK_END
    row.add_child(_d_bots)

    var h := UI.hbox(10)
    v.add_child(h)
    var cancel := UI.plain_button("취소")
    cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    cancel.pressed.connect(func(): _dialog.visible = false)
    h.add_child(cancel)
    var ok := UI.cta_button("만들기")
    ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    ok.pressed.connect(_on_create)
    h.add_child(ok)


func _dialog_module():
    return GameRegistry.all()[clampi(_d_game_index, 0, GameRegistry.all().size() - 1)]


func _select_game(i: int) -> void:
    _d_game_index = i
    for k in _d_game_cards.size():
        _d_game_cards[k].set_pressed_no_signal(k == i)
    var m = _dialog_module()
    _d_game_desc.text = m.description
    _d_max.max_value = mini(Net.MAX_PLAYERS_LIMIT, m.max_players)
    _d_bots.disabled = not m.supports_bots
    if not m.supports_bots:
        _d_bots.button_pressed = false


func _open_dialog() -> void:
    _select_game(_d_game_index)
    _d_name.text = "%s의 방" % Net.nickname
    _dialog.visible = true
    if not Fighter.touch_device():
        _d_name.grab_focus()
        _d_name.select_all()


func _on_create() -> void:
    _dialog.visible = false
    Net.create_room(_d_name.text, int(_d_max.value), _d_bots.button_pressed, _dialog_module().id)


func _on_logout() -> void:
    Net.disconnect_from_server()
    app.show_screen("title")
