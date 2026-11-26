extends RefCounted
## 금칙어 필터 (서버에서 닉네임·방 이름·채팅에 적용)
##   mask(text)    금칙어를 ***로 가린 문자열
##   contains(text) 금칙어가 들어 있으면 true (닉네임 거절용)
## 띄어쓰기·숫자·기호를 끼워 넣어도("시 1발", "f.u.c.k") 걸러낸다.
## 단, 두 글자 단어는 띄어쓰기를 건너뛰지 않는다 ("개 새로운"이 "개새"로 걸리지 않게).
## 관리 페이지에서 더한 단어는 set_extra() 로 받는다 (서버가 15초마다 읽음).

## 기본 목록 — 소문자, 공백 없이. 너무 흔한 말과 겹치지 않게 골랐다 (예: '새끼'는 '새끼손가락' 때문에 '개새끼'만)
const BASE_WORDS: PackedStringArray = [
    # 한국어 욕설·비하
    "시발", "씨발", "씨빨", "시빨", "씨바", "씨팔", "시팔", "ㅅㅂ", "ㅆㅂ", "ㅅ발", "ㅆ발", "씹",
    "병신", "븅신", "빙신", "ㅂㅅ", "좆", "존나", "졸라", "ㅈㄴ", "개새끼", "개새기", "개색기", "개색히", "개세끼", "개새",
    "니미", "느금", "느개비", "니애미", "니어미", "엠창", "애미", "애비", "지랄", "ㅈㄹ", "썅", "미친놈", "미친년", "미친새끼",
    "꺼져", "닥쳐", "등신", "또라이", "찐따", "쓰레기새끼", "년아", "놈아",
    # 성적 표현
    "섹스", "보지", "자지", "꼬추", "야동", "딸딸이", "자위",
    # 혐오·차별
    "한남충", "한녀", "김치녀", "된장녀", "틀딱", "급식충", "맘충", "짱깨", "쪽바리", "흑형", "장애새끼",
    # 영어
    "fuck", "fuk", "fck", "shit", "bitch", "asshole", "bastard", "cunt", "dick", "pussy", "slut", "whore",
    "nigger", "nigga", "faggot", "retard", "motherfucker", "wtf",
]

static var _extra: PackedStringArray = []


static func set_extra(words: Array) -> void:
    var out := PackedStringArray()
    for w in words:
        var s := String(w).to_lower().replace(" ", "")
        if s.length() >= 2:
            out.append(s)
    _extra = out


static func words() -> PackedStringArray:
    var all := BASE_WORDS.duplicate()
    all.append_array(_extra)
    return all


## 비교용 글자인지 (한글·한글 자모·영문). 숫자·기호·공백은 건너뛴다
static func _is_letter(c: String) -> bool:
    var u := c.unicode_at(0)
    return (u >= 0xAC00 and u <= 0xD7A3) or (u >= 0x3131 and u <= 0x318E) \
            or (u >= 0x61 and u <= 0x7A) or (u >= 0x41 and u <= 0x5A)


## 비교용 문자열과, 각 글자가 원문 몇 번째 글자였는지
##   keep_space: 공백을 남김 (두 글자 단어용)
static func _normalize(text: String, keep_space: bool) -> Array:
    var norm := ""
    var idx := PackedInt32Array()
    var low := text.to_lower()
    for i in low.length():
        var c := low[i]
        if _is_letter(c) or (keep_space and c == " "):
            norm += c
            idx.append(i)
    return [norm, idx]


## 가릴 글자 위치들 (원문 기준)
static func _hits(text: String) -> PackedInt32Array:
    var out := PackedInt32Array()
    var tight: Array = _normalize(text, false)
    var spaced: Array = _normalize(text, true)
    for w in words():
        var src: Array = tight if w.length() >= 3 else spaced
        var norm: String = src[0]
        var idx: PackedInt32Array = src[1]
        var from := 0
        while true:
            var at := norm.find(w, from)
            if at < 0:
                break
            for k in w.length():
                out.append(idx[at + k])
            from = at + 1
    return out


static func contains(text: String) -> bool:
    return not _hits(text).is_empty()


static func mask(text: String) -> String:
    var hits := _hits(text)
    if hits.is_empty():
        return text
    var chars := text.split("")
    if chars.size() != text.length():
        chars = PackedStringArray()
        for i in text.length():
            chars.append(text[i])
    for i in hits:
        if i < chars.size():
            chars[i] = "*"
    return "".join(chars)
