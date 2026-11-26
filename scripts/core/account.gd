extends Node
## 계정 (자동 로드 "Account") — 온라인 대전은 구글·Apple 로그인이 필요하다. 혼자 연습은 로그인 없이.
##   Account.is_logged_in()            로그인했나 (이 기기에 토큰이 있나)
##   Account.start_login("google")     브라우저로 로그인 화면을 열고, 끝날 때까지 기다린다 → changed / login_failed
##   Account.refresh()                 계정·오늘 판수 다시 읽기 → changed
##   Account.logout() / delete_account()
## 이 기기에는 로그인 토큰만 저장한다 (user://account.cfg). 이메일·이름은 받지 않는다.
## 정책(하루 판수, 광고 보상, 베타 여부)은 관리 서버가 정하고 info.plays 로 알려 준다.

signal changed                      ## 로그인·로그아웃·판수 정보가 바뀜
signal providers_loaded(list: Array)
signal login_failed(message: String)
signal login_waiting(provider: String)

const FILE := "user://account.cfg"
const POLL_SEC := 1.5
const POLL_MAX_SEC := 600.0

var token := ""
var info: Dictionary = {}           ## {id, provider, provider_name, ad_free, plays:{phase, unlimited, limit, used, left, ...}}
var providers: Array = []           ## [{id, name}] 켜진 로그인
var _login_id := ""
var _poll_started := 0.0


func _ready() -> void:
    if _is_server():
        return
    var cfg := ConfigFile.new()
    if cfg.load(FILE) == OK:
        token = String(cfg.get_value("account", "token", ""))
    load_providers()
    if token != "":
        refresh()


func _is_server() -> bool:
    return "--server" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless" and OS.get_environment("SPW_ACCOUNT_TEST") == ""


func site() -> String:
    return Updater.site


func is_logged_in() -> bool:
    return token != ""


func is_waiting() -> bool:
    return _login_id != ""


## 오늘 남은 판수 (-1 = 무제한, 정보 없음도 -1)
func plays_left() -> int:
    var p: Dictionary = info.get("plays", {})
    if p.is_empty() or bool(p.get("unlimited", true)):
        return -1
    return int(p.get("left", -1))


func plays_text() -> String:
    var p: Dictionary = info.get("plays", {})
    if p.is_empty():
        return ""
    if String(p.get("phase", "")) != "live":
        return "베타 기간 · 판수 제한 없음"
    if bool(info.get("ad_free", false)):
        return "광고 제거 · 판수 제한 없음"
    return "오늘 남은 판 %d / %d" % [int(p.get("left", 0)), int(p.get("limit", 0))]


# ---------------------------------------------------------------- 요청
## HTTP 요청 하나 → {code, data} (실패하면 code = 0)
func _request(method: int, path: String, body: Variant = null) -> Dictionary:
    var http := HTTPRequest.new()
    http.timeout = 10.0
    add_child(http)
    var headers := PackedStringArray(["Content-Type: application/json"])
    if token != "":
        headers.append("Authorization: Bearer " + token)
    var err := http.request(site() + path, headers, method, "" if body == null else JSON.stringify(body))
    if err != OK:
        http.queue_free()
        return {"code": 0, "data": {}}
    var res: Array = await http.request_completed
    http.queue_free()
    var data = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8()) if res[0] == HTTPRequest.RESULT_SUCCESS else null
    return {"code": int(res[1]) if res[0] == HTTPRequest.RESULT_SUCCESS else 0, "data": data if data is Dictionary else {}}


func load_providers() -> void:
    var r := await _request(HTTPClient.METHOD_GET, "/api/auth/providers")
    providers = r.data.get("providers", []) if r.code == 200 else []
    providers_loaded.emit(providers)


func refresh() -> void:
    if token == "":
        return
    var r := await _request(HTTPClient.METHOD_GET, "/api/account")
    if r.code == 200:
        info = r.data.get("account", {})
        changed.emit()
    elif r.code == 401:
        _set_token("")          # 만료·삭제된 로그인


# ---------------------------------------------------------------- 로그인
func start_login(provider: String) -> void:
    var r := await _request(HTTPClient.METHOD_POST, "/api/auth/start", {"provider": provider})
    if r.code != 200:
        login_failed.emit(String(r.data.get("error", "로그인 서버에 연결할 수 없어요")))
        return
    _login_id = String(r.data.id)
    _poll_started = Time.get_ticks_msec() / 1000.0
    OS.shell_open(String(r.data.url))
    login_waiting.emit(provider)
    _poll(_login_id)


func cancel_login() -> void:
    _login_id = ""


func _poll(id: String) -> void:
    while _login_id == id:
        await get_tree().create_timer(POLL_SEC).timeout
        if _login_id != id:
            return
        if Time.get_ticks_msec() / 1000.0 - _poll_started > POLL_MAX_SEC:
            _login_id = ""
            login_failed.emit("로그인 시간이 지났어요. 다시 시도해 주세요")
            return
        var r := await _request(HTTPClient.METHOD_GET, "/api/auth/poll?id=" + id.uri_encode())
        if _login_id != id or r.code != 200:
            continue
        match String(r.data.get("status", "")):
            "done":
                _login_id = ""
                info = r.data.get("account", {}) if r.data.get("account") is Dictionary else {}
                _set_token(String(r.data.get("token", "")))
                return
            "error":
                _login_id = ""
                login_failed.emit(String(r.data.get("error", "로그인하지 못했어요")))
                return
            "expired":
                _login_id = ""
                login_failed.emit("로그인 시간이 지났어요. 다시 시도해 주세요")
                return


func logout() -> void:
    if token != "":
        _request(HTTPClient.METHOD_POST, "/api/auth/logout", {})
    _set_token("")


## 계정 삭제 (판수 기록·로그인 정보 삭제). 성공하면 true
func delete_account() -> bool:
    var r := await _request(HTTPClient.METHOD_DELETE, "/api/account")
    if r.code == 200 or r.code == 401:
        _set_token("")
        return true
    return false


func _set_token(t: String) -> void:
    token = t
    if t == "":
        info = {}
    var cfg := ConfigFile.new()
    cfg.load(FILE)
    cfg.set_value("account", "token", t)
    cfg.save(FILE)
    changed.emit()
