extends Control
const LoadingOverlay := preload("res://scripts/ui/loading_overlay.gd")
## 3단계: 대기룸 — 참가자 슬롯(캐릭터 초상화, 최대 12), 레디, 방장 설정/강퇴/위임, 채팅, 게임 시작
## 슬롯 색 = 게임 안 캐릭터 색 (Fighter.SLOT_COLORS, 초상화 ui/portraits/slot_N.png)

const UI := preload("res://scripts/ui/ui_kit.gd")
const GameRegistry := preload("res://scripts/core/game_registry.gd")
const Series := preload("res://scripts/core/series.gd")
const Teams := preload("res://scripts/core/teams.gd")

var app: Node
var _title: Label
var _state_badge_holder: HBoxContainer
var _slots_label: Label
var _slots: VBoxContainer           ## 참가자 목록 (팀전 = 팀별 열, 개인전 = 2~3열 목록)
var _last_slots_key := ""
var _game_img_holder: Control
var _game_name: Label
var _game_desc: Label
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
var _mode_bar: HBoxContainer          # 상단 '경기 방식' 바 (팀 · 라운드)
var _mode_key := ""
var _s_round_box: GridContainer
var _s_round_opts: Array[OptionButton] = []
var _overlay_text: Label
var _settings_mode := ""
var _shown_game := ""


var _last_members := -1
var _last_ready := false


