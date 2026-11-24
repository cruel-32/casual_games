extends Control
## 3단계: 방 — 참가자 슬롯(최대 12), 레디, 방장 설정/강퇴/위임, 채팅, 게임 시작

const UI := preload("res://scripts/ui/ui_kit.gd")
const SLOT_COLORS: Array[Color] = [
    Color(0.98, 0.55, 0.35), Color(0.85, 0.22, 0.22), Color(0.22, 0.42, 0.90), Color(0.95, 0.68, 0.08),
    Color(0.25, 0.65, 0.22), Color(0.55, 0.28, 0.85), Color(0.95, 0.45, 0.10), Color(0.10, 0.65, 0.70),
    Color(0.88, 0.30, 0.60), Color(0.45, 0.45, 0.55), Color(0.60, 0.40, 0.25), Color(0.30, 0.75, 0.95),
]

var app: Node
var _title: Label
var _state_badge_holder: HBoxContainer
var _grid: GridContainer
var _settings_box: VBoxContainer
var _chat_log: RichTextLabel
var _chat_input: LineEdit
var _status: Label
var _ready_btn: Button
var _start_btn: Button
var _playing_overlay: Control
var _s_name: LineEdit
var _s_max: SpinBox
var _s_bots: CheckBox
var _settings_mode := ""


func _ready() -> void:
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 32)
    add_child(margin)
    var root := UI.vbox(16)
    margin.add_child(root)

    # 상단 바
    var top := UI.hbox(12)
    root.add_child(top)
    _title = UI.title("", 36)
    _title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    top.add_child(_title)
    _state_badge_holder = UI.hbox(0)
    _state_badge_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    top.add_child(_state_badge_holder)
    var sp := Control.new()
    sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top.add_child(sp)
    var leave := UI.plain_button("방 나가기")
    leave.pressed.connect(func(): Net.leave_room())
    top.add_child(leave)

    # 본문: 왼쪽 슬롯 / 오른쪽 설정+채팅
    var body := UI.hbox(16)
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(body)

    var left := PanelContainer.new()
    left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.add_child(left)
    var lv := UI.vbox(12)
    left.add_child(lv)
    lv.add_child(UI.label("참가자", 22))
    _grid = GridContainer.new()
    _grid.columns = 4
    _grid.add_theme_constant_override("h_separation", 10)
    _grid.add_theme_constant_override("v_separation", 10)
    _grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    lv.add_child(_grid)

    var right := UI.vbox(16)
    right.custom_minimum_size.x = 360
    body.add_child(right)
    var sp_panel := PanelContainer.new()
    right.add_child(sp_panel)
    _settings_box = UI.vbox(10)
    sp_panel.add_child(_settings_box)

    var chat_panel := PanelContainer.new()
    chat_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    right.add_child(chat_panel)
    var cv := UI.vbox(8)
    chat_panel.add_child(cv)
    cv.add_child(UI.label("채팅", 20))
    _chat_log = RichTextLabel.new()
    _chat_log.bbcode_enabled = true
    _chat_log.scroll_following = true
    _chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _chat_log.add_theme_font_size_override("normal_font_size", 16)
    _chat_log.add_theme_font_size_override("bold_font_size", 16)
    cv.add_child(_chat_log)
    var ch := UI.hbox(8)
    cv.add_child(ch)
    _chat_input = UI.line_edit("메시지 입력 후 Enter", "", Net.CHAT_MAX)
    _chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _chat_input.text_submitted.connect(_on_chat_submit)
    ch.add_child(_chat_input)

    # 하단 바
    var bottom := PanelContainer.new()
    root.add_child(bottom)
    var bh := UI.hbox(12)
    bottom.add_child(bh)
    _status = UI.label("", 18, UI.MUTED)
    _status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    bh.add_child(_status)
    _ready_btn = UI.secondary_button("레디")
    _ready_btn.custom_minimum_size.x = 180
    _ready_btn.pressed.connect(_on_ready_pressed)
    bh.add_child(_ready_btn)
    _start_btn = UI.primary_button("게임 시작")
    _start_btn.custom_minimum_size.x = 200
    _start_btn.pressed.connect(func(): Net.start_game())
    bh.add_child(_start_btn)

    # 게임 중 대기 오버레이
    _playing_overlay = ColorRect.new()
    (_playing_overlay as ColorRect).color = Color(0.05, 0.08, 0.15, 0.5)
    _playing_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _playing_overlay.visible = false
    add_child(_playing_overlay)
    var ov := UI.centered_panel(_playing_overlay, 460)
    var ol := UI.label("게임 진행 중\n다른 플레이어가 돌아오기를 기다리는 중…", 22)
    ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    ov.add_child(ol)

    Net.room_updated.connect(_refresh)
    Net.chat_received.connect(_on_chat)
    for e in Net.chat_log:
        _append_chat(e.nick, e.text, e.system)
    _refresh(Net.room)


