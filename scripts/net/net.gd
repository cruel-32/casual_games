extends Node
## 온라인 로비/방 네트워크 (오토로드: /root/Net)
## - 같은 스크립트가 서버와 클라이언트 양쪽에서 실행된다 (WebSocket + RPC, 서버 권위)
## - 서버는 평문 ws:// 로 열고, 외부에서는 리버스 프록시(Caddy)가 wss:// (HTTPS 443) 를 받아 전달한다
## - 실행 인자 `-- --server [--port 7777] [--status-port 7778]` 이면 전용 서버로 시작
## - 상태 페이지(HTTP): status-port 의 `/` (HTML), `/health` (헬스체크, "ok")
## - 클라이언트 → 서버: c_* RPC / 서버 → 클라이언트: s_* RPC
## - 게임 중: 서버가 방마다 경기(match.tscn)를 따로 돌린다 (SubViewport + 독립 물리 월드).
##   게임 모듈끼리 주고받는 메시지는 c_game / s_game (내용은 게임 모듈이 정함)
## - 시계 맞추기: 클라이언트가 주기적으로 ping → server_now() 로 서버 시계를 추정

signal connected
signal connection_failed(reason: String)
signal disconnected
signal login_result(ok: bool, message: String)
signal room_list_updated(rooms: Array)
signal room_updated(room: Dictionary)
signal left_room(reason: String)
signal error_message(text: String)
signal chat_received(nick: String, text: String, system: bool)
signal game_started(room: Dictionary)
signal game_message(msg: Array)          # 클라이언트: 서버의 게임 모듈이 보낸 메시지

const GameRegistry := preload("res://scripts/core/game_registry.gd")
const Series := preload("res://scripts/core/series.gd")
const Teams := preload("res://scripts/core/teams.gd")
const WordFilter := preload("res://scripts/core/word_filter.gd")

## 서버·클라이언트 통신 규약 버전. 메시지 형식이 바뀌면 올린다 → 다르면 로그인 단계에서 안내
const PROTOCOL_VERSION := 21
const LOGIN_TIMEOUT := 6.0
const DEFAULT_PORT := 7777
const DEFAULT_TEAMS := 2                    # 새 방의 기본 모드: 2팀전 (0 = 개인전)
const DEFAULT_ROUNDS := 3                   # 새 방의 기본 라운드 수 (1판 = 최대 5라운드)
const DEFAULT_SERVER := "wss://spwsv.cloudish.cloud"    # 게임 서버 (웹 게임 페이지는 spw.cloudish.cloud)

## 접속 화면에 보여줄 서버 목록 — 사용자에게는 이름만 보이고 주소는 노출하지 않는다.
## 서버를 늘리면 여기에 한 줄씩 추가.
const SERVER_LIST := [
    {"name": "서버 1", "url": DEFAULT_SERVER},
]
## 개발용 (에디터 실행·디버그 빌드에서만 목록에 표시, 릴리스·웹 빌드에선 숨김)
const LOCAL_TEST_SERVER := {"name": "로컬 테스트 (이 PC)", "url": "ws://127.0.0.1:7777"}
const MAX_PLAYERS_LIMIT := 12
## 시작 최소 인원은 게임 모듈별 min_players (games/<게임>/module.gd)
const NICK_MIN := 2
const NICK_MAX := 12
const ROOM_NAME_MAX := 20
const CHAT_MAX := 120
const CONNECT_TIMEOUT := 6.0
const MATCH_SCENE := "res://scenes/match.tscn"
## 신고 사유 (관리 서버 REPORT_REASONS 와 같아야 함)
const REPORT_REASONS := {"abuse": "욕설·비하", "spam": "도배·광고", "nickname": "부적절한 닉네임", "cheat": "핵·부정 이용", "other": "기타"}
const DEVICE_FILE := "user://device.cfg"
const ROOM_CHAT_KEEP := 40              # 서버: 방마다 최근 채팅 몇 개를 기억하나 (신고에 첨부, 저장은 안 함)

var is_server := false
var server_name := ""                   # 현재 접속한 서버의 표시 이름

# ---- 클라이언트 상태
var my_id := 0
var nickname := ""
var rooms: Array = []
var room: Dictionary = {}               # 현재 방 스냅샷 (없으면 빈 딕셔너리)
var match_config: Dictionary = {}       # 게임 시작 시 받은 방 정보 (게임 씬에서 사용)
var chat_log: Array = []                # 현재 방 채팅 기록 [{nick, text, system}]
var blocked: Dictionary = {}            # 클라이언트: 차단한 사람 uid -> 닉네임 (이 기기에만 저장, 채팅 숨김)
var _device_id := ""
var _connect_timer: SceneTreeTimer
var _connecting := false
var rtt := 0.0                          # 왕복 지연(초)
var _clock_offset := 0.0                # 서버 시계 - 내 시계
var _clock_samples: Array = []          # [[rtt, offset], ...]
var _clock_synced := false
var _ping_timer := 0.0
var _ping_count := 0

# ---- 서버 상태
var _players := {}                      # peer_id -> {nick, room}
var _client_versions := {}              # peer_id -> 게임 버전 (x_hello 로 받음)
var _client_devices := {}               # peer_id -> 기기 ID (y_device 로 받음, 제재 기준)
var _client_accounts := {}              # peer_id -> 계정 {id, ...} (y_auth 토큰을 관리 서버로 확인한 결과, 실패면 {})
var _pending_logins := {}               # peer_id -> [nick] 계정 확인이 끝나면 이어서 로그인
var _sanctions: Array = []              # 관리 서버의 제재 목록 [{device, kind, until, reason}]
var _mod_http: HTTPRequest
var _report_queue: Array = []           # 관리 서버로 보낼 신고 (차례로 전송)
var _report_http: HTTPRequest
var _min_client_version := "0.0.0"     # release.json 의 min_supported (서버가 시작할 때 읽음)
## 점검 모드 (관리 서버 /api/status 를 주기적으로 읽음). 켜지면 새 로그인·방 만들기를 막는다
var maintenance := {"on": false, "message": ""}
var _admin_http: HTTPRequest
const ADMIN_POLL_SEC := 15.0
var _rooms := {}                        # room_id -> {id, name, host, max, bot_fill, state, members[], ready{}, returned{}, rounds, round_games[], series{}}
var _next_room_id := 1
var _nick_regex := RegEx.new()
var _status_server: TCPServer
var _status_clients: Array = []         # [{peer: StreamPeerTCP, buf: String, t: float}]
var _started_at := 0.0
var _matches := {}                      # room_id -> {vp: SubViewport, game: Node}


func _ready() -> void:
    _nick_regex.compile("^[가-힣A-Za-z0-9_\\-\\.]+$")
    _load_blocked()
    multiplayer.connected_to_server.connect(_on_connected_to_server)
    multiplayer.connection_failed.connect(_on_connection_failed)
    multiplayer.server_disconnected.connect(_on_server_disconnected)
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)

    var args := OS.get_cmdline_user_args()
    if "--server" in args:
        var port := DEFAULT_PORT
        var i := args.find("--port")
        if i >= 0 and i + 1 < args.size():
            port = int(args[i + 1])
        var status_port := port + 1
        var j := args.find("--status-port")
        if j >= 0 and j + 1 < args.size():
            status_port = int(args[j + 1])
        _min_client_version = String(Boot.read_release().get("min_supported", "0.0.0"))
        print("[server] 최소 클라이언트 버전 %s" % _min_client_version)
        if start_server(port) == OK:
            _start_status_server(status_port)
            _start_admin_poll()


# ================================================================ 공통
func is_online() -> bool:
    var p := multiplayer.multiplayer_peer
    return p != null and not (p is OfflineMultiplayerPeer) \
            and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## 이 PC의 시계(초)