func _ready() -> void:
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for side in ["left", "right"]:
        margin.add_theme_constant_override("margin_" + side, 28)
    margin.add_theme_constant_override("margin_top", 18)
    margin.add_theme_constant_override("margin_bottom", 26)       # 아래 버튼 그림자까지 여유
    add_child(margin)
    var root := UI.vbox(12)
    margin.add_child(root)

    # 상단 바: 방 이름 · 게임/상태 배지 · 나가기
    var top := UI.hbox(12)
    root.add_child(top)
    _title = UI.title("", 38)
    _title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _title.clip_text = true
    _title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    _title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _title.size_flags_stretch_ratio = 3.0
    top.add_child(_title)
    # 방장: 방 이름을 위 제목 자리에서 바로 고침 (오른쪽 설정 칸 높이를 줄이려고 여기로)
    _s_name = UI.line_edit("방 이름", "", Net.ROOM_NAME_MAX)
    _s_name.custom_minimum_size = Vector2(0, 50)
    _s_name.add_theme_font_size_override("font_size", 24)
    _s_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _s_name.size_flags_stretch_ratio = 3.0
    _s_name.tooltip_text = "방 이름 (방장만 바꿀 수 있어요)"
    _s_name.text_submitted.connect(func(t): Net.update_settings({"name": t}))
    _s_name.focus_exited.connect(func(): Net.update_settings({"name": _s_name.text}))
    _s_name.visible = false
    top.add_child(_s_name)
    _state_badge_holder = UI.hbox(8)
    top.add_child(_state_badge_holder)
    var snd := UI.sound_button()
    snd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    top.add_child(snd)
    var leave := UI.pill_button("방 나가기")
    leave.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    leave.pressed.connect(func(): Net.leave_room())
    top.add_child(leave)

    # 경기 방식: 팀 · 라운드 — 한눈에 보이게 크게 (방장만 바꿀 수 있음)
    var mode_panel := PanelContainer.new()
    var mode_sb := UI.box(Color(1, 0.99, 0.95), 18, 18, UI.INK, 3, 4)
    mode_sb.content_margin_top = 12
    mode_sb.content_margin_bottom = 12
    mode_panel.add_theme_stylebox_override("panel", mode_sb)
    root.add_child(mode_panel)
    _mode_bar = UI.hbox(22)
    _mode_bar.alignment = BoxContainer.ALIGNMENT_CENTER
    mode_panel.add_child(_mode_bar)

    # 본문: 왼쪽 슬롯 / 오른쪽 게임 카드 + 채팅
    var body := UI.hbox(20)
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(body)

    var left := PanelContainer.new()
    left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.add_child(left)
    var lv := UI.vbox(14)
    left.add_child(lv)
    _slots_label = UI.heading("참가자", 26)
    lv.add_child(_slots_label)
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    lv.add_child(scroll)
    var pad := MarginContainer.new()
    pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    pad.add_theme_constant_override("margin_bottom", 8)
    pad.add_theme_constant_override("margin_right", 6)
    scroll.add_child(pad)
    _slots = UI.vbox(14)
    _slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    pad.add_child(_slots)

    # 오른쪽 줄: 화면이 낮으면 스크롤 (아래 '게임 시작' 줄이 화면 밖으로 밀리지 않게)
    var right_scroll := ScrollContainer.new()
    right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    right_scroll.custom_minimum_size.x = 392
    right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body.add_child(right_scroll)
    var right_pad := MarginContainer.new()
    right_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right_pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
    right_pad.add_theme_constant_override("margin_right", 10)       # 그림자·스크롤바 자리
    right_pad.add_theme_constant_override("margin_bottom", 6)
    right_scroll.add_child(right_pad)
    var right := UI.vbox(16)
    right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right.size_flags_vertical = Control.SIZE_EXPAND_FILL
    right_pad.add_child(right)

    # 게임 카드 (썸네일 + 이름 + 설명 + 설정)
    var game_panel := PanelContainer.new()
    right.add_child(game_panel)
    var gv := UI.vbox(10)
    game_panel.add_child(gv)
    var gh := UI.hbox(16)
    gv.add_child(gh)
    _game_img_holder = UI.vbox(0)
    gh.add_child(_game_img_holder)
    var gt := UI.vbox(6)
    gt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    gt.alignment = BoxContainer.ALIGNMENT_CENTER
    gh.add_child(gt)
    _game_name = UI.heading("", 22)
    _game_name.clip_text = true
    _game_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    gt.add_child(_game_name)
    # 게임 설명: 높이 고정 + 넘치면 스크롤 (게임이 바뀌어도 화면 배치가 흔들리지 않게)
    var desc_scroll := ScrollContainer.new()
    desc_scroll.custom_minimum_size = Vector2(0, 52)
    desc_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    gt.add_child(desc_scroll)
    _game_desc = UI.label("", 13, UI.MUTED)
    _game_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _game_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    desc_scroll.add_child(_game_desc)
    _settings_box = UI.vbox(8)
    gv.add_child(_settings_box)

    var chat_panel := PanelContainer.new()
    chat_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    right.add_child(chat_panel)
    var cv := UI.vbox(8)
    chat_panel.add_child(cv)
    cv.add_child(UI.heading("채팅", 20))
    _chat_log = RichTextLabel.new()
    _chat_log.bbcode_enabled = true
    _chat_log.scroll_following = true
    _chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _chat_log.custom_minimum_size.y = 40
    _chat_log.add_theme_font_size_override("normal_font_size", 16)
    _chat_log.add_theme_font_size_override("bold_font_size", 16)
    cv.add_child(_chat_log)
    _chat_input = UI.line_edit("메시지 입력 후 Enter", "", Net.CHAT_MAX)
    _chat_input.custom_minimum_size.y = 46
    _chat_input.add_theme_font_size_override("font_size", 17)
    _chat_input.text_submitted.connect(_on_chat_submit)
    cv.add_child(_chat_input)

    # 하단 바: 상태 문구 + 큰 버튼
    var bottom := UI.hbox(18)
    root.add_child(bottom)
    _status = UI.heading("", 19, UI.CREAM)
    _status.add_theme_stylebox_override("normal", UI.box(UI.INK, 22, 18))
    _status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    bottom.add_child(_status)
    bottom.add_child(UI.spacer())
    _ready_btn = UI.good_button("레디!")
    _ready_btn.custom_minimum_size = Vector2(230, 62)
    _ready_btn.add_theme_font_size_override("font_size", 28)
    _ready_btn.pressed.connect(_on_ready_pressed)
    bottom.add_child(_ready_btn)
    _start_btn = UI.cta_button("게임 시작!")
    _start_btn.custom_minimum_size = Vector2(250, 62)
    _start_btn.add_theme_font_size_override("font_size", 28)
    _start_btn.pressed.connect(func():
        LoadingOverlay.open(get_tree(), "게임 시작 준비 중…")
        Net.start_game())
    bottom.add_child(_start_btn)

    # 게임 중 대기 오버레이
    _playing_overlay = ColorRect.new()
    (_playing_overlay as ColorRect).color = Color(UI.INK, 0.55)
    _playing_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _playing_overlay.visible = false
    add_child(_playing_overlay)
    var ov := UI.centered_panel(_playing_overlay, 480)
    var oh := UI.heading("게임 진행 중", 30)
    oh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    ov.add_child(oh)
    _overlay_text = UI.label("다른 플레이어가 돌아오기를 기다리는 중…", 18, UI.MUTED)
    _overlay_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    ov.add_child(_overlay_text)

    Net.room_updated.connect(_refresh)
    Net.chat_received.connect(_on_chat)
    for e in Net.chat_log:
        _append_chat(e.nick, e.text, e.system)
    resized.connect(_update_columns)
    _update_columns()
    _refresh(Net.room)


