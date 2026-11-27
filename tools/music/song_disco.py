"""곡: 반짝 디스코 (118 BPM, C장조, 약 1분 30초) — 옥타브 신스 베이스, 스트링, 뮤트 기타, 브라스, 오픈 하이햇
  python3 tools/music/song_disco.py [미리듣기.wav] → audio/drum/songs/disco/backing.ogg, song.gd
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L

CHORDS = {
    "Dm7": {"voicing": [53, 57, 60, 62], "root": 38},
    "G7": {"voicing": [53, 55, 59, 62], "root": 43},
    "Cmaj7": {"voicing": [52, 55, 59, 60], "root": 36},
    "Am7": {"voicing": [52, 55, 57, 60], "root": 45},
    "Fmaj7": {"voicing": [52, 53, 57, 60], "root": 41},
    "Em7": {"voicing": [50, 52, 55, 59], "root": 40},
}
PATTERNS = {
    "A": {"don": [0, 8], "ka": [4, 12]},
    "B": {"don": [0, 8, 14], "ka": [4, 12]},
    "C": {"don": [0, 6, 8], "ka": [4, 12]},
    "D": {"don": [0, 8], "ka": [4, 10, 12]},
    "d1": {"don": [0, 4, 8, 12], "ka": [6, 14]},
    "d2": {"don": [0, 4, 8, 12], "ka": [2, 6, 10, 14]},              # 둥딱둥딱
    "d3": {"don": [0, 8], "ka": [4, 12, 14]},
    "d4": {"don": [0, 4, 8], "ka": [12, 13, 14, 15]},
    "E": {"don": [0, 3, 8], "ka": [4, 12]},
    "F": {"don": [0, 8, 11], "ka": [4, 12]},
    "G": {"don": [0, 6, 8], "ka": [4, 7, 12]},
    "H": {"don": [0, 8, 10], "ka": [4, 12, 14]},
    "k1": {"don": [0, 4, 8, 12], "ka": [6, 14]},
    "k2": {"don": [0, 8], "ka": [4, 12], "hold": {8: 4}},            # 둥~ 피버
    "l1": {"don": [0, 4, 8, 12], "ka": [2, 6, 10, 14]},
    "l2": {"don": [0, 4, 8], "ka": [10, 12, 13, 14, 15]},            # 마지막 필인
}
RIFFS = {
    "i1": [(0, 2, 74), (2, 2, 77), (4, 4, 81), (10, 2, 79), (12, 4, 77)],
    "i2": [(0, 2, 74), (2, 2, 77), (4, 4, 79), (10, 2, 77), (12, 4, 74)],
    "i3": [(0, 4, 76), (4, 2, 79), (6, 2, 76), (8, 8, 72)],
    "i4": [(0, 2, 72), (2, 2, 74), (4, 4, 76), (8, 2, 79), (10, 6, 81)],
    "h1": [(2, 2, 72), (6, 2, 72), (8, 4, 76), (14, 2, 77)],
    "h2": [(0, 6, 76), (6, 2, 74), (8, 8, 71)],
    "h3": [(2, 2, 74), (6, 2, 74), (8, 4, 77), (14, 2, 76)],
    "h4": [(0, 6, 74), (6, 2, 72), (8, 8, 74)],
    "b1": [(0, 2, 81), (2, 2, 79), (4, 2, 77), (6, 2, 76), (8, 8, 74)],
    "b2": [(0, 2, 79), (2, 2, 77), (4, 2, 76), (6, 2, 74), (8, 8, 71)],
}

B = L.Bars({"intro": ["Dm7", "G7", "Cmaj7", "Am7"], "verse": ["Dm7", "G7", "Cmaj7", "Am7"],
            "chorus": ["Fmaj7", "Em7", "Dm7", "G7"], "break": ["Fmaj7", "G7"], "outro": ["Cmaj7"]})
B.section("intro").plain("intro", 4, leads=("i1", "i2", "i3", "i4"))
B.section("verse").echo(["A", "B", "C"], rest=True, rest_leads=("i3", "i4", "i3"))
B.echo(["D", "E"])
B.section("chorus").echo2([("d1", "d2"), ("d3", "d4")])
B.section("break").plain("break", 2, leads=("b1", "b2"))
B.section("verse").echo(["F", "G", "H", "E"])
B.section("chorus").echo2([("k1", "k2"), ("l1", "l2")])
B.section("outro").plain("outro", 1)
k = 0
for bar in B.bars:
    if bar["sec"] == "chorus":
        bar["lead"] = ("h1", "h2", "h3", "h4")[k % 4]
        k += 1

SONG = {
    "title": "반짝 디스코", "bpm": 118, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": B.bars,
    "reverb": 0.18,
    "programs": {0: (0, 38), 1: (0, 48), 2: (0, 28), 3: (0, 61), 9: (128, 0)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 100, "style": "eighths", "oct": True, "shift": -12 + 12},
        {"type": "chord", "ch": 1, "vel": 64, "shift": 12,
         "steps": {"chorus": [(0, 16, 62)], "break": [(0, 16, 66)], "default": [(2, 1.5, 64), (6, 1.5, 58), (10, 1.5, 64), (14, 1.5, 58)]}},
        {"type": "arp", "ch": 2, "vel": 62, "skip": ["break"], "order": [0, 2, 1, 3], "every": 2, "dur": 0.6, "shift": 12},
        {"type": "lead", "ch": 3, "vel": 90},
        {"type": "perc", "ch": 9, "key": 46, "outro_key": 49, "skip": ["break"], "steps": [(2, 56), (6, 52), (10, 56), (14, 52)]},
        {"type": "perc", "ch": 9, "key": 42, "skip": ["break"], "steps": [(0, 34), (4, 30), (8, 34), (12, 30)]},
        {"type": "perc", "ch": 9, "key": 54, "when": ["chorus"], "steps": [(s, 30 if s % 4 else 38) for s in range(0, 16, 2)]},
    ],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "disco", sys.argv)
