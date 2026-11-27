"""곡: 번개 드럼앤베이스 (172 BPM, F단조, ★★★★★) — 굵은 신스 베이스, 공간감 패드, 사각파 아르페지오, 투스텝 북(엇박 둥)"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L
from song_lib import P

CHORDS = {
    "Fm": {"voicing": [56, 60, 65], "root": 41},
    "Db": {"voicing": [56, 61, 65], "root": 37},
    "Ab": {"voicing": [56, 60, 63], "root": 44},
    "Eb": {"voicing": [55, 58, 63], "root": 39},
    "Bbm": {"voicing": [53, 58, 61], "root": 46},
}
PATTERNS = {
    "A": P("D...K.....D.K..."),           # 투스텝
    "B": P("D...K..D..D.K..."),
    "C": P("D.D.K.....D.K..."),
    "D": P("D...K.K...D.K.K."),
    "c1": P("D...K..D..D.K.K."),
    "c2": P("D.D.K..D..D.K..."),
    "c3": P("D...K.K.D.D.K.K."),
    "x": P("D.K.D.K.D.K.K.K."),
    "f": P("D...K...H=====K."),
}
RIFFS = {
    "p1": [(0, 6, 77), (6, 2, 75), (8, 8, 72)],
    "p2": [(0, 6, 73), (6, 2, 72), (8, 8, 68)],
    "m1": [(0, 3, 80), (3, 3, 77), (6, 2, 75), (8, 6, 77), (14, 2, 80)],
    "m2": [(0, 3, 77), (3, 3, 73), (6, 2, 72), (8, 8, 73)],
    "m3": [(0, 3, 75), (3, 3, 72), (6, 2, 70), (8, 6, 72), (14, 2, 75)],
    "m4": [(0, 6, 72), (6, 2, 70), (8, 8, 68)],
}
PROG = ["Fm", "Db", "Ab", "Eb"]
BARS = L.compose({"intro": PROG, "verse": PROG, "chorus": ["Db", "Eb", "Fm", "Fm", "Db", "Eb", "Bbm", "Eb"], "break": ["Db", "Eb", "Fm", "Eb"], "outro": ["Fm"]}, [
    ("intro", 4, {"lead": ["p1", "p2", "p1", "p2"]}),
    ("verse", ["A", "A", "B", "A", "A", "C", "B", "D", "A", "B", "C", "D"]),
    ("chorus", ["c1", "c2", "c1", "c3", "c1", "c2", "c3", "x"], {"lead": ["m1", "m2", "m3", "m4"]}),
    ("break", 4, {"lead": ["p1", "p2", "p1", "p2"]}),
    ("verse", ["B", "C", "B", "D", "B", "C", "D", "D"]),
    ("chorus", ["c1", "c2", "c1", "c3", "c1", "c2", "c3", "x", "c1", "c2", "c3", "f"], {"lead": ["m1", "m2", "m3", "m4"]}),
    ("outro", 1, {"lead": ["p1"]}),
])
SONG = {
    "title": "번개 드럼앤베이스", "bpm": 172, "level": 5, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": BARS,
    "reverb": 0.2, "mix": {0: 86, 1: 76, 2: 112, 3: 127, 9: 112},
    "programs": {0: (0, 39), 1: (0, 89), 2: (0, 80), 3: (0, 81), 9: (128, 0)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 104, "style": "steps", "shift": -12,
         "steps": {"break": [(0, 16, 0, 0)], "default": [(0, 6, 0, 0), (7, 3, 0, -8), (10, 6, 12, -10)]}},
        {"type": "pad", "ch": 1, "vel": 64, "shift": 12, "steps": [(0, 16, 64)]},
        {"type": "arp", "ch": 2, "vel": 48, "order": [0, 1, 2, 1], "every": 1, "dur": 0.7, "shift": 12, "skip": ["intro", "break"]},
        {"type": "lead", "ch": 3, "vel": 86},
        {"type": "perc", "ch": 9, "key": 42, "outro_key": 49, "skip": ["intro"], "steps": [(s * 2, 44 if s % 2 else 32) for s in range(8)]},
        {"type": "perc", "ch": 9, "key": 51, "when": ["chorus"], "steps": [(0, 40), (4, 36), (8, 40), (12, 36)]},
    ],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "dnb", sys.argv)