func _exit_tree() -> void:
    Net.room_updated.disconnect(_refresh)
    Net.chat_received.disconnect(_on_chat)


func _update_columns() -> void:
    _last_slots_key = ""
    if not Net.room.is_empty():
        _refresh(Net.room)


func _refresh(r: Dictionary) -> void:
    if r.is_empty():
        return
    # 소리: 누가 들어오거나 나감, 내 준비 상태 변화
    var member_count: int = (r.get("members", []) as Array).size()
    var my_ready: bool = _my_entry(r).get("ready", false)
    if _last_members >= 0:
        if member_count > _last_members:
            Sfx.play("join")
        elif member_count < _last_members:
            Sfx.play("leave")
        if my_ready != _last_ready:
            Sfx.play("ready_on" if my_ready else "ready_off")
    _last_members = member_count
    _last_ready = my_ready
    var host := Net.is_host()
    var first_choice := String(r.get("game", ""))
    var module = GameRegistry.get_or_default(first_choice)
    var rounds: int = int(r.get("rounds", 1))
    _title.text = String(r.name)
    for c in _state_badge_holder.get_children():
        c.queue_free()
    var playing: bool = r.state == "playing"
    var teams := int(r.get("teams", 0))
    _update_mode_bar(teams, rounds, host and not playing)
    _state_badge_holder.add_child(UI.badge("게임 중" if playing else "대기 중", UI.DANGER if playing else UI.GOOD))
    _playing_overlay.visible = playing
    var ser: Dictionary = r.get("series", {})
    if playing and not ser.is_empty():
        _overlay_text.text = "라운드 %d/%d 진행 중 · 끝나면 이 방으로 돌아와요" % [int(ser.round), int(ser.total)]
    else:
        _overlay_text.text = "다른 플레이어가 돌아오기를 기다리는 중…"

    # 게임 카드
    var card_id: String = first_choice if first_choice == Series.RANDOM else String(module.id)
    if _shown_game != card_id:
        _shown_game = card_id
        for c in _game_img_holder.get_children():
            c.queue_free()
        if card_id == Series.RANDOM:
            _game_img_holder.add_child(UI.image_card(null, Vector2(150, 86), UI.YELLOW))
        else:
            _game_img_holder.add_child(UI.image_card(module.thumbnail(), Vector2(150, 86), module.accent))
    var rg: Array = r.get("round_games", [first_choice])
    var names := PackedStringArray()
    for g in rg:
        names.append(Series.choice_name(String(g)))
    _game_name.text = Series.choice_name(first_choice) if rounds == 1 else "%d라운드 경기" % rounds
    if rounds > 1:
        _game_desc.text = "%s\n라운드마다 1등 3점 · 2등 2점 · 3등 1점, 합계 1위가 우승" % " → ".join(names)
    else:
        _game_desc.text = module.description if first_choice != Series.RANDOM else "게임을 무작위로 골라요"

    # 참가자
    var members: Array = r.members
    _slots_label.text = "참가자  %d / %d" % [members.size(), int(r.max)]
    _build_slots(r, host, teams)

    _build_settings(r, host, module)

    # 하단 버튼/상태
    var me := _my_entry(r)
    _ready_btn.visible = not host
    _start_btn.visible = host
    if not host:
        var rd: bool = me.get("ready", false)
        _ready_btn.text = "레디 취소" if rd else "레디!"
        var sb := UI.toon_box(UI.MUTED if rd else UI.GOOD)
        _ready_btn.add_theme_stylebox_override("normal", sb)
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
        _status.text = "준비 %d / %d  ·  방장이 시작하면 게임이 열려요" % [ready_count, members.size()]
    _status.add_theme_color_override("font_color", UI.YELLOW if (host and reason == "") else UI.CREAM)


func _my_entry(r: Dictionary) -> Dictionary:
    for m in r.members:
        if int(m.id) == Net.my_id:
            return m
    return {}


func _portrait_rect(index: int, alpha: float = 1.0) -> TextureRect:
    var t := TextureRect.new()
    t.texture = UI.portrait(index)
    t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    t.custom_minimum_size = Vector2(56, 56)
    t.modulate.a = alpha
    t.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return t


