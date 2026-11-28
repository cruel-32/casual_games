extends "res://scripts/core/game_module.gd"
## 크레이지 봄버맨 모듈 정보


func _init() -> void:
    id = "bomber"
    display_name = "크레이지 봄버맨"
    description = "블록 탑 위에서 폭탄을 던져요! 터질수록 바닥이 깎여 구멍이 뚫리고 아래는 용암. 맞거나 떨어지면 탈락, 탈락하면 유령이 되어 밖에서 던지기"
    min_players = 2
    max_players = 12
    supports_bots = true
    supports_teams = true
    game_script_path = "res://games/bomber/bomber_game.gd"
    thumbnail_path = "res://games/bomber/thumbnail.png"
    accent = Color(0.95, 0.42, 0.2)
    arena_half = 26.0              # 격자 최대 21×15칸 (칸 2m) + 바깥 유령 길
