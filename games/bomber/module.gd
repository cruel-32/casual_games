extends "res://scripts/core/game_module.gd"
## 연쇄폭탄마 모듈 정보


func _init() -> void:
    id = "bomber"
    display_name = "연쇄폭탄마"
    description = "격자 미로에 폭탄을 놓아 상자를 부수고 상대를 날려요! 폭탄끼리 연쇄 폭발, 탈락하면 유령이 되어 밖에서 폭탄 던지기"
    min_players = 2
    max_players = 12
    supports_bots = true
    supports_teams = true
    game_script_path = "res://games/bomber/bomber_game.gd"
    thumbnail_path = "res://games/bomber/thumbnail.png"
    accent = Color(0.95, 0.42, 0.2)
    arena_half = 26.0              # 격자 최대 21×15칸 (칸 2m) + 바깥 유령 길