## 참가자 목록 다시 그리기
##   팀전: 팀마다 한 열 (팀 색 머리글 · 인원 · '이 팀으로' 버튼 → 사람 줄 → 빈 자리)
##   개인전: 사람 줄을 2~3열로
##   사람 줄 = 초상화 · 이름(+나·방장·차단) · 상태(READY/대기) · 오른쪽 '•••' 메뉴(팀 옮기기·강퇴·방장 위임·신고·차단)
func _build_slots(r: Dictionary, host: bool, teams: int) -> void:
    var members: Array = r.members
    var key := "%s|%s|%d|%d|%s|%d|%s|%s" % [str(members), host, teams, int(r.max), r.get("bot_fill", false), Net.my_id, str(Net.blocked.keys()), r.get("state", "")]
    if key == _last_slots_key:
        return
    _last_slots_key = key
    for c in _slots.get_children():
        c.queue_free()
    var bot_fill := bool(r.get("bot_fill", false))
    var waiting := String(r.get("state", "")) == "waiting"
    if teams >= 2:
        var per := int(ceil(float(int(r.max)) / teams))
        # 팀 열: 들어가는 만큼 옆으로 (좁으면 2열로 접어 아래로)
        var compact := teams >= 3 or _slots_width() < 640.0      # 3·4팀: 작은 줄로 모든 팀을 한 줄에
        var row := GridContainer.new()
        row.columns = teams if _slots_width() / teams >= (170.0 if compact else 300.0) else maxi(teams / 2, 1)
        row.add_theme_constant_override("h_separation", 12 if compact else 16)
        row.add_theme_constant_override("v_separation", 16)
        row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _slots.add_child(row)
        var my_team := int(_my_entry(r).get("team", -1))
        for t in teams:
            var list: Array = []
            for i in members.size():
                if int(members[i].get("team", 0)) == t:
                    list.append(i)
            row.add_child(_team_column(t, list, members, per, host, teams, my_team, waiting, bot_fill, compact))
    else:
        var grid := GridContainer.new()
        var small := int(r.max) > 8                # 사람이 많으면 작은 줄로 3~4열 (스크롤 없이 한눈에)
        grid.columns = clampi(int(_slots_width() / (180.0 if small else 280.0)), 1, 4 if small else 3)
        grid.add_theme_constant_override("h_separation", 14)
        grid.add_theme_constant_override("v_separation", 12)
        grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _slots.add_child(grid)
        for i in int(r.max):
            if i < members.size():
                grid.add_child(_member_row(members[i], i, host, 0, -1, waiting, small))
            else:
                grid.add_child(_empty_row(i, bot_fill, Color(UI.INK, 0.3), small))


## 참가자 칸 너비 (화면 너비 - 오른쪽 칸 - 여백)
func _slots_width() -> float:
    return maxf(size.x - 56.0 - 20.0 - 392.0 - 64.0, 280.0)


func _team_column(t: int, list: Array, members: Array, per: int, host: bool, teams: int, my_team: int,
        waiting: bool, bot_fill: bool, compact: bool = false) -> Control:
    var tc := Teams.color(t)
    var col := PanelContainer.new()
    col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var sb := UI.box(tc.lerp(Color.WHITE, 0.86), 16, 8 if compact else 14, tc, 3, 0)
    sb.content_margin_top = 10 if compact else 12
    sb.content_margin_bottom = 12 if compact else 14
    col.add_theme_stylebox_override("panel", sb)
    var v := UI.vbox(8 if compact else 10)
    col.add_child(v)
    # 머리글: 팀 색 띠
    var head_p := PanelContainer.new()
    var hsb := UI.box(tc, 10, 12)
    hsb.content_margin_top = 6
    hsb.content_margin_bottom = 6
    head_p.add_theme_stylebox_override("panel", hsb)
    v.add_child(head_p)
    var head := UI.hbox(10)
    head_p.add_child(head)
    var fg := UI.INK if t == 3 else Color.WHITE
    var name_l := UI.heading(Teams.team_name(t), 17 if compact else 20, fg)
    name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(name_l)
    var cnt := UI.label("%d / %d" % [list.size(), per], 15, fg)
    cnt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    head.add_child(cnt)
    # 나: 다른 팀으로 옮기기 (그 팀 머리 아래 버튼)
    if waiting and my_team >= 0 and my_team != t and list.size() < per:
        var join := UI.pill_button("이 팀으로" if compact else "이 팀으로 옮기기", Color.WHITE, tc.darkened(0.25))
        join.focus_mode = Control.FOCUS_NONE
        join.pressed.connect(func(): Net.set_team(Net.my_id, t))
        v.add_child(join)
    for i in list:
        v.add_child(_member_row(members[i], i, host, teams, t, waiting, compact))
    for k in maxi(per - list.size(), 0):
        v.add_child(_empty_row(-1, bot_fill, Color(tc, 0.45), compact))
    return col


