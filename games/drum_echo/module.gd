extends "res://scripts/core/game_module.gd"
## 뒷북의 달인 모듈 정보


func _init() -> void:
    id = "drum_echo"
    display_name = "뒷북의 달인"
    description = "공격팀이 북으로 낸 리듬을 다음 마디에 똑같이 따라 치기! 둥·딱 두 북으로 박자 대결"
    min_players = 2
    max_players = 12
    supports_bots = true
    supports_teams = true
    game_script_path = "res://games/drum_echo/drum_game.gd"
    thumbnail_path = "res://games/drum_echo/thumbnail.png"
    accent = Color(0.95, 0.70, 0.18)
