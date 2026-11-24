extends Node
## 온라인 로비/방 네트워크 (오토로드: /root/Net)
## - 같은 스크립트가 서버와 클라이언트 양쪽에서 실행된다 (WebSocket + RPC, 서버 권위)
## - 서버는 평문 ws:// 로 열고, 외부에서는 리버스 프록시(Caddy)가 wss:// (HTTPS 443) 를 받아 전달한다
## - 실행 인자 `-- --server [--port 7777]` 이면 전용 서버로 시작
## - 클라이언트 → 서버: c_* RPC / 서버 → 클라이언트: s_* RPC

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

const DEFAULT_PORT := 7777
const DEFAULT_SERVER := "wss://spw.cloudish.cloud"
const MAX_PLAYERS_LIMIT := 12
const MIN_PLAYERS_TO_START := 2       # 봇 채우기가 꺼져 있을 때 필요한 최소 인원
const NICK_MIN := 2
const NICK_MAX := 12
const ROOM_NAME_MAX := 20
const CHAT_MAX := 120
const CONNECT_TIMEOUT := 6.0

var is_server := false

# ---- 클라이언트 상태
var my_id := 0
var nickname := ""
var rooms: Array = []
var room: Dictionary = {}               # 현재 방 스냅샷 (없으면 빈 딕셔너리)
var match_config: Dictionary = {}       # 게임 시작 시 받은 방 정보 (게임 씬에서 사용)
var chat_log: Array = []                # 현재 방 채팅 기록 [{nick, text, system}]
var _connect_timer: SceneTreeTimer
var _connecting := false

# ---- 서버 상태
var _players := {}                      # peer_id -> {nick, room}
var _rooms := {}                        # room_id -> {id, name, host, max, bot_fill, state, members[], ready{}, returned{}}
var _next_room_id := 1
var _nick_regex := RegEx.new()


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
        start_server(port)


# ================================================================ 공통
func is_online() -> bool:
    var p := multiplayer.multiplayer_peer
    return p != null and not (p is OfflineMultiplayerPeer) \
            and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


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
    if members.size() < MIN_PLAYERS_TO_START and not r.get("bot_fill", false):
        return "최소 %d명이 필요합니다 (또는 봇 채우기)" % MIN_PLAYERS_TO_START
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
        "id": r.id, "name": r.name, "host": r.host, "max": r.max,
        "bot_fill": r.bot_fill, "state": r.state, "members": members,
    }


func _public_rooms() -> Array:
    var out := []
    for rid in _rooms:
        var r: Dictionary = _rooms[rid]
        out.append({
            "id": rid, "name": r.name, "host_nick": _players[r.host].nick,
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
    if r.members.is_empty():
        _rooms.erase(rid)
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
    _room_system_chat(rid, "모두 돌아왔습니다. 다시 레디해 주세요")


# ---- 클라이언트 → 서버 요청
@rpc("any_peer", "call_remote", "reliable")
func c_login(nick: String) -> void:
    if not is_server:
        return
    var id := multiplayer.get_remote_sender_id()
    if _players.has(id):
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
func c_create_room(room_name: String, max_players: int, bot_fill: bool) -> void:
    var id := _sender()
    if not is_server or id == 0:
        return
    if int(_players[id].room) != 0:
        s_error.rpc_id(id, "이미 방에 있습니다")
        return
    room_name = room_name.strip_edges().left(ROOM_NAME_MAX)
    if room_name == "":
        room_name = "%s의 방" % _players[id].nick
    var rid := _next_room_id
    _next_room_id += 1
    _rooms[rid] = {
        "id": rid, "name": room_name, "host": id,
        "max": clampi(max_players, 2, MAX_PLAYERS_LIMIT), "bot_fill": bot_fill,
        "state": "waiting", "members": [id], "ready": {}, "returned": {},
    }
    _players[id].room = rid
    print("[server] 방 생성 #%d '%s' by %s" % [rid, room_name, _players[id].nick])
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
    if settings.has("max"):
        var want := int(settings.max)
        r.max = clampi(want, maxi(2, r.members.size()), MAX_PLAYERS_LIMIT)
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
    game_started.emit(snap)


# ================================================================ 클라이언트 API
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


func connect_to_server(url: String) -> void:
    _reset_client()
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
    c_login.rpc_id(1, nick)


func request_rooms() -> void:
    c_request_rooms.rpc_id(1)


func create_room(room_name: String, max_players: int, bot_fill: bool) -> void:
    c_create_room.rpc_id(1, room_name, max_players, bot_fill)


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
