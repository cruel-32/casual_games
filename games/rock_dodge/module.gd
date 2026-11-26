extends "res://scripts/core/game_module.gd"
## 3D 돌피하기 모듈 정보


func _init() -> void:
    id = "rock_dodge"
    display_name = "3D 돌피하기"
    description = "하늘에서 떨어지는 돌을 피하고, 상대를 밀쳐 마지막까지 살아남기"
    min_players = 2
    max_players = 12
    supports_bots = true
    supports_teams = true
    game_script_path = "res://games/rock_dodge/rock_dodge_game.gd"
    thumbnail_path = "res://games/rock_dodge/thumbnail.png"     # tools/render_thumbnail.gd 로 생성
    accent = Color(0.96, 0.42, 0.30)
