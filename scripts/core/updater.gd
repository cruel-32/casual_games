extends Node
## 업데이트 확인·받기 (자동 로드 Updater)
##
## 흐름: 시작하면 https://spw.cloudish.cloud/version.json 을 읽어 지금 버전과 비교 →
##   - PC 앱: 업데이트 팩(.pck)을 받아 sha256·서명을 확인하고 다음 실행 때 Boot 가 적용
##             (엔진이 바뀌었거나 pc_full_required 면 전체 zip 을 받도록 안내)
##   - Android/iOS: 스토어(출시 전에는 APK) 페이지를 연다 — 스토어 정책상 앱이 스스로 코드를 바꾸면 안 됨
##   - 웹: 새로고침
## version.json 은 CI 가 저장소의 release.json 으로 만든다 (tools/make_manifest.gd).

signal checked                          ## 확인 끝 (state 가 바뀜)
signal progress(ratio: float)           ## 받는 중 0~1
signal finished(ok: bool, message: String)

enum State { IDLE, CHECKING, UP_TO_DATE, AVAILABLE, DOWNLOADING, READY, FAILED }

const SITE := "https://spw.cloudish.cloud"
const MANIFEST_PATH := "/version.json"
const TIMEOUT := 10.0
## 업데이트 팩 서명 확인용 공개 키 (개인 키는 GitHub Secrets 의 PATCH_SIGNING_KEY)
const PUBLIC_KEY := """-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxY/FtlDkBohzW8QLv+HQ
MQq8JfsOp6snnvqyo24Z+zNo1lKvZc/m2R9N+V5khH+Dk2nZeNjsKKl1eMwl+du/
QgOfx3rLL9xdkA7Y/gF5ZTMq/1c/zHeW+8Q3BwgZzpgWDbQ7PYlKbX+QJBr+ygSn
hfzGakPgghj3RugU9+vYzYTtSH0Grtxt7O123Fw/haBxHUeRqtrJlY+hdbWN1L65
pAXQNKba2H1V3keVX0fdXWLddYnTepl0o+cwgYdjMtyXhFw7aQDxf5rS8+ZmViDB
r04YMvypdnpYrXWtkEpv+Q3fYzuhi9EONGZ2m7q6EAfkrDMbOgvuy2XJbruOnmCL
vQIDAQAB
-----END PUBLIC KEY-----"""

var state := State.IDLE
var manifest: Dictionary = {}
var latest := ""                ## 최신 버전 (확인 전 "")
var required := false           ## 지금 버전으로는 온라인 접속 불가 (min_supported 미만)
var message := ""               ## 실패 등 안내 문구
var public_key_pem := PUBLIC_KEY        ## 테스트에서 바꿔 끼울 수 있게
var site := OS.get_environment("SPW_SITE") if OS.get_environment("SPW_SITE") != "" else SITE   ## 개발용 SPW_SITE

var _http: HTTPRequest
var _dl: HTTPRequest
var _dl_file := ""


func _ready() -> void:
    if "--server" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
        return
    check()


func current_version() -> String:
    return Boot.version()


## version.json 다시 읽기
func check() -> void:
    if state == State.CHECKING or state == State.DOWNLOADING:
        return
    state = State.CHECKING
    if _http == null:
        _http = HTTPRequest.new()
        _http.timeout = TIMEOUT
        add_child(_http)
        _http.request_completed.connect(_on_manifest)
    # 캐시 회피 (CDN·브라우저가 예전 파일을 주지 않게)
    var err := _http.request("%s%s?t=%d" % [site, MANIFEST_PATH, Time.get_unix_time_from_system()])
    if err != OK:
        _fail("업데이트 정보를 받을 수 없어요")


