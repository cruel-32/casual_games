extends "res://scripts/core/game_module.gd"
## 뒷북의 달인 모듈 정보


func _init() -> void:
    id = "drum_echo"
    display_name = "뒷북의 달인"
    description = "가면 쓴 진행자와 함께 곡에 맞춰 둥·딱! 노트가 동그라미에 닿을 때 치는 리듬 대결 (18곡, 난이도 1~5)"
    min_players = 2
    max_players = 12
    supports_bots = true
    supports_teams = true
    game_script_path = "res://games/drum_echo/drum_game.gd"
    thumbnail_path = "res://games/drum_echo/thumbnail.png"
    accent = Color(0.95, 0.70, 0.18)