static func local_time() -> float:
    return Time.get_ticks_usec() / 1000000.0


## 서버 시계(초) — 클라이언트는 ping 으로 추정한 값
func server_now() -> float:
    if is_server:
        return local_time()
    return local_time() + _clock_offset


func is_clock_synced() -> bool:
    return is_server or _clock_synced


func is_logged_in() -> bool:
    return is_online() and nickname != ""


func in_room() -> bool:
    return not room.is_empty()


func is_host() -> bool:
    return in_room() and int(room.get("host", -1)) == my_id


## 시작할 수 없는 이유 (가능하면 ""). 클라이언트 버튼 상태와 서버 검증에 함께 사용
static func start_block_reason(r: Dictionary) -> String:
    if r.is_empty():
        return "방이 없습니다"
    if r.get("state", "") != "waiting":
        return "이미 게임 중입니다"
    var members: Array = r.get("members", [])
    var round_games: Array = r.get("round_games", [r.get("game", "")])
    for i in round_games.size():
        var choice := String(round_games[i])
        var mods: Array = GameRegistry.all() if choice == Series.RANDOM else [GameRegistry.get_or_default(choice)]
        var any_ok := false
        var need := 99
        for module in mods:
            var bots_ok: bool = r.get("bot_fill", false) and module.supports_bots
            if members.size() >= module.min_players or bots_ok:
                any_ok = true
            need = mini(need, module.min_players)
        if not any_ok:
            return "%d라운드(%s): 최소 %d명이 필요합니다 (또는 봇 채우기)" % [i + 1, Series.choice_name(choice), need]
    var teams := int(r.get("teams", 0))
    if teams >= 2:
        for choice in round_games:
            if String(choice) != Series.RANDOM and not GameRegistry.get_or_default(String(choice)).supports_teams:
                return "%s 는 팀전을 지원하지 않아요" % GameRegistry.display_name(String(choice))
        var tr := Teams.block_reason(r)
        if tr != "":
            return tr
    for m in members:
        if not m.get("host", false) and not m.get("ready", false):
            return "모두 레디해야 시작할 수 있습니다"
    return ""


# ================================================================ 서버
func start_server(port: int) -> Error:
    var peer := WebSocketMultiplayerPeer.new()
    var err := peer.create_server(port)
    if err != OK:
        printerr("[server] 포트 %d 열기 실패 (%s)" % [port, error_string(err)])
        return err
    multiplayer.multiplayer_peer = peer
    is_server = true
    print("[server] 대기 중 — 포트 %d" % port)
    return OK


func _on_peer_connected(id: int) -> void:
    if is_server:
        print("[server] 접속 %d" % id)


func _on_peer_disconnected(id: int) -> void:
    if not is_server:
        return
    _client_versions.erase(id)
    _client_devices.erase(id)
    _client_accounts.erase(id)
    _pending_logins.erase(id)
    if _players.has(id):
        print("[server] 퇴장 %s (%d)" % [_players[id].nick, id])
        _leave_room(id, "")
        _players.erase(id)


func _sender() -> int:
    var id := multiplayer.get_remote_sender_id()
    return id if _players.has(id) else 0


func _validate_nick(nick: String) -> String:
    if nick.length() < NICK_MIN or nick.length() > NICK_MAX:
        return "닉네임은 %d~%d자여야 합니다" % [NICK_MIN, NICK_MAX]
    if _nick_regex.search(nick) == null:
        return "닉네임은 한글, 영문, 숫자, _ - . 만 쓸 수 있습니다"
    if WordFilter.contains(nick):
        return "쓸 수 없는 단어가 들어 있는 닉네임입니다"
    for id in _players:
        if String(_players[id].nick).to_lower() == nick.to_lower():
            return "이미 사용 중인 닉네임입니다"
    return ""


func _room_snapshot(rid: int) -> Dictionary:
    var r: Dictionary = _rooms[rid]
    var members := []
    for pid in r.members:
        members.append({
            "id": pid,
            "nick": _players[pid].nick,
            "ready": r.ready.get(pid, false),
            "host": pid == r.host,
            "team": int(r.team.get(pid, 0)),
            "uid": String(_players[pid].get("uid", "")),      # 차단용 (기기 ID 를 해시한 값)
        })
    return {
        "id": r.id, "name": r.name, "host": r.host, "max": r.max, "game": r.game,
        "bot_fill": r.bot_fill, "state": r.state, "members": members,
        "rounds": r.rounds, "round_games": r.round_games, "series": _series_view(r),
        "teams": r.teams,
    }


## 방 정보에 실어 보낼 시리즈 상태 (점수표는 순위순 배열로)
func _series_view(r: Dictionary) -> Dictionary:
    var s: Dictionary = r.get("series", {})
    if s.is_empty():
        return {}
    return {
        "round": s.round, "total": s.total, "phase": s.phase, "game": s.game, "games": s.games,
        "participants": s.participants, "standings": Series.standings(s), "last": s.last,
        "ready": s.ready.keys(), "next_at": s.next_at,
    }


func _public_rooms() -> Array:
    var out := []
    for rid in _rooms:
        var r: Dictionary = _rooms[rid]
        out.append({
            "id": rid, "name": r.name, "host_nick": _players[r.host].nick, "game": r.game,
            "count": r.members.size(), "max": r.max, "state": r.state, "bot_fill": r.bot_fill,
            "rounds": r.rounds, "teams": r.teams,
        })
    out.sort_custom(func(a, b): return a.id < b.id)
    return out


func _peer_alive(pid: int) -> bool:
    return multiplayer.get_peers().has(pid)


func _broadcast_room_list() -> void:
    var list := _public_rooms()
    for pid in _players:
        if int(_players[pid].room) == 0 and _peer_alive(pid):
            s_room_list.rpc_id(pid, list)


func _send_room(rid: int) -> void:
    if not _rooms.has(rid):
        return
    var snap := _room_snapshot(rid)
    for pid in _rooms[rid].members:
        if _peer_alive(pid):
            s_room_state.rpc_id(pid, snap)


func _room_system_chat(rid: int, text: String) -> void:
    for pid in _rooms[rid].members:
        if _peer_alive(pid):
            s_chat.rpc_id(pid, "", text, true)


func _leave_room(pid: int, reason: String) -> void:
    var rid := int(_players[pid].room)
    if rid == 0 or not _rooms.has(rid):
        return
    var r: Dictionary = _rooms[rid]
    r.members.erase(pid)
    r.ready.erase(pid)
    r.returned.erase(pid)
    r.team.erase(pid)
    _series_drop(r, pid)
    _players[pid].room = 0
    if _peer_alive(pid):
        s_left_room.rpc_id(pid, reason)
        s_room_list.rpc_id(pid, _public_rooms())
    _match_player_left(rid, pid)
    if r.members.is_empty():
        _rooms.erase(rid)
        _free_match(rid)
        print("[server] 방 삭제 #%d" % rid)
    else:
        _room_system_chat(rid, "%s 님이 나갔습니다" % _players[pid].nick)
        if r.host == pid:
            r.host = r.members[0]
            r.ready.erase(r.host)
            _room_system_chat(rid, "%s 님이 새 방장입니다" % _players[r.host].nick)
        _check_all_returned(rid)
        _maybe_next_round(rid)
        _send_room(rid)
    _broadcast_room_list()


func _check_all_returned(rid: int) -> void:
    var r: Dictionary = _rooms[rid]
    if r.state != "playing":
        return
    for pid in r.members:
        if not r.returned.get(pid, false):
            return
    var s: Dictionary = r.series
    if not s.is_empty() and s.phase == "final":
        var w := Series.winners(s)
        if not w.is_empty():
            _room_system_chat(rid, "최종 우승: %s" % ", ".join(w))
    elif not s.is_empty():
        _room_system_chat(rid, "라운드 %d/%d 에서 경기를 마쳤습니다" % [s.round, s.total])
    r.state = "waiting"
    r.ready.clear()
    r.returned.clear()
    r.series = {}
    _free_match(rid)
    _room_system_chat(rid, "모두 돌아왔습니다. 다시 레디해 주세요")