func _member_row(m: Dictionary, index: int, host: bool, teams: int, team: int, waiting: bool, compact: bool = false) -> Control:
    var is_me := int(m.id) == Net.my_id
    var row := PanelContainer.new()
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var border := UI.CTA if is_me else Color(UI.INK, 0.18)
    var sb := UI.box(Color.WHITE, 12, 8 if compact else 12, border, 3 if is_me else 2, 0)
    sb.content_margin_top = 6
    sb.content_margin_bottom = 6
    row.add_theme_stylebox_override("panel", sb)
    var h := UI.hbox(6 if compact else 12)
    row.add_child(h)
    # 초상화 (캐릭터 색 동그라미 위)
    var face := PanelContainer.new()
    var col: Color = Teams.color(team) if team >= 0 else Fighter.SLOT_COLORS[index % Fighter.SLOT_COLORS.size()]
    face.add_theme_stylebox_override("panel", UI.box(col.lerp(Color.WHITE, 0.7), 28, 0))
    var pr := _portrait_rect(index)
    if compact:
        pr.custom_minimum_size = Vector2(34, 36)
    face.add_child(pr)
    face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    h.add_child(face)
    # 이름 + 작은 표시
    var mid := UI.vbox(2)
    mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    mid.alignment = BoxContainer.ALIGNMENT_CENTER
    h.add_child(mid)
    var name_l := UI.heading(String(m.nick), 16 if compact else 19)
    name_l.custom_minimum_size.x = 44 if compact else 72
    name_l.clip_text = true
    name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    mid.add_child(name_l)
    var tags := PackedStringArray()
    if is_me:
        tags.append("나")
    var uid := String(m.get("uid", ""))
    var blocked := uid != "" and Net.blocked.has(uid)
    if blocked:
        tags.append("차단함")
    # 상태: 넓으면 오른쪽 배지, 좁으면 이름 아래 색 글자
    var st_text := "방장" if m.host else ("READY" if m.ready else "대기")
    var st_col: Color = UI.YELLOW if m.host else (UI.GOOD if m.ready else UI.MUTED)
    if compact:
        tags.insert(0, st_text)
    if not tags.is_empty():
        var tl := UI.label(" · ".join(tags), 12 if compact else 13, UI.DANGER if blocked else (st_col.darkened(0.25) if compact else UI.MUTED))
        tl.clip_text = true
        mid.add_child(tl)
    if not compact:
        var st: Control = UI.badge(st_text, st_col, UI.INK if m.host else Color.WHITE)
        h.add_child(st)
    # 더보기 메뉴 (할 수 있는 것이 있을 때만)
    var acts: Array = []                     # [글자, Callable]
    var pid := int(m.id)
    if host and not is_me and waiting and teams >= 2:
        for t in teams:
            if t != team:
                var tv: int = t
                acts.append(["%s으로 옮기기" % Teams.team_name(t), func(): Net.set_team(pid, tv)])
    if host and not is_me:
        acts.append(["방장 넘기기", func(): Net.transfer_host(pid)])
        acts.append(["내보내기 (강퇴)", func(): Net.kick(pid)])
    if not is_me:
        var nick_s := String(m.nick)
        acts.append(["신고하기", func(): _open_report(pid, nick_s)])
        if uid != "":
            acts.append(["차단 해제" if blocked else "채팅 차단", func():
                Net.set_blocked(uid, nick_s, not blocked)
                _append_chat("", "%s 님을 %s" % [nick_s, "차단 해제했어요" if blocked else "차단했어요. 이 사람의 채팅이 보이지 않아요"], true)
                _last_slots_key = ""
                _refresh(Net.room)])
    if not acts.is_empty():
        var mb := _more_menu(acts)
        if compact:
            mb.custom_minimum_size = Vector2(28, 28)
            for st in ["normal", "hover", "pressed", "focus"]:
                (mb.get_theme_stylebox(st) as StyleBoxFlat).content_margin_left = 4
                (mb.get_theme_stylebox(st) as StyleBoxFlat).content_margin_right = 4
        h.add_child(mb)
    elif not compact:
        var gap := Control.new()
        gap.custom_minimum_size.x = 40
        h.add_child(gap)
    return row