func _exit_tree() -> void:
    Net.room_updated.disconnect(_refresh)
    Net.chat_received.disconnect(_on_chat)


func _refresh(r: Dictionary) -> void:
    if r.is_empty():
        return
    var host := Net.is_host()
    _title.text = String(r.name)
    for c in _state_badge_holder.get_children():
        c.queue_free()
    var playing: bool = r.state == "playing"
    _state_badge_holder.add_child(UI.badge("게임 중" if playing else "대기 중", UI.DANGER if playing else UI.GOOD))
    _playing_overlay.visible = playing

    # 슬롯
    for c in _grid.get_children():
        c.queue_free()
    var members: Array = r.members
    for i in int(r.max):
        if i < members.size():
            _grid.add_child(_member_card(members[i], i, host))
        else:
            _grid.add_child(_empty_card(bool(r.bot_fill)))

    _build_settings(r, host)

    # 하단 버튼/상태
    var me := _my_entry(r)
    _ready_btn.visible = not host
    _start_btn.visible = host
    if not host:
        var rd: bool = me.get("ready", false)
        _ready_btn.text = "레디 해제" if rd else "레디"
        _ready_btn.disabled = playing
    var reason := Net.start_block_reason(r)
    _start_btn.disabled = reason != ""
    if host:
        _status.text = "모두 준비 완료! 게임을 시작하세요" if reason == "" else reason
    else:
        var ready_count := 0
        for m in members:
            if m.ready or m.host:
                ready_count += 1
        _status.text = "준비 %d / %d  ·  방장이 시작하면 게임이 열립니다" % [ready_count, members.size()]
    _status.add_theme_color_override("font_color", UI.GOOD if (host and reason == "") else UI.MUTED)


func _my_entry(r: Dictionary) -> Dictionary:
    for m in r.members:
        if int(m.id) == Net.my_id:
            return m
    return {}


func _member_card(m: Dictionary, index: int, viewer_is_host: bool) -> Control:
    var is_me := int(m.id) == Net.my_id
    var card := PanelContainer.new()
    var border := UI.PRIMARY if is_me else Color(0, 0, 0, 0)
    card.add_theme_stylebox_override("panel", UI.box(UI.SOFT, 14, 14, border, 3 if is_me else 0))
    card.custom_minimum_size = Vector2(0, 118)
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var v := UI.vbox(6)
    card.add_child(v)

    var top := UI.hbox(8)
    v.add_child(top)
    var dot := ColorRect.new()
    dot.color = SLOT_COLORS[index % SLOT_COLORS.size()]
    dot.custom_minimum_size = Vector2(14, 14)
    dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    top.add_child(dot)
    var name_l := UI.label(String(m.nick) + (" (나)" if is_me else ""), 18)
    name_l.clip_text = true
    name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top.add_child(name_l)

    var badges := UI.hbox(6)
    v.add_child(badges)
    if m.host:
        badges.add_child(UI.badge("방장", UI.PRIMARY))
    elif m.ready:
        badges.add_child(UI.badge("READY", UI.GOOD))
    else:
        badges.add_child(UI.badge("대기", UI.MUTED))

    if viewer_is_host and not is_me:
        var acts := UI.hbox(6)
        v.add_child(acts)
        var kick := _small_button("강퇴")
        var pid := int(m.id)
        kick.pressed.connect(func(): Net.kick(pid))
        acts.add_child(kick)
        var give := _small_button("방장 위임")
        give.pressed.connect(func(): Net.transfer_host(pid))
        acts.add_child(give)
    return card