# ---- 경기 (서버가 방마다 게임을 직접 돌림)
func _create_match(rid: int, snap: Dictionary) -> void:
    _free_match(rid)
    var vp := SubViewport.new()
    vp.name = "Match%d" % rid
    vp.own_world_3d = true                  # 방마다 독립된 물리 공간
    vp.size = Vector2i(2, 2)
    vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
    add_child(vp)
    var world: Node = load(MATCH_SCENE).instantiate()
    var cfg := snap.duplicate(true)
    cfg["game_id"] = String(snap.get("game", ""))
    cfg["room_id"] = rid
    world.set("server_config", cfg)
    vp.add_child(world)
    _matches[rid] = {"vp": vp, "game": world.get_node_or_null("Game")}
    print("[server] 경기 시작 #%d [%s]" % [rid, cfg.game_id])


func _free_match(rid: int) -> void:
    if not _matches.has(rid):
        return
    var m: Dictionary = _matches[rid]
    _matches.erase(rid)
    if is_instance_valid(m.vp):
        m.vp.queue_free()
    print("[server] 경기 정리 #%d" % rid)


func _match_game(rid: int) -> Node:
    if not _matches.has(rid):
        return null
    var g = _matches[rid].game
    return g if is_instance_valid(g) else null


func _match_player_left(rid: int, pid: int) -> void:
    var g := _match_game(rid)
    if g and g.has_method(&"on_player_left"):
        g.on_player_left(pid)


## 서버: 게임 모듈 → 특정 플레이어
func send_game_to(pid: int, msg: Array, reliable: bool = true) -> void:
    if not _peer_alive(pid):
        return
    if reliable:
        s_game.rpc_id(pid, msg)
    else:
        s_game_u.rpc_id(pid, msg)


## 서버: 게임 모듈 → 방 안 모든 플레이어 (except_pid 제외)
func broadcast_game(rid: int, msg: Array, reliable: bool = true, except_pid: int = 0) -> void:
    if not _rooms.has(rid):
        return
    for pid in _rooms[rid].members:
        if pid != except_pid:
            send_game_to(pid, msg, reliable)


## 클라이언트: 게임 모듈 → 서버
func send_game(msg: Array, reliable: bool = true) -> void:
    if not is_online():
        return
    if reliable:
        c_game.rpc_id(1, msg)
    else:
        c_game_u.rpc_id(1, msg)


func _route_client_game(msg: Array) -> void:
    var id := _sender()
    if not is_server or id == 0:
        return
    var g := _match_game(int(_players[id].room))
    if g and g.has_method(&"on_client_message"):
        g.on_client_message(id, msg)


@rpc("any_peer", "call_remote", "reliable")
func c_game(msg: Array) -> void:
    _route_client_game(msg)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func c_game_u(msg: Array) -> void:
    _route_client_game(msg)


@rpc("authority", "call_remote", "reliable")
func s_game(msg: Array) -> void:
    game_message.emit(msg)


@rpc("authority", "call_remote", "unreliable_ordered")
func s_game_u(msg: Array) -> void:
    game_message.emit(msg)


# ---- 시계 맞추기
@rpc("any_peer", "call_remote", "unreliable")
func c_ping(client_t: float) -> void:
    if is_server:
        s_pong.rpc_id(multiplayer.get_remote_sender_id(), client_t, local_time())


@rpc("authority", "call_remote", "unreliable")
func s_pong(client_t: float, server_t: float) -> void:
    var now := local_time()
    var r := now - client_t
    if r < 0.0 or r > 5.0:
        return
    _clock_samples.append([r, server_t + r * 0.5 - now])
    if _clock_samples.size() > 12:
        _clock_samples.pop_front()
    # 왕복이 가장 짧았던 측정이 가장 정확하다
    var best: Array = _clock_samples[0]
    for smp in _clock_samples:
        if smp[0] < best[0]:
            best = smp
    var target: float = best[1]
    if not _clock_synced or absf(target - _clock_offset) > 0.25:
        _clock_offset = target
    else:
        _clock_offset = lerpf(_clock_offset, target, 0.2)
    rtt = lerpf(rtt, r, 0.3) if _clock_synced else r
    _clock_synced = true


func _update_clock(delta: float) -> void:
    if not is_online():
        return
    _ping_timer -= delta
    if _ping_timer > 0.0:
        return
    _ping_count += 1
    _ping_timer = 0.2 if _ping_count < 8 else 1.0     # 접속 직후엔 빠르게 여러 번
    c_ping.rpc_id(1, local_time())


# ---- 상태 페이지 (HTTP, 헬스체크용)
func _start_status_server(port: int) -> void:
    _started_at = Time.get_unix_time_from_system()
    _status_server = TCPServer.new()
    var err := _status_server.listen(port)
    if err != OK:
        printerr("[server] 상태 페이지 포트 %d 열기 실패 (%s)" % [port, error_string(err)])
        _status_server = null
        return
    print("[server] 상태 페이지 — http://0.0.0.0:%d/  (헬스체크 /health)" % port)


func _process(delta: float) -> void:
    if not is_server:
        _update_clock(delta)
        return
    _tick_series()
    if _status_server == null:
        return
    while _status_server.is_connection_available():
        _status_clients.append({"peer": _status_server.take_connection(), "buf": "", "t": 0.0})
    var keep: Array = []
    for c in _status_clients:
        var peer: StreamPeerTCP = c.peer
        peer.poll()
        c.t += delta
        if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
            continue
        var n := peer.get_available_bytes()
        if n > 0:
            c.buf += peer.get_utf8_string(mini(n, 4096))
        if c.buf.contains("\r\n\r\n") or c.buf.contains("\n\n") or c.t > 2.0:
            _respond_status(peer, c.buf)
            peer.disconnect_from_host()
        elif c.buf.length() < 16384:
            keep.append(c)
    _status_clients = keep


func _respond_status(peer: StreamPeerTCP, request: String) -> void:
    var path := "/"
    var first := request.get_slice("\n", 0).split(" ")
    if first.size() >= 2:
        path = first[1]
    var body: String
    var ctype := "text/html; charset=utf-8"
    if path.begins_with("/health"):
        body = "ok"
        ctype = "text/plain; charset=utf-8"
    elif path.begins_with("/status.json"):
        body = JSON.stringify(_status_data())
        ctype = "application/json; charset=utf-8"
    else:
        body = _status_html()
    var bytes := body.to_utf8_buffer()
    var head := "HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" % [ctype, bytes.size()]
    peer.put_data(head.to_utf8_buffer())
    peer.put_data(bytes)


func _status_data() -> Dictionary:
    var room_list := []
    for r in _public_rooms():
        room_list.append({"name": r.name, "host": r.host_nick, "game": GameRegistry.display_name(r.game),
                "players": r.count, "max": r.max, "state": r.state})
    return {
        "status": "ok",
        "game": ProjectSettings.get_setting("application/config/name"),
        "godot": Engine.get_version_info().string,
        "protocol": PROTOCOL_VERSION,
        "version": Boot.version(),
        "maintenance": maintenance,
        "min_client_version": _min_client_version,
        "uptime_sec": int(Time.get_unix_time_from_system() - _started_at),
        "connections": multiplayer.get_peers().size(),
        "players": _players.size(),
        "rooms": room_list,
        "matches": _matches.size(),
    }