## '•••' 더보기 단추 → 펼침 메뉴
func _more_menu(acts: Array) -> MenuButton:
    var mb := MenuButton.new()
    mb.text = "•••"
    mb.flat = false
    mb.focus_mode = Control.FOCUS_NONE
    mb.tooltip_text = "더보기"
    mb.custom_minimum_size = Vector2(40, 34)
    mb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    mb.add_theme_font_size_override("font_size", 14)
    for st in ["normal", "hover", "pressed", "focus"]:
        var sb := UI.box(Color(UI.INK, 0.06) if st == "normal" else Color(UI.INK, 0.14), 10, 8)
        mb.add_theme_stylebox_override(st, sb)
    for st in ["font_color", "font_hover_color", "font_pressed_color"]:
        mb.add_theme_color_override(st, UI.INK)
    var pop := mb.get_popup()
    pop.add_theme_font_size_override("font_size", 16)
    for i in acts.size():
        pop.add_item(String(acts[i][0]), i)
    pop.id_pressed.connect(func(id: int): (acts[id][1] as Callable).call())
    return mb


func _empty_row(index: int, bot_fill: bool, border: Color, compact: bool = false) -> Control:
    var row := PanelContainer.new()
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var sb := UI.box(Color(1, 1, 1, 0.45), 12, 12, border, 2, 0)
    sb.content_margin_top = 6
    sb.content_margin_bottom = 6
    row.add_theme_stylebox_override("panel", sb)
    var h := UI.hbox(12)
    row.add_child(h)
    var ph := Control.new()
    ph.custom_minimum_size = Vector2(34, 36) if compact else Vector2(56, 56)
    if bot_fill and index >= 0:
        var pr := _portrait_rect(index, 0.55)
        pr.custom_minimum_size = ph.custom_minimum_size
        pr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        ph.add_child(pr)
    h.add_child(ph)
    var l := UI.label(("봇" if compact else "봇이 채워요") if bot_fill else "빈 자리", 14 if compact else 16, UI.MUTED)
    l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    h.add_child(l)
    return row


# ---------------------------------------------------------------- 신고
var _report_dlg: Control
var _report_reason: OptionButton
var _report_detail: LineEdit
var _report_title: Label
var _report_target := 0


func _open_report(pid: int, nick: String) -> void:
    if _report_dlg == null:
        _report_dlg = ColorRect.new()
        (_report_dlg as ColorRect).color = Color(UI.INK, 0.55)
        _report_dlg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        add_child(_report_dlg)
        var v := UI.centered_panel(_report_dlg, 460)
        _report_title = UI.heading("", 26)
        v.add_child(_report_title)
        var note := UI.label("운영자가 신고 내용과 이 방의 최근 채팅을 확인해요. 거짓 신고는 제재될 수 있어요.", 15, UI.MUTED)
        note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        v.add_child(note)
        _report_reason = OptionButton.new()
        _report_reason.add_theme_font_size_override("font_size", 18)
        for k in Net.REPORT_REASONS:
            _report_reason.add_item(Net.REPORT_REASONS[k])
            _report_reason.set_item_metadata(_report_reason.item_count - 1, k)
        v.add_child(_report_reason)
        _report_detail = UI.line_edit("자세한 내용 (선택)", "", 200)
        v.add_child(_report_detail)
        var row := UI.hbox(10)
        v.add_child(row)
        var cancel := UI.secondary_button("취소")
        cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        cancel.pressed.connect(func(): _report_dlg.visible = false)
        row.add_child(cancel)
        var send := UI.cta_button("신고하기")
        send.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        send.pressed.connect(func():
            Net.report(_report_target, String(_report_reason.get_item_metadata(_report_reason.selected)), _report_detail.text)
            _report_dlg.visible = false)
        row.add_child(send)
    _report_target = pid
    _report_title.text = "%s 님 신고" % nick
    _report_reason.select(0)
    _report_detail.clear()
    _report_dlg.visible = true