func _empty_card(bot_fill: bool) -> Control:
    var card := PanelContainer.new()
    card.add_theme_stylebox_override("panel", UI.box(Color(1, 1, 1, 0.35), 14, 14, Color(0.8, 0.83, 0.9), 2))
    card.custom_minimum_size = Vector2(0, 118)
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var l := UI.label("봇" if bot_fill else "빈 자리", 18, UI.MUTED)
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    card.add_child(l)
    return card


func _small_button(text: String) -> Button:
    var b := Button.new()
    b.text = text
    b.add_theme_font_size_override("font_size", 14)
    b.add_theme_stylebox_override("normal", UI.box(Color.WHITE, 8, 8))
    b.add_theme_stylebox_override("hover", UI.box(Color(0.9, 0.92, 0.98), 8, 8))
    return b


# ---------------------------------------------------------------- 설정
func _build_settings(r: Dictionary, host: bool) -> void:
    # 방장이 입력 중일 때 덮어쓰지 않도록, 방장 화면은 값만 갱신하고 위젯은 유지
    if host and _settings_mode == "host":
        _s_max.set_value_no_signal(int(r.max))
        _s_bots.set_pressed_no_signal(bool(r.bot_fill))
        if not _s_name.has_focus():
            _s_name.text = String(r.name)
        return
    _settings_mode = "host" if host else "guest"
    for c in _settings_box.get_children():
        c.queue_free()
    _settings_box.add_child(UI.label("게임 설정", 20))
    if host:
        _settings_box.add_child(UI.label("방 이름", 15, UI.MUTED))
        _s_name = UI.line_edit("방 이름", String(r.name), Net.ROOM_NAME_MAX)
        _s_name.text_submitted.connect(func(t): Net.update_settings({"name": t}))
        _s_name.focus_exited.connect(func(): Net.update_settings({"name": _s_name.text}))
        _settings_box.add_child(_s_name)
        _settings_box.add_child(UI.label("최대 인원 (2~%d명)" % Net.MAX_PLAYERS_LIMIT, 15, UI.MUTED))
        _s_max = SpinBox.new()
        _s_max.min_value = 2
        _s_max.max_value = Net.MAX_PLAYERS_LIMIT
        _s_max.value = int(r.max)
        _s_max.custom_minimum_size.y = 44
        _s_max.value_changed.connect(func(v): Net.update_settings({"max": int(v)}))
        _settings_box.add_child(_s_max)
        _s_bots = CheckBox.new()
        _s_bots.text = "빈 자리를 봇으로 채우기"
        _s_bots.button_pressed = bool(r.bot_fill)
        _s_bots.toggled.connect(func(on): Net.update_settings({"bot_fill": on}))
        _settings_box.add_child(_s_bots)
    else:
        _settings_box.add_child(UI.label("최대 인원: %d명" % int(r.max), 18))
        _settings_box.add_child(UI.label("빈 자리 봇 채우기: %s" % ("켜짐" if r.bot_fill else "꺼짐"), 18))
        _settings_box.add_child(UI.label("설정은 방장만 바꿀 수 있습니다", 14, UI.MUTED))


# ---------------------------------------------------------------- 레디 / 채팅
func _on_ready_pressed() -> void:
    var me := _my_entry(Net.room)
    Net.set_ready(not me.get("ready", false))


func _on_chat_submit(text: String) -> void:
    if text.strip_edges() != "":
        Net.send_chat(text)
    _chat_input.clear()


func _on_chat(nick: String, text: String, system: bool) -> void:
    _append_chat(nick, text, system)


func _append_chat(nick: String, text: String, system: bool) -> void:
    var safe := text.replace("[", "[lb]")
    if system:
        _chat_log.append_text("[color=#8a90a6]· %s[/color]\n" % safe)
    else:
        var col := "#f0844e" if nick == Net.nickname else "#3b62c9"
        _chat_log.append_text("[b][color=%s]%s[/color][/b]  %s\n" % [col, nick.replace("[", "[lb]"), safe])