func _status_html() -> String:
    var d := _status_data()
    var up := int(d.uptime_sec)
    var uptime := "%d일 %02d:%02d:%02d" % [up / 86400, (up / 3600) % 24, (up / 60) % 60, up % 60]
    var rows := ""
    for r in d.rooms:
        rows += "<tr><td>%s</td><td>%s</td><td>%s</td><td>%d / %d</td><td>%s</td></tr>" % [
            String(r.name).xml_escape(), String(r.game).xml_escape(), String(r.host).xml_escape(), r.players, r.max,
            "게임 중" if r.state == "playing" else "대기 중"]
    if rows == "":
        rows = "<tr><td colspan=5 class=m>열린 방 없음</td></tr>"
    return """<!doctype html><html lang=ko><meta charset=utf-8><meta name=viewport content="width=device-width">
<title>%s 서버</title><meta http-equiv=refresh content=10>
<style>body{font-family:system-ui,sans-serif;background:linear-gradient(#6aa8f8,#b8edd2);min-height:100vh;margin:0;display:flex;justify-content:center;align-items:flex-start}
.c{background:#fff;margin:48px 16px;padding:28px 32px;border-radius:20px;box-shadow:0 8px 24px #0002;max-width:640px;width:100%%}
h1{margin:0 0 4px}.ok{color:#2e9e5b;font-weight:700}.m{color:#778}table{width:100%%;border-collapse:collapse;margin-top:12px}
td,th{padding:8px;border-bottom:1px solid #eef;text-align:left}</style>
<div class=c><h1>%s</h1><p class=ok>● 서버 정상</p>
<p>접속 %d · 로그인 %d명 · 방 %d개<br><span class=m>가동 %s · Godot %s · 프로토콜 v%d · 10초마다 새로고침</span></p>
<table><tr><th>방</th><th>게임</th><th>방장</th><th>인원</th><th>상태</th></tr>%s</table></div></html>""" % [
        d.game, d.game, d.connections, d.players, d.rooms.size(), uptime, d.godot, d.protocol, rows]


# ---- 클라이언트 → 서버 요청
@rpc("any_peer", "call_remote", "reliable")
func c_login(nick: String, protocol: int) -> void:
    if not is_server:
        return
    var id := multiplayer.get_remote_sender_id()
    if _players.has(id):
        return
    if protocol != PROTOCOL_VERSION:
        var newer := protocol > PROTOCOL_VERSION
        s_login_result.rpc_id(id, false, "게임 버전이 서버와 다릅니다 (%s). %s" % [
            "게임이 더 새 버전" if newer else "게임이 예전 버전",
            "서버 업데이트가 필요합니다" if newer else "새로고침하거나 최신 버전을 받아 주세요"])
        return
    if maintenance.on:
        s_login_result.rpc_id(id, false, _maintenance_text())
        return
    var ver := String(_client_versions.get(id, "0.0.0"))
    if Boot.compare(ver, _min_client_version) < 0:
        s_login_result.rpc_id(id, false, "새 버전(%s 이상)이 나왔어요. 첫 화면의 업데이트 버튼으로 업데이트해 주세요" % _min_client_version)
        return
    # 온라인은 계정 로그인 필수 (관리 서버가 있을 때). 토큰 확인이 아직이면 끝날 때 이어서 처리
    if _accounts_required():
        if not _client_accounts.has(id):
            _pending_logins[id] = [nick]         # y_auth 확인이 끝나면 _finish_login
            return
        if (_client_accounts[id] as Dictionary).is_empty():
            s_login_result.rpc_id(id, false, "계정 로그인이 필요해요. 첫 화면에서 로그인해 주세요")
            return
    _finish_login(id, nick)


func _finish_login(id: int, nick: String) -> void:
    var dev := String(_client_devices.get(id, ""))
    if dev == "":
        dev = "srv" + Crypto.new().generate_random_bytes(12).hex_encode()     # 기기 ID 를 안 보낸 경우 (이 접속에만)
    var acc_id := String((_client_accounts.get(id, {}) as Dictionary).get("id", ""))
    var ban := _sanction_for(dev, "ban", acc_id)
    if not ban.is_empty():
        s_login_result.rpc_id(id, false, "이용이 제한된 계정입니다%s. 문의: 정보 → 이메일" % _until_text(ban))
        return
    nick = nick.strip_edges()
    var err := _validate_nick(nick)
    if err != "":
        s_login_result.rpc_id(id, false, err)
        return
    _players[id] = {"nick": nick, "room": 0, "dev": dev, "account": acc_id,
            "uid": (acc_id if acc_id != "" else dev).sha256_text().left(16)}
    print("[server] 로그인 %s (%d)" % [nick, id])
    s_login_result.rpc_id(id, true, nick)
    s_room_list.rpc_id(id, _public_rooms())


@rpc("any_peer", "call_remote", "reliable")
func c_request_rooms() -> void:
    var id := _sender()
    if is_server and id:
        s_room_list.rpc_id(id, _public_rooms())


@rpc("any_peer", "call_remote", "reliable")
func c_create_room(room_name: String, max_players: int, bot_fill: bool, game_id: String) -> void:
    var id := _sender()
    if not is_server or id == 0:
        return
    if maintenance.on:
        s_error.rpc_id(id, _maintenance_text())
        return
    if int(_players[id].room) != 0:
        s_error.rpc_id(id, "이미 방에 있습니다")
        return
    room_name = WordFilter.mask(room_name.strip_edges().left(ROOM_NAME_MAX))
    if room_name == "":
        room_name = "%s의 방" % _players[id].nick
    var module = GameRegistry.get_or_default(game_id)
    var rid := _next_room_id
    _next_room_id += 1
    _rooms[rid] = {
        "id": rid, "name": room_name, "host": id, "game": module.id,
        "max": clampi(max_players, 2, mini(MAX_PLAYERS_LIMIT, module.max_players)), "bot_fill": bot_fill,
        "state": "waiting", "members": [id], "ready": {}, "returned": {},
        "rounds": DEFAULT_ROUNDS, "round_games": [module.id, module.id, module.id].slice(0, DEFAULT_ROUNDS), "series": {},
        "teams": DEFAULT_TEAMS, "team": {},
    }
    var r0: Dictionary = _rooms[rid]
    if r0.teams >= 2:
        r0.team[id] = 0
        # 최대 인원을 팀 수의 배수로 (예: 5명 → 6명, 안 되면 4명)
        r0.max = Teams.fit_max(r0.max, r0.teams, 1, mini(MAX_PLAYERS_LIMIT, module.max_players))
        if r0.max < r0.teams:
            r0.teams = 0
            r0.team.clear()
    _players[id].room = rid
    print("[server] 방 생성 #%d '%s' [%s] by %s" % [rid, room_name, module.id, _players[id].nick])
    _send_room(rid)
    _room_system_chat(rid, "방이 만들어졌습니다")
    _broadcast_room_list()


@rpc("any_peer", "call_remote", "reliable")
func c_join_room(rid: int) -> void:
    var id := _sender()
    if not is_server or id == 0:
        return
    if int(_players[id].room) != 0:
        s_error.rpc_id(id, "이미 방에 있습니다")
        return
    if not _rooms.has(rid):
        s_error.rpc_id(id, "방이 사라졌습니다")
        s_room_list.rpc_id(id, _public_rooms())
        return
    var r: Dictionary = _rooms[rid]
    if r.state != "waiting":
        s_error.rpc_id(id, "게임이 진행 중인 방입니다")
        return
    if r.members.size() >= r.max:
        s_error.rpc_id(id, "방이 가득 찼습니다")
        return
    if r.teams >= 2:
        r.team[id] = Teams.smallest(_room_snapshot(rid).members, r.teams)
    r.members.append(id)
    r.ready[id] = false
    _players[id].room = rid
    _send_room(rid)
    _room_system_chat(rid, "%s 님이 들어왔습니다" % _players[id].nick)
    _broadcast_room_list()


