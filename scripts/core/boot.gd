extends Node
## 가장 먼저 실행되는 자동 로드 (project.godot 의 autoload 맨 위).
## PC 앱에서 받아 둔 업데이트 팩(.pck)을 다른 스크립트·장면보다 먼저 적용한다.
## - 이 파일 자체는 업데이트 팩으로 바뀌지 않는다(이미 실행 중) → 최소한으로 유지
## - 업데이트 팩을 받는 일은 Updater(scripts/core/updater.gd) 가 한다
##
## 버전 정보는 저장소 맨 위의 release.json 한 곳에서 관리한다.

const UPDATE_DIR := "user://updates/"
const CURRENT_FILE := "user://updates/current.json"

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
    var path := UPDATE_DIR + String(info.get("file", "")).get_file()
    if not FileAccess.file_exists(path) or not ProjectSettings.load_resource_pack(path):
        patch_note = "업데이트 팩을 열 수 없음"
        _forget()
        return
    patch_version = v
    patch_file = path.get_file()
    print("[boot] 업데이트 팩 적용 %s (설치본 %s)" % [v, base_version])


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
