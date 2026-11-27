"""곡: 아프로 축제 (108 BPM, D단조, ★★★★) — 아프로비트: 하이라이프 기타 16분 가락, 엇박 베이스, 브라스, 오르간, 벨"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L
from song_lib import P

CHORDS = {
    "Dm7": {"voicing": [53, 57, 60, 62], "root": 38},
    "Gm7": {"voicing": [55, 58, 62, 65], "root": 43},
    "Bbmaj7": {"voicing": [53, 57, 58, 62], "root": 46},
    "Am7": {"voicing": [55, 60, 64, 67], "root": 45},
    "C": {"voicing": [55, 60, 64, 67], "root": 48},
}
PATTERNS = {
    "a1": P("D.....D...D.K..."),
    "a2": P("D..K..D...D.K..."),
    "a3": P("D.....D.K.D...K."),
    "a4": P("D..K..D.K.D.K..."),
    "c1": P("D..K..D.K.D..KD."),
    "c2": P("D.K...DK..D.K.K."),
    "c3": P("D..K.DD...D.K.K."),
    "f": P("D..K..D.H=====K."),
}
RIFFS = {
    "h1": [(0, 2, 74), (3, 2, 77), (6, 2, 74), (8, 2, 72), (10, 2, 69), (12, 4, 72)],
    "h2": [(0, 2, 70), (3, 2, 74), (6, 2, 70), (8, 2, 69), (10, 2, 67), (12, 4, 69)],
    "m1": [(0, 3, 81), (3, 3, 79), (6, 2, 77), (8, 3, 74), (11, 3, 77), (14, 2, 79)],
    "m2": [(0, 6, 81), (6, 2, 79), (8, 8, 77)],
    "m3": [(0, 3, 77), (3, 3, 76), (6, 2, 74), (8, 3, 72), (11, 3, 74), (14, 2, 76)],
    "m4": [(0, 8, 74), (10, 2, 72), (12, 4, 74)],
}
BARS = L.compose({"intro": ["Dm7", "Gm7"], "verse": ["Dm7", "Dm7", "Gm7", "Gm7"], "chorus": ["Bbmaj7", "C", "Am7", "Dm7"],
                  "break": ["Gm7", "Am7"], "outro": ["Dm7"]}, [
    ("intro", 2, {"lead": ["h1", "h2"]}),
    ("verse", ["a1", "a1", "a2", "a1", "a1", "a3", "a2", "a4"], {"lead": ["h1", None, "h2", None]}),
    ("chorus", ["c1", "c2", "c1", "c3", "c1", "c2", "a4", "c3"], {"lead": ["m1", "m2", "m3", "m4"]}),
    ("break", 2, {"lead": ["h1", "h2"]}),
    ("verse", ["a2", "a3", "a2", "a4", "a3", "a4", "a2", "a4"], {"lead": ["h1", None, "h2", None]}),
    ("chorus", ["c1", "c2", "c1", "c3", "c2", "c3", "a4", "f"], {"lead": ["m1", "m2", "m3", "m4"]}),
    ("outro", 1, {"lead": ["m4"]}),
])
SONG = {
    "title": "아프로 축제", "bpm": 108, "level": 4, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": BARS,
    "reverb": 0.16, "mix": {0: 86, 1: 104, 2: 104, 3: 96, 9: 110},
    "programs": {0: (0, 33), 1: (0, 27), 2: (0, 16), 3: (0, 61), 9: (128, 0)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 104, "style": "steps",
         "steps": [(0, 2, 0, 0), (3, 1, 12, -14), (6, 2, 0, -6), (10, 2, 7, -8), (13, 1, 10, -12), (14, 2, 12, -10)]},
        {"type": "arp", "ch": 1, "vel": 70, "order": [3, 1, 2, 0, 2, 1, 3, 2], "every": 1, "dur": 0.6, "shift": 12, "skip": ["break"]},
        {"type": "chord", "ch": 2, "vel": 60, "steps": [(0, 6, 60), (8, 6, 56)]},
        {"type": "lead", "ch": 3, "vel": 94},
        {"type": "perc", "ch": 9, "key": 56, "outro_key": 49, "steps": [(0, 46), (3, 36), (6, 40), (10, 36), (12, 40)]},   # 벨 패턴
        {"type": "perc", "ch": 9, "key": 70, "steps": [(s, 32 if s % 2 == 0 else 22) for s in range(16)]},
    ],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "afro", sys.argv)
