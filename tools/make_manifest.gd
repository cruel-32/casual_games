extends SceneTree
## version.json (업데이트 정보) 만들기 — CI(deploy/web-build/build.sh)에서 실행
##   godot --headless --path . -s tools/make_manifest.gd -- \
##       --pck <PC 업데이트 팩> --pck-url /download/updates/game-0.2.0.pck \
##       --key <서명 개인 키 PEM, 없으면 서명 생략> --links deploy/web-landing/links.json --out <version.json>
## 서명이 없으면 PC 앱은 업데이트 팩 대신 전체 zip 을 받도록 안내한다.


func _initialize() -> void:
    var a := _args()
    var release = JSON.parse_string(FileAccess.get_file_as_string("res://release.json"))
    if typeof(release) != TYPE_DICTIONARY:
        _die("release.json 을 읽을 수 없음")
        return
    var links = {}
    if a.has("links") and FileAccess.file_exists(a.links):
        links = JSON.parse_string(FileAccess.get_file_as_string(a.links))
    var e := Engine.get_version_info()
    var pc := {
        "pck": "",
        "sha256": "",
        "sig": "",
        "full": String(links.get("windows", "/download/SmallPartyWorld-windows.zip")),
        "full_required": bool(release.get("pc_full_required", false)),
    }
    if a.has("pck") and FileAccess.file_exists(a.pck):
        var digest := _sha256(a.pck)
        pc.sha256 = digest.hex_encode()
        var pem := ""
        if a.has("key") and FileAccess.file_exists(a.key):
            pem = FileAccess.get_file_as_string(a.key)
        if pem.strip_edges() != "":
            var key := CryptoKey.new()
            if key.load_from_string(pem) != OK:
                _die("서명 키를 읽을 수 없음")
                return
            pc.sig = Marshalls.raw_to_base64(Crypto.new().sign(HashingContext.HASH_SHA256, digest, key))
            pc.pck = String(a.get("pck-url", ""))
        else:
            print("[manifest] 서명 키 없음 → PC 업데이트 팩 생략 (전체 zip 안내)")
    var out := {
        "version": String(release.get("version", "0.0.0")),
        "min_supported": String(release.get("min_supported", "0.0.0")),
        "engine": "%d.%d.%d" % [e.major, e.minor, e.patch],
        "notes": release.get("notes", []),
        "published": Time.get_datetime_string_from_system(true) + "Z",
        "pc": pc,
        "android": {"store": String(links.get("android", "")), "apk": String(links.get("android_apk", ""))},
        "ios": {"store": String(links.get("ios", ""))},
    }
    var f := FileAccess.open(String(a.get("out", "version.json")), FileAccess.WRITE)
    if f == null:
        _die("출력 파일을 쓸 수 없음")
        return
    f.store_string(JSON.stringify(out, "  "))
    f.close()
    print("[manifest] %s 버전 %s (PC 팩: %s)" % [a.get("out", "version.json"), out.version, "있음" if pc.pck != "" else "없음"])
    quit(0)


func _args() -> Dictionary:
    var d := {}
    var args := OS.get_cmdline_user_args()
    var i := 0
    while i < args.size():
        if args[i].begins_with("--") and i + 1 < args.size():
            d[args[i].substr(2)] = args[i + 1]
            i += 2
        else:
            i += 1
    return d


func _sha256(path: String) -> PackedByteArray:
    var f := FileAccess.open(path, FileAccess.READ)
    var ctx := HashingContext.new()
    ctx.start(HashingContext.HASH_SHA256)
    while not f.eof_reached():
        ctx.update(f.get_buffer(1 << 20))
    return ctx.finish()


func _die(msg: String) -> void:
    printerr("[manifest] " + msg)
    quit(1)