@rpc("any_peer", "call_remote", "reliable")
func c_leave_room() -> void:
    var id := _sender()
    if is_server and id:
        _leave_room(id, "")


@rpc("any_peer", "call_remote", "reliable")
func c_set_ready(is_ready: bool) -> void:
    var id := _sender()
    if not is_server or id == 0:
        return
    var rid := int(_players[id].room)
    if rid == 0:
        return
    var r: Dictionary = _rooms[rid]
    if r.state != "waiting" or r.host == id:
        return
    r.ready[id] = is_ready
    _send_room(rid)


@rpc("any_peer", "call_remote", "reliable")
func c_update_settings(settings: Dictionary) -> void:
    var id := _sender()
    if not is_server or id == 0:
        return
    var rid := int(_players[id].room)
    if rid == 0 or _rooms[rid].host != id:
        return
    var r: Dictionary = _rooms[rid]
    if r.state != "waiting":
        return
    if settings.has("name"):
        var n := WordFilter.mask(String(settings.name).strip_edges().left(ROOM_NAME_MAX))
        if n != "":
            r.name = n
    var games_changed := false
    if settings.has("game"):            # 예전 클라이언트 호환: 1라운드 게임
        settings["round_game"] = [0, String(settings.game)]
    if settings.has("rounds"):
        var n := clampi(int(settings.rounds), Series.MIN_ROUNDS, Series.MAX_ROUNDS)
        if n != r.rounds:
            var list: Array = r.round_games
            while list.size() < n:
                list.append(list.back())       # 늘리면 마지막 라운드 게임을 이어서
            list.resize(n)
            r.rounds = n
            games_changed = true
            _room_system_chat(rid, "라운드 수가 %d(으)로 바뀌었습니다" % n)
    if settings.has("round_game") and settings.round_game is Array and settings.round_game.size() == 2:
        var i := int(settings.round_game[0])
        var g := String(settings.round_game[1])
        if i >= 0 and i < r.rounds and Series.is_valid_choice(g) and r.round_games[i] != g:
            r.round_games[i] = g
            games_changed = true
            _room_system_chat(rid, "%d라운드 게임이 '%s'(으)로 바뀌었습니다" % [i + 1, Series.choice_name(g)])
    if settings.has("teams"):
        var t := int(settings.teams)
        if Teams.MODES.has(t) and t != r.teams:
            r.teams = t
            r.team.clear()
            if t >= 2:
                for i in r.members.size():
                    r.team[r.members[i]] = i % t       # 고르게 나눔
            r.ready.clear()
            var old_max: int = r.max
            r.max = Teams.fit_max(r.max, t, r.members.size(), mini(MAX_PLAYERS_LIMIT, Series.max_players_for(r.round_games)))
            if r.max != old_max:
                _room_system_chat(rid, "%s(으)로 바뀌었습니다 · 최대 인원 %d명" % [Teams.mode_name(t), r.max])
            else:
                _room_system_chat(rid, "%s(으)로 바뀌었습니다" % Teams.mode_name(t))
    if games_changed:
        r.game = r.round_games[0]
        var mx := Series.max_players_for(r.round_games)
        if r.max > mx:
            r.max = Teams.fit_max(maxi(mx, r.members.size()), r.teams, r.members.size(), mini(MAX_PLAYERS_LIMIT, mx), false)
        r.ready.clear()     # 게임이 바뀌면 다시 레디
    var game_max: int = Series.max_players_for(r.round_games)
    if settings.has("max"):
        var want := int(settings.max)
        r.max = Teams.fit_max(want, r.teams, r.members.size(), mini(MAX_PLAYERS_LIMIT, game_max), want > r.max)
        if want < r.members.size():
            s_error.rpc_id(id, "현재 인원(%d명)보다 적게 줄일 수 없습니다" % r.members.size())
    if settings.has("bot_fill"):
        r.bot_fill = bool(settings.bot_fill)
    _send_room(rid)
    _broadcast_room_list()


@rpc("any_peer", "call_remote", "reliable")
func c_kick(target: int) -> void:
    var id := _sender()
    if not is_server or id == 0:
        return
    var rid := int(_players[id].room)
    if rid == 0 or _rooms[rid].host != id or target == id or not _rooms[rid].members.has(target):
        return
    _leave_room(target, "방장에 의해 강퇴되었습니다")


@rpc("any_peer", "call_remote", "reliable")
func c_transfer_host(target: int) -> void:
    var id := _sender()
    if not is_server or id == 0:
        return
    var rid := int(_players[id].room)
    if rid == 0 or _rooms[rid].host != id or not _rooms[rid].members.has(target):
        return
    var r: Dictionary = _rooms[rid]
    r.host = target
    r.ready.erase(target)
    r.ready[id] = false
    _room_system_chat(rid, "%s 님이 새 방장입니다" % _players[target].nick)
    _send_room(rid)
    _broadcast_room_list()


@rpc("any_peer", "call_remote", "reliable")
func c_chat(text: String) -> void:
    var id := _sender()
    if not is_server or id == 0:
        return
    var rid := int(_players[id].room)
    text = text.strip_edges().left(CHAT_MAX)
    if rid == 0 or text == "":
        return
    var mute := _sanction_for(String(_players[id].get("dev", "")), "mute", String(_players[id].get("account", "")))
    if not mute.is_empty():
        s_chat.rpc_id(id, "", "채팅이 제한된 상태예요%s" % _until_text(mute), true)
        return
    text = WordFilter.mask(text)
    var r: Dictionary = _rooms[rid]
    var recent: Array = r.get("chat", [])
    recent.append({"t": Time.get_datetime_string_from_system(true) + "Z", "nick": _players[id].nick, "text": text})
    r["chat"] = recent.slice(-ROOM_CHAT_KEEP)
    for pid in r.members:
        s_chat.rpc_id(pid, _players[id].nick, text, false)


@rpc("any_peer", "call_remote", "reliable")
func c_start_game() -> void:
    var id := _sender()
    if not is_server or id == 0:
        return
    var rid := int(_players[id].room)
    if rid == 0 or _rooms[rid].host != id:
        return
    var reason := start_block_reason(_room_snapshot(rid))
    if reason != "":
        s_error.rpc_id(id, reason)
        return
    var r: Dictionary = _rooms[rid]
    # 하루 판수 (정식 출시 단계에서만 관리 서버가 차감·거절). 관리 서버가 응답하지 않으면 그냥 진행
    if _accounts_required() and not r.get("_starting", false):
        r["_starting"] = true
        var accs := []
        for pid in r.members:
            var a := String(_players[pid].get("account", ""))
            if a != "":
                accs.append(a)
        var res := await _admin_post("/internal/plays/start", {"accounts": accs})
        if _rooms.has(rid):
            r.erase("_starting")
        if not _rooms.has(rid) or r.state != "waiting" or r.host != id or start_block_reason(_room_snapshot(rid)) != "":
            return
        if res.get("ok", true) == false:
            var names := []
            for pid in r.members:
                if (res.get("blocked", []) as Array).has(String(_players[pid].get("account", ""))):
                    names.append(_players[pid].nick)
            for pid in r.members:
                s_error.rpc_id(pid, "오늘 플레이할 수 있는 판을 다 쓴 사람이 있어요: %s (광고를 보면 판이 늘어나요)" % ", ".join(names))
            return
    elif r.get("_starting", false):
        return
    r.state = "playing"
    r.returned.clear()
    r.series = Series.create(r.rounds, r.members)
    # 팀전: 팀 배정과 팀 인원을 시리즈 내내 고정 (나간 자리는 봇이 채움)
    r.series["teams"] = r.teams
    r.series["team_of"] = r.team.duplicate()
    r.series["team_size"] = Teams.team_size(_room_snapshot(rid))
    print("[server] 게임 시작 #%d (%d명, %d라운드)" % [rid, r.members.size(), r.rounds])
    _start_round(rid)
    _broadcast_room_list()


