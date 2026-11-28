extends Node
## 경기 화면에서 "불러오는 중" 표시를 이어받아, 화면이 준비되고 서버의 시작 신호가 오면 닫는다 (PartyGame.add_common_ui 가 붙임)
##   클라이언트: 화면 준비 중 → "게임 불러오는 중…", 준비 끝(loaded 보냄) → "다른 플레이어를 기다리는 중…", 시작 신호 → 닫음
##   혼자 연습: 몇 프레임 그려지면 닫음

const LoadingOverlay := preload("res://scripts/ui/loading_overlay.gd")

var game: Node
var _frames := 0


func _process(_delta: float) -> void:
    _frames += 1
    var tree := get_tree()
    if game == null or not game.is_client():
        if _frames > 3:
            LoadingOverlay.close(tree)
            queue_free()
        return
    if _started():
        LoadingOverlay.close(tree)
        queue_free()
        return
    LoadingOverlay.open(tree, "다른 플레이어를 기다리는 중…" if bool(game.get("loaded_sent")) else "게임 불러오는 중…")


## 서버의 시작 신호를 받았나 (게임마다 시작 시각 변수 이름이 다름)
func _started() -> bool:
    for key in ["play_start_t", "t0"]:
        var v = game.get(key)
        if v != null:
            return float(v) > 0.0
    return int(game.get("state")) != 0