# ---------------------------------------------------------------- 설정
func _build_settings(r: Dictionary, host: bool, module) -> void:
    # 방장이 입력 중일 때 덮어쓰지 않도록, 방장 화면은 값만 갱신하고 위젯은 유지
    var rg: Array = r.get("round_games", [String(r.get("game", ""))])
    if host and _settings_mode == "host":
        _sync_round_widgets(rg)
        _set_max_step(int(r.get("teams", 0)))
        _s_max.max_value = mini(Net.MAX_PLAYERS_LIMIT, Series.max_players_for(rg))
        _s_max.set_value_no_signal(int(r.max))
        _s_bots.set_pressed_no_signal(bool(r.bot_fill))
        if not _s_name.has_focus():
            _s_name.text = String(r.name)
        return
    _settings_mode = "host" if host else "guest"
    for c in _settings_box.get_children():
        c.queue_free()
    _s_name.visible = host
    _title.visible = not host
    if host:
        _s_name.text = String(r.name)

        # 2줄: 최대 인원 · 봇 채우기 (팀·라운드는 위쪽 '경기 방식' 바에서)
        var mrow := UI.hbox(14)
        _settings_box.add_child(mrow)
        mrow.add_child(_field_label("인원"))
        _s_max = SpinBox.new()
        _s_max.min_value = 2
        _s_max.max_value = mini(Net.MAX_PLAYERS_LIMIT, Series.max_players_for(rg))
        _set_max_step(int(r.get("teams", 0)))
        _s_max.value = int(r.max)
        _s_max.suffix = "명"
        _s_max.custom_minimum_size = Vector2(104, 40)
        _s_max.value_changed.connect(func(v): Net.update_settings({"max": int(v)}))
        mrow.add_child(_s_max)
        _s_bots = CheckBox.new()
        _s_bots.text = "봇 채우기"
        _s_bots.add_theme_font_size_override("font_size", 16)
        _s_bots.button_pressed = bool(r.bot_fill)
        _s_bots.toggled.connect(func(on): Net.update_settings({"bot_fill": on}))
        mrow.add_child(_s_bots)

        # 라운드별 게임 (같은 게임 여러 번 / 랜덤) — 두 칸씩
        var grid := GridContainer.new()
        grid.columns = 2
        grid.add_theme_constant_override("h_separation", 14)
        grid.add_theme_constant_override("v_separation", 8)
        _settings_box.add_child(grid)
        _s_round_box = grid
        _s_round_opts.clear()
        _sync_round_widgets(rg)
    else:
        var list := PackedStringArray()
        for i in rg.size():
            list.append("%d. %s" % [i + 1, Series.choice_name(String(rg[i]))])
        var rl := UI.label("\n".join(list), 15, UI.INK)
        _settings_box.add_child(rl)
        var chips := UI.hbox(10)
        _settings_box.add_child(chips)
        chips.add_child(UI.badge("최대 %d명" % int(r.max), UI.SECONDARY))
        chips.add_child(UI.badge("봇 채우기 %s" % ("ON" if r.bot_fill else "OFF"), UI.GOOD if r.bot_fill else UI.MUTED))
        _settings_box.add_child(UI.label("설정은 방장만 바꿀 수 있어요", 13, UI.MUTED))


## 상단 '경기 방식' 바: [팀] 개인전 2팀 3팀 4팀  |  [라운드] 1 2 3 4 5
## 팀전이면 인원은 팀 수 단위로만 (2팀 2·4·6…, 3팀 3·6·9…)
func _set_max_step(teams: int) -> void:
    _s_max.min_value = teams if teams >= 2 else 2
    _s_max.step = teams if teams >= 2 else 1
    _s_max.tooltip_text = "%d팀전: 인원은 %d명 단위" % [teams, teams] if teams >= 2 else ""


func _update_mode_bar(teams: int, rounds: int, editable: bool) -> void:
    var key := "%d/%d/%s" % [teams, rounds, editable]
    if key == _mode_key:
        return
    _mode_key = key
    for c in _mode_bar.get_children():
        c.queue_free()

    _mode_bar.add_child(_mode_title("팀"))
    var tg := UI.hbox(10)
    _mode_bar.add_child(tg)
    for t in Teams.MODES:
        var label := "개인전" if t == 0 else "%d팀" % t
        var b := _seg_button(label, t == teams, UI.PRIMARY, editable, 92)
        # 팀 색 점: 몇 팀으로 나뉘는지 바로 보이게
        if t >= 2:
            var dots := UI.hbox(3)
            dots.alignment = BoxContainer.ALIGNMENT_CENTER
            dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
            for i in t:
                var d := ColorRect.new()
                d.color = Teams.color(i)
                d.custom_minimum_size = Vector2(12, 5)
                d.mouse_filter = Control.MOUSE_FILTER_IGNORE
                dots.add_child(d)
            # 흰 받침 위에 (고른 버튼이 팀 색이어도 점이 보이게), 테두리 안쪽에
            var holder := PanelContainer.new()
            holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
            holder.add_theme_stylebox_override("panel", UI.box(Color(1, 1, 1, 0.95), 4, 3))
            holder.add_child(dots)
            holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 8)
            b.add_child(holder)
        var tv: int = t
        b.pressed.connect(func(): Net.update_settings({"teams": tv}))
        tg.add_child(b)

    var sep := VSeparator.new()
    sep.custom_minimum_size.x = 12
    _mode_bar.add_child(sep)

    _mode_bar.add_child(_mode_title("라운드"))
    var rgp := UI.hbox(10)
    _mode_bar.add_child(rgp)
    for n in range(Series.MIN_ROUNDS, Series.MAX_ROUNDS + 1):
        var b := _seg_button(str(n), n == rounds, UI.YELLOW, editable, 54)
        var nv: int = n
        b.pressed.connect(func(): Net.update_settings({"rounds": nv}))
        rgp.add_child(b)
    # 설명 글은 한 칸에 (방장이 아니면 '방장이 정해요'까지 세 줄) — 바가 옆으로 넘치지 않게
    var cap := UI.label("1등 3점 · 2등 2점 · 3등 1점\n합계 1위가 우승" + ("" if editable else "\n방장이 정해요"), 13, UI.MUTED)
    _mode_bar.add_child(cap)