@rpc("any_peer", "call_remote", "reliable")
func c_return_to_room() -> void:
    var id := _sender()
    if not is_server or id == 0:
        return
    var rid := int(_players[id].room)
    if rid == 0:
        return
    _rooms[rid].returned[id] = true
    _match_player_left(rid, id)        # 경기 도중 나가면 기권
    _series_drop(_rooms[rid], id)      # 남은 라운드에서도 빠짐
    _check_all_returned(rid)
    if _rooms.has(rid):
        _maybe_next_round(rid)
    _send_room(rid)
    _broadcast_room_list()


# ================================================================ 서버 → 클라이언트
@rpc("authority", "call_remote", "reliable")
func s_login_result(ok: bool, message: String) -> void:
    if ok:
        nickname = message
        my_id = multiplayer.get_unique_id()
    login_result.emit(ok, message)


@rpc("authority", "call_remote", "reliable")
func s_room_list(list: Array) -> void:
    rooms = list
    room_list_updated.emit(list)


@rpc("authority", "call_remote", "reliable")
func s_room_state(snap: Dictionary) -> void:
    if room.get("id", -1) != snap.get("id", -2):
        chat_log.clear()
    room = snap
    room_updated.emit(snap)


@rpc("authority", "call_remote", "reliable")
func s_left_room(reason: String) -> void:
    room = {}
    chat_log.clear()
    left_room.emit(reason)


@rpc("authority", "call_remote", "reliable")
func s_error(text: String) -> void:
    error_message.emit(text)


@rpc("authority", "call_remote", "reliable")
func s_chat(nick: String, text: String, system: bool) -> void:
    chat_log.append({"nick": nick, "text": text, "system": system})
    if chat_log.size() > 100:
        chat_log.pop_front()
    chat_received.emit(nick, text, system)


@rpc("authority", "call_remote", "reliable")
func s_game_start(snap: Dictionary) -> void:
    room = snap
    match_config = snap.duplicate(true)
    match_config["my_id"] = my_id
    match_config["game_id"] = String(snap.get("game", ""))
    game_started.emit(snap)


# ================================================================ 클라이언트 API
## 접속 화면에 보여줄 서버 목록 (이름/주소)
static func available_servers() -> Array:
    var list: Array = SERVER_LIST.duplicate(true)
    if is_dev_build():
        list.append(LOCAL_TEST_SERVER)
    return list


## 개발용 기능(로컬 테스트 서버 등)을 보여줄지: 에디터/디버그 빌드이면서 웹이 아닐 때
static func is_dev_build() -> bool:
    return OS.is_debug_build() and not OS.has_feature("web")


## 입력 주소를 WebSocket URL로 정규화
## - ws:// wss:// 는 그대로, http(s):// 는 ws(s):// 로
## - IP·localhost 는 ws://주소:포트 (포트 생략 시 7777)
## - 그 외 도메인은 wss://도메인 (리버스 프록시 HTTPS)
static func normalize_url(text: String) -> String:
    var t := text.strip_edges().trim_suffix("/")
    if t == "":
        return DEFAULT_SERVER
    if t.begins_with("ws://") or t.begins_with("wss://"):
        return t
    if t.begins_with("https://"):
        return "wss://" + t.substr(8)
    if t.begins_with("http://"):
        return "ws://" + t.substr(7)
    var host := t
    var port := ""
    var idx := t.rfind(":")
    if idx > 0:
        host = t.substr(0, idx)
        port = t.substr(idx + 1)
    var is_local := host == "localhost" or host.is_valid_ip_address()
    if is_local:
        return "ws://%s:%s" % [host, port if port != "" else str(DEFAULT_PORT)]
    return "wss://%s%s" % [host, (":" + port) if port != "" else ""]


func connect_to_server(url: String, display_name: String = "") -> void:
    _reset_client()
    server_name = display_name
    var peer := WebSocketMultiplayerPeer.new()
    var err := peer.create_client(normalize_url(url))
    if err != OK:
        connection_failed.emit("접속을 시작할 수 없습니다 (%s)" % error_string(err))
        return
    multiplayer.multiplayer_peer = peer
    _connecting = true
    _connect_timer = get_tree().create_timer(CONNECT_TIMEOUT)
    _connect_timer.timeout.connect(_on_connect_timeout)


func disconnect_from_server() -> void:
    if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
        multiplayer.multiplayer_peer.close()
    multiplayer.multiplayer_peer = null
    _reset_client()


func login(nick: String) -> void:
    x_hello.rpc_id(1, Boot.version())      # 같은 연결에서 순서대로 도착 (reliable)
    y_device.rpc_id(1, device_id())
    y_auth.rpc_id(1, Account.token)
    c_login.rpc_id(1, nick, PROTOCOL_VERSION)


func request_rooms() -> void:
    c_request_rooms.rpc_id(1)


func create_room(room_name: String, max_players: int, bot_fill: bool, game_id: String) -> void:
    c_create_room.rpc_id(1, room_name, max_players, bot_fill, game_id)


func join_room(rid: int) -> void:
    c_join_room.rpc_id(1, rid)


func leave_room() -> void:
    c_leave_room.rpc_id(1)


func set_ready(is_ready: bool) -> void:
    c_set_ready.rpc_id(1, is_ready)


func update_settings(settings: Dictionary) -> void:
    c_update_settings.rpc_id(1, settings)


func kick(target: int) -> void:
    c_kick.rpc_id(1, target)


func transfer_host(target: int) -> void:
    c_transfer_host.rpc_id(1, target)


func send_chat(text: String) -> void:
    c_chat.rpc_id(1, text)


func start_game() -> void:
    c_start_game.rpc_id(1)


func return_to_room() -> void:
    match_config = {}
    if is_online():
        c_return_to_room.rpc_id(1)


func _reset_client() -> void:
    _connecting = false
    _clock_samples.clear()
    _clock_synced = false
    _ping_count = 0
    _ping_timer = 0.0
    my_id = 0
    nickname = ""
    rooms = []
    room = {}
    match_config = {}
    chat_log = []


func _on_connected_to_server() -> void:
    _connecting = false
    connected.emit()


func _on_connect_timeout() -> void:
    if _connecting:
        disconnect_from_server()
        connection_failed.emit("서버에 연결할 수 없습니다 (시간 초과)")


func _on_connection_failed() -> void:
    if _connecting:
        _connecting = false
        multiplayer.multiplayer_peer = null
        connection_failed.emit("서버에 연결할 수 없습니다")


func _on_server_disconnected() -> void:
    multiplayer.multiplayer_peer = null
    _reset_client()
    disconnected.emit()


# ---- 클라이언트 → 서버: 게임 버전 알림 (로그인 직전)
# RPC 번호가 기존 함수들과 섞이지 않도록 이름이 맨 뒤로 정렬되고(x_) 파일 맨 끝에 둔다
@rpc("any_peer", "call_remote", "reliable")
func x_hello(version: String) -> void:
    if not is_server:
        return
    var id := multiplayer.get_remote_sender_id()
    _client_versions[id] = version.left(20)


