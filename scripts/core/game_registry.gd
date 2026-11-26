extends RefCounted
## 게임 모듈 목록. 새 게임은 MODULES 에 한 줄 추가 (맨 위가 기본 게임)

const MODULES := [
    preload("res://games/rock_dodge/module.gd"),
]

static var _cache: Array = []


static func all() -> Array:
    if _cache.is_empty():
        for script in MODULES:
            _cache.append(script.new())
    return _cache


static func find(id: String):
    for m in all():
        if m.id == id:
            return m
    return null


## 없는 ID면 기본 게임
static func get_or_default(id: String):
    var m = find(id)
    return m if m != null else all()[0]


static func default_id() -> String:
    return all()[0].id


static func display_name(id: String) -> String:
    if id == "random":
        return "랜덤"
    var m = find(id)
    return m.display_name if m != null else id
