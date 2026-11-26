extends Node
## 가장 먼저 실행되는 자동 로드 (project.godot 의 autoload 맨 위).
## PC 앱에서 받아 둔 업데이트 팩(.pck)을 다른 스크립트·장면보다 먼저 적용한다.
## - 이 파일 자체는 업데이트 팩으로 바뀌지 않는다(이미 실행 중) → 최소한으로 유지
## - 업데이트 팩을 받는 일은 Updater(scripts/core/updater.gd) 가 한다
##
## 버전 정보는 저장소 맨 위의 release.json 한 곳에서 관리한다.

const UPDATE_DIR := "user://updates/"
const CURRENT_FILE := "user://updates/current.json"
## 업데이트 팩을 적용해 시작했다는 표시. 정상으로 몇 초 버티면 지움 → 남아 있으면 지난번에 팩 때문에 죽은 것
const TRY_FILE := "user://updates/boot_try.txt"
const HEALTHY_AFTER := 8.0

var base_version := ""      ## 설치한 앱(실행 파일과 함께 온 팩)에 들어 있는 버전
var patch_version := ""     ## 적용한 업데이트 팩의 버전 ("" = 없음)
var patch_file := ""        ## 적용한 업데이트 팩 파일 이름 (사용 중이라 지우면 안 됨)
var patch_note := ""        ## 업데이트 팩을 건너뛴 이유 (디버그용)


func _init() -> void:
    base_version = read_release().get("version", "0.0.0")
    if not can_patch():
        return
    var info = _read_json(CURRENT_FILE)
    if typeof(info) != TYPE_DICTIONARY:
        return
    var v := String(info.get("version", ""))
    if String(info.get("engine", "")) != engine_version():
        patch_note = "엔진 버전이 달라 업데이트 팩을 쓰지 않음"
        _forget()
        return
    if compare(v, base_version) <= 0:
        patch_note = "설치본이 업데이트 팩보다 새것"
        _forget()
        return
    # 업데이트 팩으로 바꿀 수 없는 설정(자동 로드·입력)이 다르면 팩을 쓰지 않는다 (전체 설치 필요)
    var need_sig := String(info.get("settings_sig", ""))
    if need_sig != "" and need_sig != settings_sig():
        patch_note = "설정이 바뀐 업데이트라 전체 설치가 필요함"
        _forget()
        return
    # 지난번에 이 팩으로 시작했다가 정상 확인 전에 꺼졌으면(강제 종료) 팩을 버린다
    if FileAccess.file_exists(TRY_FILE) and FileAccess.get_file_as_string(TRY_FILE).strip_edges() == v:
        patch_note = "지난번 실행이 비정상 종료되어 업데이트 팩을 쓰지 않음"
        push_warning("[boot] " + patch_note)
        _forget()
        DirAccess.remove_absolute(TRY_FILE)
        return
    var path := UPDATE_DIR + String(info.get("file", "")).get_file()
    if not FileAccess.file_exists(path) or not ProjectSettings.load_resource_pack(path):
        patch_note = "업데이트 팩을 열 수 없음"
        _forget()
        return
    patch_version = v
    patch_file = path.get_file()
    var tf := FileAccess.open(TRY_FILE, FileAccess.WRITE)
    if tf:
        tf.store_string(v)
        tf.close()
    print("[boot] 업데이트 팩 적용 %s (설치본 %s)" % [v, base_version])


func _ready() -> void:
    if patch_version != "":
        _check_patch_health.call_deferred()


## 팩을 적용한 뒤: 자동 로드가 모두 떴는지 확인. 하나라도 없으면(팩의 코드가 설치본 설정과 안 맞음) 팩을 버리고 다시 시작
## 문제없이 HEALTHY_AFTER 초를 버티면 '시작 시도' 표시를 지운다
func _check_patch_health() -> void:
    for prop in ProjectSettings.get_property_list():
        var name := String(prop.name)
        if not name.begins_with("autoload/"):
            continue
        var node_name := name.trim_prefix("autoload/")
        if get_tree().root.get_node_or_null(node_name) == null:
            push_warning("[boot] 업데이트 팩과 설치본이 맞지 않음 (%s 없음) → 설치본으로 다시 시작" % node_name)
            _forget()
            DirAccess.remove_absolute(TRY_FILE)
            OS.set_restart_on_exit(true, OS.get_cmdline_args())
            get_tree().quit()
            return
    get_tree().create_timer(HEALTHY_AFTER).timeout.connect(func(): DirAccess.remove_absolute(TRY_FILE))


## 업데이트 팩으로 바꿀 수 없는 설정의 지문: 자동 로드(이름·경로)와 입력 동작 이름
## 설치본(지금 실행 중인 앱)과 새 버전(version.json 의 pc.settings_sig)이 다르면 팩 대신 전체 설치
static func settings_sig() -> String:
    var lines := PackedStringArray()
    for prop in ProjectSettings.get_property_list():
        var name := String(prop.name)
        if name.begins_with("autoload/"):
            lines.append("%s=%s" % [name, str(ProjectSettings.get_setting(name))])
        elif name.begins_with("input/"):
            lines.append(name)
    lines.sort()
    return "\n".join(lines).sha256_text().substr(0, 16)


## 지금 실행 중인 게임 버전 (업데이트 팩이 있으면 그 버전)
func version() -> String:
    return patch_version if patch_version != "" else base_version


## 업데이트 팩을 받아 적용할 수 있는 환경: 내보낸 PC 앱 (에디터·웹·모바일·서버 제외)
static func can_patch() -> bool:
    if "--server" in OS.get_cmdline_user_args() or OS.has_feature("web"):
        return false
    # SPW_PATCH_TEST=1: 에디터 바이너리로 업데이트 흐름을 시험할 때만
    return OS.has_feature("pc") and (OS.has_feature("template") or OS.get_environment("SPW_PATCH_TEST") == "1")


static func engine_version() -> String:
    var e := Engine.get_version_info()
    return "%d.%d.%d" % [e.major, e.minor, e.patch]


static func read_release() -> Dictionary:
    var d = _read_json("res://release.json")
    return d if typeof(d) == TYPE_DICTIONARY else {}


## 버전 비교 "1.2.10" vs "1.2.9" → 1 / 0 / -1
static func compare(a: String, b: String) -> int:
    var pa := a.split(".")
    var pb := b.split(".")
    for i in maxi(pa.size(), pb.size()):
        var x := int(pa[i]) if i < pa.size() else 0
        var y := int(pb[i]) if i < pb.size() else 0
        if x != y:
            return 1 if x > y else -1
    return 0


static func _read_json(path: String) -> Variant:
    if not FileAccess.file_exists(path):
        return null
    return JSON.parse_string(FileAccess.get_file_as_string(path))


func _forget() -> void:
    DirAccess.remove_absolute(CURRENT_FILE)