# ---- 서버: 점검 모드 읽기 (관리 서버 ADMIN_URL/api/status, 없으면 끔)
func _start_admin_poll() -> void:
    var base := OS.get_environment("ADMIN_URL")
    if base == "":
        return
    _admin_http = HTTPRequest.new()
    _admin_http.timeout = 5.0
    add_child(_admin_http)
    _admin_http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray):
        if result == HTTPRequest.RESULT_SUCCESS and code == 200:
            var d = JSON.parse_string(body.get_string_from_utf8())
            if d is Dictionary and d.get("maintenance") is Dictionary:
                var m: Dictionary = d.maintenance
                var on := bool(m.get("on", false))
                if on != bool(maintenance.on):
                    print("[server] 점검 모드 %s" % ("켬" if on else "끔"))
                maintenance = {"on": on, "message": String(m.get("message", ""))})
    var timer := Timer.new()
    timer.wait_time = ADMIN_POLL_SEC
    timer.autostart = true
    add_child(timer)
    var poll := func():
        if _admin_http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
            _admin_http.request(base.trim_suffix("/") + "/api/status")
    timer.timeout.connect(poll)
    poll.call()
    _start_moderation_poll(base)


func _maintenance_text() -> String:
    var msg := String(maintenance.get("message", ""))
    return "서버 점검 중이에요." + (" " + msg if msg != "" else "") + " (혼자 연습은 할 수 있어요)"


# ================================================================ 시리즈 (여러 라운드) — 서버
## 다음 라운드 시작: 게임을 정하고 남아 있는 참가자에게 경기 시작을 보낸다
func _start_round(rid: int) -> void:
    var r: Dictionary = _rooms[rid]
    var s: Dictionary = r.series
    var players: Array = s.participants.filter(func(pid): return r.members.has(pid) and _peer_alive(pid))
    if players.is_empty():
        return
    s.round = int(s.round) + 1
    s.game = Series.resolve_game(String(r.round_games[s.round - 1]), players.size(), r.bot_fill, int(s.get("teams", 0)))
    s.games.append(s.game)
    s.phase = "playing"
    s.ready = {}
    s.next_at = 0.0
    var snap := _room_snapshot(rid)
    snap["game"] = s.game
    # 경기에는 이번 라운드 참가자만 (방으로 돌아간 사람 제외)
    snap["members"] = snap.members.filter(func(m): return players.has(int(m.id)))
    var module = GameRegistry.get_or_default(s.game)
    snap["bot_fill"] = bool(r.bot_fill) and module.supports_bots
    var teams := int(s.get("teams", 0))
    if teams >= 2 and module.supports_teams:
        snap["teams"] = teams
        snap["team_size"] = int(s.team_size)
        for m in snap.members:
            m["team"] = int(s.team_of.get(int(m.id), 0))
    else:
        snap["teams"] = 0
    print("[server] 라운드 %d/%d #%d [%s] %d명" % [s.round, s.total, rid, s.game, players.size()])
    _room_system_chat(rid, "라운드 %d/%d: %s" % [s.round, s.total, module.display_name])
    for pid in players:
        s_game_start.rpc_id(pid, snap)
    _create_match(rid, snap)
    _send_room(rid)


## 게임 모듈이 경기 결과를 알림 (PartyGame.report_result)
func on_match_result(rid: int, placements: Array) -> void:
    if not _rooms.has(rid):
        return
    var r: Dictionary = _rooms[rid]
    var s: Dictionary = r.series
    if s.is_empty() or s.phase != "playing":
        return
    Series.apply_result(s, placements)
    if s.phase == "between":
        s.next_at = server_now() + Series.BETWEEN_SEC
    var top: Array = s.last.rows.filter(func(row): return row.rank == 1)
    var first := ", ".join(PackedStringArray(top.map(func(row): return String(row.names))))
    print("[server] 라운드 %d/%d 끝 #%d 1등 %s" % [s.round, s.total, rid, first])
    _send_room(rid)


## 라운드 사이 레디 (클라이언트 → 서버)
@rpc("any_peer", "call_remote", "reliable")
func c_round_ready(on: bool) -> void:
    var id := _sender()
    if not is_server or id == 0:
        return
    var rid := int(_players[id].room)
    if rid == 0:
        return
    var s: Dictionary = _rooms[rid].series
    if s.is_empty() or s.phase != "between" or not s.participants.has(id):
        return
    if on:
        s.ready[id] = true
    else:
        s.ready.erase(id)
    if not _maybe_next_round(rid):
        _send_room(rid)


## 라운드 사이에 남은 참가자가 모두 레디했으면 다음 라운드 시작. 시작했으면 true
func _maybe_next_round(rid: int) -> bool:
    var r: Dictionary = _rooms[rid]
    var s: Dictionary = r.get("series", {})
    if s.is_empty() or s.phase != "between":
        return false
    var waiting := 0
    for pid in s.participants:
        if _peer_alive(pid) and not s.ready.get(pid, false):
            waiting += 1
    if waiting > 0:
        return false
    _start_round(rid)
    return true


## 라운드 사이 시간이 다 되면 다음 라운드 (서버 _process)
func _tick_series() -> void:
    var now := server_now()
    for rid in _rooms.keys():
        var s: Dictionary = _rooms[rid].get("series", {})
        if not s.is_empty() and s.phase == "between" and now >= float(s.next_at):
            _start_round(rid)


func _series_drop(r: Dictionary, pid: int) -> void:
    var s: Dictionary = r.get("series", {})
    if not s.is_empty():
        s.participants.erase(pid)
        s.ready.erase(pid)


## 클라이언트: 라운드 사이 레디
func round_ready(on: bool) -> void:
    if is_online():
        c_round_ready.rpc_id(1, on)


# ================================================================ 팀전 — 팀 바꾸기
## 대기 중에만. 자기 팀은 누구나, 다른 사람 팀은 방장만 바꿀 수 있다
@rpc("any_peer", "call_remote", "reliable")
func c_set_team(target: int, team: int) -> void:
    var id := _sender()
    if not is_server or id == 0:
        return
    var rid := int(_players[id].room)
    if rid == 0:
        return
    var r: Dictionary = _rooms[rid]
    if r.state != "waiting" or r.teams < 2 or team < 0 or team >= r.teams or not r.members.has(target):
        return
    if target != id and r.host != id:
        return
    r.team[target] = team
    _send_room(rid)


## 클라이언트: 팀 바꾸기 (target = 내 id 또는 방장이 바꿀 사람)
func set_team(target: int, team: int) -> void:
    if is_online():
        c_set_team.rpc_id(1, target, team)


# ================================================================ 신고·차단·제재 (3단계)
# RPC 번호가 기존 함수들과 섞이지 않도록 이름을 y_ 로 시작한다 (x_hello 뒤로 정렬)

## 클라이언트: 이 기기의 ID (처음 한 번 무작위로 만들어 저장). 서버의 제재 기준, 다른 사람에게는 해시만 보임
func device_id() -> String:
    if _device_id != "":
        return _device_id
    var cfg := ConfigFile.new()
    cfg.load(DEVICE_FILE)
    var v := String(cfg.get_value("device", "id", ""))
    if not v.is_valid_hex_number() or v.length() != 32:
        v = Crypto.new().generate_random_bytes(16).hex_encode()
        cfg.set_value("device", "id", v)
        cfg.save(DEVICE_FILE)
    _device_id = v
    return v


@rpc("any_peer", "call_remote", "reliable")
func y_device(dev: String) -> void:
    if not is_server:
        return
    var id := multiplayer.get_remote_sender_id()
    if dev.is_valid_hex_number() and dev.length() == 32 and not _players.has(id):
        _client_devices[id] = dev


## 클라이언트: 같은 방 사람 신고 (reason: REPORT_REASONS 키)
func report(target_pid: int, reason: String, detail: String) -> void:
    y_report.rpc_id(1, target_pid, reason, detail.strip_edges().left(200))


