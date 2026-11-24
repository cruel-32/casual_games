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

## 서버·클라이언트 통신 규약 버전. 메시지 형식이 바뀌면 올린다 → 다르면 로그인 단계에서 안내
const PROTOCOL_VERSION := 3
const LOGIN_TIMEOUT := 6.0
const DEFAULT_PORT := 7777
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

var is_server := false
var server_name := ""                   # 현재 접속한 서버의 표시 이름

# ---- 클라이언트 상태
var my_id := 0
var nickname := ""
var rooms: Array = []
var room: Dictionary = {}               # 현재 방 스냅샷 (없으면 빈 딕셔너리)
var match_config: Dictionary = {}       # 게임 시작 시 받은 방 정보 (게임 씬에서 사용)
var chat_log: Array = []                # 현재 방 채팅 기록 [{nick, text, system}]
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
var _rooms := {}                        # room_id -> {id, name, host, max, bot_fill, state, members[], ready{}, returned{}}
var _next_room_id := 1
var _nick_regex := RegEx.new()
var _status_server: TCPServer
var _status_clients: Array = []         # [{peer: StreamPeerTCP, buf: String, t: float}]
var _started_at := 0.0
var _matches := {}                      # room_id -> {vp: SubViewport, game: Node}


func _ready() -> void:
    _nick_regex.compile("^[가-힣A-Za-z0-9_\\-\\.]+$")
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
        if start_server(port) == OK:
            _start_status_server(status_port)


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
    var module = GameRegistry.get_or_default(String(r.get("game", "")))
    var bots_ok: bool = r.get("bot_fill", false) and module.supports_bots
    if members.size() < module.min_players and not bots_ok:
        return "최소 %d명이 필요합니다%s" % [module.min_players, " (또는 봇 채우기)" if module.supports_bots else ""]
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
        })
    return {
        "id": r.id, "name": r.name, "host": r.host, "max": r.max, "game": r.game,
        "bot_fill": r.bot_fill, "state": r.state, "members": members,
    }


func _public_rooms() -> Array:
    var out := []
    for rid in _rooms:
        var r: Dictionary = _rooms[rid]
        out.append({
            "id": rid, "name": r.name, "host_nick": _players[r.host].nick, "game": r.game,
            "count": r.members.size(), "max": r.max, "state": r.state, "bot_fill": r.bot_fill,
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
        _send_room(rid)
    _broadcast_room_list()


func _check_all_returned(rid: int) -> void:
    var r: Dictionary = _rooms[rid]
    if r.state != "playing":
        return
    for pid in r.members:
        if not r.returned.get(pid, false):
            return
    r.state = "waiting"
    r.ready.clear()
    r.returned.clear()
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
    nick = nick.strip_edges()
    var err := _validate_nick(nick)
    if err != "":
        s_login_result.rpc_id(id, false, err)
        return
    _players[id] = {"nick": nick, "room": 0}
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
    if int(_players[id].room) != 0:
        s_error.rpc_id(id, "이미 방에 있습니다")
        return
    room_name = room_name.strip_edges().left(ROOM_NAME_MAX)
    if room_name == "":
        room_name = "%s의 방" % _players[id].nick
    var module = GameRegistry.get_or_default(game_id)
    var rid := _next_room_id
    _next_room_id += 1
    _rooms[rid] = {
        "id": rid, "name": room_name, "host": id, "game": module.id,
        "max": clampi(max_players, 2, mini(MAX_PLAYERS_LIMIT, module.max_players)), "bot_fill": bot_fill,
        "state": "waiting", "members": [id], "ready": {}, "returned": {},
    }
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
        var n := String(settings.name).strip_edges().left(ROOM_NAME_MAX)
        if n != "":
            r.name = n
    if settings.has("game"):
        var m = GameRegistry.find(String(settings.game))
        if m != null and m.id != r.game:
            r.game = m.id
            _room_system_chat(rid, "게임이 '%s'(으)로 바뀌었습니다" % m.display_name)
            if r.max > m.max_players:
                r.max = maxi(m.max_players, r.members.size())
            if not m.supports_bots:
                r.bot_fill = false
            r.ready.clear()     # 게임이 바뀌면 다시 레디
    var game_max: int = GameRegistry.get_or_default(r.game).max_players
    if settings.has("max"):
        var want := int(settings.max)
        r.max = clampi(want, maxi(2, r.members.size()), mini(MAX_PLAYERS_LIMIT, game_max))
        if r.max != want:
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
    for pid in _rooms[rid].members:
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
    r.state = "playing"
    r.returned.clear()
    var snap := _room_snapshot(rid)
    print("[server] 게임 시작 #%d (%d명)" % [rid, r.members.size()])
    for pid in r.members:
        s_game_start.rpc_id(pid, snap)
    _create_match(rid, snap)
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
    _check_all_returned(rid)
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