func _mode_title(text: String) -> Label:
    var l := UI.heading(text, 24)
    l.custom_minimum_size.x = 0
    return l


## 고르는 버튼: 고른 것은 진하게, 나머지는 옅게. 방장이 아니면 누를 수 없음
func _seg_button(text: String, selected: bool, color: Color, editable: bool, width: float) -> Button:
    var b := Button.new()
    b.text = text
    b.custom_minimum_size = Vector2(width, 56)
    b.focus_mode = Control.FOCUS_NONE
    b.add_theme_font_size_override("font_size", 22 if selected else 19)
    var fg := (UI.INK if color == UI.YELLOW else Color.WHITE) if selected else UI.INK
    for st in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
        b.add_theme_color_override(st, fg if (selected or st != "font_disabled_color") else Color(UI.INK, 0.45))
    var base := color if selected else Color(1, 1, 1)
    for st in ["normal", "hover", "pressed", "disabled", "focus"]:
        var sb := UI.box(base.lightened(0.08) if st == "hover" and editable else base, 14, 10,
                UI.INK if selected else Color(UI.INK, 0.25), 3 if selected else 2, 4 if selected else 0)
        sb.content_margin_top = 6
        sb.content_margin_bottom = 14          # 아래 팀 색 점 자리
        b.add_theme_stylebox_override(st, sb)
    b.disabled = not editable and not selected
    if selected:
        b.mouse_filter = Control.MOUSE_FILTER_IGNORE      # 이미 고른 것
    return b


## 방장 화면: 라운드 수에 맞춰 라운드별 게임 선택 상자를 만들고 값 맞추기
func _sync_round_widgets(rg: Array) -> void:
    while _s_round_opts.size() > rg.size():
        var o: OptionButton = _s_round_opts.pop_back()
        o.get_parent().queue_free()
    while _s_round_opts.size() < rg.size():
        var i := _s_round_opts.size()
        var row := UI.hbox(10)
        row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _s_round_box.add_child(row)
        var l := UI.label("%dR" % (i + 1), 15, UI.MUTED)
        l.custom_minimum_size.x = 26
        l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        row.add_child(l)
        var o := OptionButton.new()
        o.custom_minimum_size.y = 36
        o.clip_text = true
        o.add_theme_font_size_override("font_size", 15)
        o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        for m in GameRegistry.all():
            o.add_item(m.display_name)
        o.add_item("랜덤")
        o.item_selected.connect(func(idx): Net.update_settings({"round_game": [i, _choice_at(idx)]}))
        row.add_child(o)
        _s_round_opts.append(o)
    for i in rg.size():
        var idx := _choice_index(String(rg[i]))
        if _s_round_opts[i].selected != idx:
            _s_round_opts[i].select(idx)


func _choice_at(idx: int) -> String:
    var mods: Array = GameRegistry.all()
    return mods[idx].id if idx < mods.size() else Series.RANDOM


func _choice_index(id: String) -> int:
    return GameRegistry.all().size() if id == Series.RANDOM else _module_index(id)


func _field_label(text: String) -> Label:
    var l := UI.heading(text, 16, UI.MUTED)
    l.custom_minimum_size.x = 72
    l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    return l


func _module_index(id: String) -> int:
    var mods: Array = GameRegistry.all()
    for i in mods.size():
        if mods[i].id == id:
            return i
    return 0


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
    if not system and nick != Net.nickname:
        Sfx.play("chat")


func _append_chat(nick: String, text: String, system: bool) -> void:
    if not system and Net.is_blocked_nick(nick):
        return              # 차단한 사람의 채팅은 숨김
    var safe := text.replace("[", "[lb]")
    if system:
        _chat_log.append_text("[color=#8a90a6]· %s[/color]\n" % safe)
    else:
        var col := "#e8603f" if nick == Net.nickname else "#2f6fd6"
        _chat_log.append_text("[b][color=%s]%s[/color][/b]  %s\n" % [col, nick.replace("[", "[lb]"), safe])
