extends SceneTree
## 개발용: 서버 없이 로비·대기실 화면을 가짜 데이터로 띄워 캡처 (/tmp/ft/ui_lobby.png, ui_room.png)
##   xvfb-run godot --rendering-method gl_compatibility --resolution 1280x720 --path . -s tools/preview_ui.gd
var t := 0.0
var step := 0
var app
var net
func _initialize():
	net = root.get_node("Net")
	net.my_id = 100
	net.nickname = "철수"
	net.server_name = "서버 1"
	net.rooms = [
		{"id": 1, "name": "영희네 놀이터", "host_nick": "영희", "game": "rock_dodge", "count": 3, "max": 8, "state": "lobby", "bot_fill": true},
		{"id": 2, "name": "고수만 오세요", "host_nick": "민준", "game": "rock_dodge", "count": 6, "max": 6, "state": "playing", "bot_fill": false},
		{"id": 3, "name": "초보 환영", "host_nick": "하은", "game": "rock_dodge", "count": 1, "max": 4, "state": "lobby", "bot_fill": true},
	]
	app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
func _cap(name):
	root.get_texture().get_image().save_png("/tmp/ft/ui_%s.png" % name)
	print("cap ", name)
func _process(d):
	t += d
	match step:
		0:
			if t > 0.5:
				app.show_screen("lobby"); net.room_list_updated.emit(net.rooms); step = 1
		1:
			if t > 1.5:
				_cap("lobby")
				net.room = {"id": 1, "name": "영희네 놀이터", "host": 200, "max": 8, "game": "rock_dodge", "bot_fill": true, "state": "lobby",
					"members": [{"id": 200, "nick": "영희", "ready": true, "host": true}, {"id": 100, "nick": "철수", "ready": false, "host": false}, {"id": 300, "nick": "민준", "ready": true, "host": false}]}
				net.chat_log = [{"nick": "", "text": "철수 님이 들어왔습니다", "system": true}, {"nick": "영희", "text": "안녕! 같이 하자", "system": false}]
				app.show_screen("room"); net.room_updated.emit(net.room); step = 2
		2:
			if t > 2.8:
				_cap("room"); quit()
	return false