@rpc("any_peer", "call_remote", "reliable")
func y_report(target: int, reason: String, detail: String) -> void:
    var id := _sender()
    if not is_server or id == 0:
        return
    var rid := int(_players[id].room)
    if rid == 0 or not _rooms.has(rid) or not _rooms[rid].members.has(target) or target == id or not _players.has(target):
        s_chat.rpc_id(id, "", "신고할 수 없어요 (같은 방에 있는 사람만 신고할 수 있어요)", true)
        return
    var r: Dictionary = _rooms[rid]
    _report_queue.append({
        "reporter": {"nick": _players[id].nick, "device": String(_players[id].get("dev", "")), "account": String(_players[id].get("account", ""))},
        "target": {"nick": _players[target].nick, "device": String(_players[target].get("dev", "")), "account": String(_players[target].get("account", ""))},
        "room": String(r.name), "reason": reason if REPORT_REASONS.has(reason) else "other",
        "detail": detail.left(200), "chat": r.get("chat", []),
    })
    print("[server] 신고 %s → %s (%s)" % [_players[id].nick, _players[target].nick, reason])
    _send_next_report()
    s_chat.rpc_id(id, "", "%s 님 신고가 접수됐어요. 운영자가 확인할게요 (내용은 신고한 사람에게만 보여요)" % _players[target].nick, true)


func _send_next_report() -> void:
    var base := OS.get_environment("ADMIN_URL")
    if base == "" or _report_queue.is_empty():
        if base == "" and not _report_queue.is_empty():
            print("[server] ADMIN_URL 이 없어 신고를 보내지 못함: ", JSON.stringify(_report_queue.pop_front()).left(300))
        return
    if _report_http == null:
        _report_http = HTTPRequest.new()
        _report_http.timeout = 10.0
        add_child(_report_http)
        _report_http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray):
            if result == HTTPRequest.RESULT_SUCCESS and code == 200:
                _report_queue.pop_front()
            else:
                print("[server] 신고 전송 실패 (%d/%d) — 다음에 다시 보냄" % [result, code])
                return
            _send_next_report())
    if _report_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
        return
    _report_http.request(base.trim_suffix("/") + "/internal/reports", ["Content-Type: application/json"],
            HTTPClient.METHOD_POST, JSON.stringify(_report_queue[0]))


## 서버: 제재·금칙어 목록을 관리 서버에서 주기적으로 읽는다
func _start_moderation_poll(base: String) -> void:
    _mod_http = HTTPRequest.new()
    _mod_http.timeout = 5.0
    add_child(_mod_http)
    _mod_http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray):
        if result != HTTPRequest.RESULT_SUCCESS or code != 200:
            return
        var d = JSON.parse_string(body.get_string_from_utf8())
        if not d is Dictionary:
            return
        if d.get("words") is Array:
            WordFilter.set_extra(d.words)
        if d.get("sanctions") is Array:
            _sanctions = d.sanctions
            _enforce_bans()
        _send_next_report())          # 실패해서 남은 신고가 있으면 다시 보냄
    var timer := Timer.new()
    timer.wait_time = ADMIN_POLL_SEC
    timer.autostart = true
    add_child(timer)
    var poll := func():
        if _mod_http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
            _mod_http.request(base.trim_suffix("/") + "/internal/moderation")
    timer.timeout.connect(poll)
    poll.call()


## 지금 유효한 제재 (없으면 빈 딕셔너리)
func _sanction_for(dev: String, kind: String, account: String = "") -> Dictionary:
    if dev == "" and account == "":
        return {}
    var now := Time.get_datetime_string_from_system(true) + "Z"
    for x in _sanctions:
        var hit := (dev != "" and String(x.get("device", "")) == dev) or (account != "" and String(x.get("account", "")) == account)
        if hit and String(x.get("kind", "")) == kind:
            var until := String(x.get("until", ""))
            if until == "" or until > now:
                return x
    return {}


func _until_text(x: Dictionary) -> String:
    var until := String(x.get("until", ""))
    if until == "":
        return ""
    var t := Time.get_unix_time_from_datetime_string(until.trim_suffix("Z").left(19))
    var left_h := maxf((t - Time.get_unix_time_from_system()) / 3600.0, 0.0)
    return " (약 %d시간 남음)" % ceili(left_h) if left_h < 48.0 else " (약 %d일 남음)" % ceili(left_h / 24.0)


## 접속 차단이 새로 생기면 지금 접속 중인 사람도 내보낸다
func _enforce_bans() -> void:
    for pid in _players.keys():
        var ban := _sanction_for(String(_players[pid].get("dev", "")), "ban", String(_players[pid].get("account", "")))
        if ban.is_empty() or not _peer_alive(pid):
            continue
        print("[server] 접속 차단으로 내보냄 %s" % _players[pid].nick)
        s_error.rpc_id(pid, "이용이 제한되어 연결을 끊습니다%s" % _until_text(ban))
        var p: int = pid
        get_tree().create_timer(0.5).timeout.connect(func():
            if multiplayer.multiplayer_peer and _peer_alive(p):
                multiplayer.multiplayer_peer.disconnect_peer(p))


# ---- 클라이언트: 차단 (내 화면에서 그 사람 채팅 숨김). 이 기기에만 저장
const BLOCK_FILE := "user://settings.cfg"


func _load_blocked() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(BLOCK_FILE) == OK:
        var b = cfg.get_value("client", "blocked", {})
        if b is Dictionary:
            blocked = b


func set_blocked(uid: String, nick: String, on: bool) -> void:
    if uid == "":
        return
    if on:
        blocked[uid] = nick
    else:
        blocked.erase(uid)
    var cfg := ConfigFile.new()
    cfg.load(BLOCK_FILE)
    cfg.set_value("client", "blocked", blocked)
    cfg.save(BLOCK_FILE)


## 지금 방에서 이 닉네임의 사람이 차단돼 있나 (채팅 숨김 판단)
func is_blocked_nick(nick: String) -> bool:
    if blocked.is_empty():
        return false
    for m in room.get("members", []):
        if String(m.nick) == nick:
            return blocked.has(String(m.get("uid", "")))
    return false


# ================================================================ 계정 (소셜 로그인 토큰 확인)
## 관리 서버(ADMIN_URL)가 있는 실제 서버에서만 계정 로그인을 요구한다 (로컬 테스트 서버는 닉네임만)
func _accounts_required() -> bool:
    return is_server and OS.get_environment("ADMIN_URL") != ""


@rpc("any_peer", "call_remote", "reliable")
func y_auth(token: String) -> void:
    if not is_server:
        return
    var id := multiplayer.get_remote_sender_id()
    if _players.has(id) or not _accounts_required():
        return
    var acc := {}
    if token.length() >= 20 and token.length() <= 100:
        var res := await _admin_post("/internal/account/verify", {"token": token})
        if res.get("account") is Dictionary:
            acc = res.account
    if not multiplayer.get_peers().has(id):
        return
    _client_accounts[id] = acc
    if _pending_logins.has(id):
        var args: Array = _pending_logins[id]
        _pending_logins.erase(id)
        if acc.is_empty():
            s_login_result.rpc_id(id, false, "계정 로그인이 필요해요. 첫 화면에서 로그인해 주세요")
        else:
            _finish_login(id, String(args[0]).strip_edges())


## 관리 서버 /internal 호출 → 응답 JSON (실패하면 빈 딕셔너리)
func _admin_post(path: String, body: Dictionary) -> Dictionary:
    var base := OS.get_environment("ADMIN_URL")
    if base == "":
        return {}
    var http := HTTPRequest.new()
    http.timeout = 5.0
    add_child(http)
    var err := http.request(base.trim_suffix("/") + path, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
    if err != OK:
        http.queue_free()
        return {}
    var res: Array = await http.request_completed
    http.queue_free()
    if res[0] != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
        print("[server] 관리 서버 호출 실패 %s (%d/%d)" % [path, res[0], res[1]])
        return {}
    var d = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
    return d if d is Dictionary else {}

