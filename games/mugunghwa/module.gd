extends "res://scripts/core/game_module.gd"
## 무궁화 꽃이 피었습니다 모듈 정보


func _init() -> void:
    id = "mugunghwa"
    display_name = "무궁화 꽃이 피었습니다"
    description = "술래가 외치는 동안만 달리고, 돌아보면 얼음! 움직이면 탈락, 결승선을 먼저 넘으면 승리"
    min_players = 2
    max_players = 12
    supports_bots = true
    supports_teams = true
    game_script_path = "res://games/mugunghwa/mugunghwa_game.gd"
    thumbnail_path = "res://games/mugunghwa/thumbnail.png"
    accent = Color(0.30, 0.75, 0.45)
    arena_half = 30.0              # 긴 운동장 (출발선 → 결승선 44m)