func _on_manifest(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
    if result != HTTPRequest.RESULT_SUCCESS or code != 200:
        _fail("업데이트 정보를 받을 수 없어요")
        return
    var d = JSON.parse_string(body.get_string_from_utf8())
    if typeof(d) != TYPE_DICTIONARY:
        _fail("업데이트 정보가 올바르지 않아요")
        return
    apply_manifest(d)


## (테스트용으로도 씀) 받은 매니페스트로 상태 결정
func apply_manifest(d: Dictionary) -> void:
    manifest = d
    latest = String(d.get("version", ""))
    var cur := current_version()
    required = Boot.compare(cur, String(d.get("min_supported", "0"))) < 0
    if state == State.READY:
        checked.emit()
        return
    state = State.AVAILABLE if latest != "" and Boot.compare(latest, cur) > 0 else State.UP_TO_DATE
    checked.emit()


func has_update() -> bool:
    return state in [State.AVAILABLE, State.DOWNLOADING, State.READY, State.FAILED] and latest != "" \
        and Boot.compare(latest, current_version()) > 0


## 이 기기에서 업데이트하는 방법
##   "patch" PC 팩 받기 · "full" PC 전체 zip · "store" 스토어/APK 페이지 · "reload" 웹 새로고침 · "" 없음
func method() -> String:
    if OS.has_feature("web"):
        return "reload"
    if OS.has_feature("android") or OS.has_feature("ios"):
        return "store" if _store_url() != "" else ""
    var pc: Dictionary = manifest.get("pc", {})
    if Boot.can_patch() and pc.get("pck", "") != "" and pc.get("sig", "") != "" \
            and not bool(pc.get("full_required", false)) \
            and String(manifest.get("engine", "")) == Boot.engine_version() \
            and (String(pc.get("settings_sig", "")) == "" or String(pc.get("settings_sig", "")) == Boot.settings_sig()):
        return "patch"
    return "full" if pc.get("full", "") != "" else ""


## 업데이트 버튼에 쓸 글자
func button_text() -> String:
    match state:
        State.DOWNLOADING:
            return "받는 중…"
        State.READY:
            return "다시 시작해서 적용"
    match method():
        "patch":
            return "업데이트"
        "full":
            return "새 버전 받기"
        "store":
            return "스토어에서 업데이트" if OS.has_feature("ios") or String(manifest.get("android", {}).get("store", "")) != "" else "새 버전(APK) 받기"
        "reload":
            return "새로고침"
    return "업데이트"


## 패치 노트 (문장 목록)
func notes() -> PackedStringArray:
    var out := PackedStringArray()
    for n in manifest.get("notes", []):
        out.append(String(n))
    return out


## 업데이트 버튼을 누름
func start() -> void:
    match state:
        State.DOWNLOADING:
            return
        State.READY:
            restart()
            return
    match method():
        "patch":
            _download_patch()
        "full":
            OS.shell_open(_abs(String(manifest.get("pc", {}).get("full", ""))))
        "store":
            OS.shell_open(_store_url())
        "reload":
            if OS.has_feature("web"):
                JavaScriptBridge.eval("location.reload()")


## 받아 둔 업데이트 팩을 적용하려고 게임을 다시 켠다
func restart() -> void:
    OS.set_restart_on_exit(true, OS.get_cmdline_args())
    get_tree().quit()


func _store_url() -> String:
    if OS.has_feature("ios"):
        return _abs(String(manifest.get("ios", {}).get("store", "")))
    var a: Dictionary = manifest.get("android", {})
    var url := String(a.get("store", ""))
    if url == "":
        url = String(a.get("apk", ""))
    return _abs(url)


func _abs(url: String) -> String:
    if url == "" or url.begins_with("http"):
        return url
    return site + url


# ---- PC 업데이트 팩 받기
func _download_patch() -> void:
    var pc: Dictionary = manifest.get("pc", {})
    DirAccess.make_dir_recursive_absolute(Boot.UPDATE_DIR)
    _dl_file = Boot.UPDATE_DIR + "game-%s.pck" % latest
    if _dl == null:
        _dl = HTTPRequest.new()
        _dl.timeout = 300.0
        _dl.use_threads = true
        add_child(_dl)
        _dl.request_completed.connect(_on_patch_downloaded)
    _dl.download_file = _dl_file + ".part"
    state = State.DOWNLOADING
    checked.emit()
    if _dl.request(_abs(String(pc.get("pck", "")))) != OK:
        _fail("업데이트를 받을 수 없어요")


func _process(_delta: float) -> void:
    if state == State.DOWNLOADING and _dl:
        var total := _dl.get_body_size()
        if total > 0:
            progress.emit(clampf(float(_dl.get_downloaded_bytes()) / total, 0.0, 1.0))


func _on_patch_downloaded(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
    var part := _dl_file + ".part"
    if result != HTTPRequest.RESULT_SUCCESS or code != 200:
        DirAccess.remove_absolute(part)
        _fail("업데이트를 받는 중 문제가 생겼어요 (다시 눌러 주세요)")
        return
    var err := install_patch(part, manifest.get("pc", {}), latest)
    if err != "":
        _fail(err)
        return
    state = State.READY
    progress.emit(1.0)
    checked.emit()
    finished.emit(true, "업데이트를 받았어요. 다시 시작하면 적용돼요")


## 받은 파일을 확인(sha256·서명)하고 다음 실행 때 쓰도록 등록. 문제가 있으면 안내 문구, 없으면 ""
func install_patch(part: String, pc: Dictionary, version: String) -> String:
    var digest := file_sha256(part)
    if digest.is_empty() or digest.hex_encode() != String(pc.get("sha256", "")).to_lower():
        DirAccess.remove_absolute(part)
        return "받은 파일이 손상됐어요 (다시 눌러 주세요)"
    if not verify_signature(digest, String(pc.get("sig", ""))):
        DirAccess.remove_absolute(part)
        return "업데이트 파일의 서명이 올바르지 않아요"
    var final := part.trim_suffix(".part")
    DirAccess.remove_absolute(final)
    if DirAccess.rename_absolute(part, final) != OK:
        return "업데이트 파일을 저장할 수 없어요"
    var f := FileAccess.open(Boot.CURRENT_FILE, FileAccess.WRITE)
    if f == null:
        return "업데이트 정보를 저장할 수 없어요"
    f.store_string(JSON.stringify({"version": version, "file": final.get_file(), "engine": Boot.engine_version(),
            "settings_sig": String(pc.get("settings_sig", ""))}))
    f.close()
    DirAccess.remove_absolute(Boot.TRY_FILE)      # 새 팩: 지난 '시작 시도' 표시는 의미 없음
    _cleanup_old(final.get_file())
    return ""


func verify_signature(digest: PackedByteArray, sig_b64: String) -> bool:
    if sig_b64 == "":
        return false
    var key := CryptoKey.new()
    if key.load_from_string(public_key_pem, true) != OK:
        return false
    return Crypto.new().verify(HashingContext.HASH_SHA256, digest, Marshalls.base64_to_raw(sig_b64), key)


static func file_sha256(path: String) -> PackedByteArray:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        return PackedByteArray()
    var ctx := HashingContext.new()
    ctx.start(HashingContext.HASH_SHA256)
    while not f.eof_reached():
        ctx.update(f.get_buffer(1 << 20))
    return ctx.finish()


## 지금 쓰는 것 말고 예전 업데이트 팩은 지운다
func _cleanup_old(keep: String) -> void:
    for f in DirAccess.get_files_at(Boot.UPDATE_DIR):
        if f.ends_with(".pck") and f != keep and f != Boot.patch_file:
            DirAccess.remove_absolute(Boot.UPDATE_DIR + f)


func _fail(msg: String) -> void:
    message = msg
    if state == State.CHECKING:
        state = State.IDLE      # 확인 실패는 조용히 (오프라인 등)
        checked.emit()
        return
    state = State.FAILED
    checked.emit()
    finished.emit(false, msg)
