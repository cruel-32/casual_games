"""곡: 네온 하우스 (124 BPM, A단조, ★★★) — 엇박 신스 베이스, 피아노 하우스 코드(엇박), 패드, 오픈 하이햇"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L
from song_lib import P

CHORDS = {
    "Am7": {"voicing": [57, 60, 64, 67], "root": 45},
    "Fmaj7": {"voicing": [57, 60, 64, 65], "root": 41},
    "C": {"voicing": [55, 60, 64, 67], "root": 48},
    "G": {"voicing": [55, 59, 62, 67], "root": 43},
    "Em7": {"voicing": [55, 59, 62, 64], "root": 40},
}
PATTERNS = {
    "A": P("D...D...D...D..."),             # 포온더플로어
    "B": P("D...K...D...K..."),
    "C": P("D...D.K.D...D.K."),             # 엇박 딱
    "D": P("D...K...D.D.K..."),
    "c1": P("D.K.D.K.D.K.D.K."),            # 둥딱둥딱
    "c2": P("D...K..DD...K..."),
    "c3": P("D.K.D.K.D...K.K."),
    "f": P("D...K...H=======") ,
}
RIFFS = {
    "i1": [(0, 2, 76), (3, 2, 76), (6, 2, 74), (8, 4, 72), (12, 2, 69), (14, 2, 72)],
    "i2": [(0, 2, 72), (3, 2, 72), (6, 2, 71), (8, 8, 67)],
    "m1": [(0, 3, 81), (3, 3, 79), (6, 2, 76), (8, 6, 76), (14, 2, 79)],
    "m2": [(0, 3, 77), (3, 3, 76), (6, 2, 72), (8, 8, 76)],
    "m3": [(0, 3, 79), (3, 3, 76), (6, 2, 74), (8, 6, 72), (14, 2, 74)],
    "m4": [(0, 3, 74), (3, 3, 72), (6, 2, 71), (8, 8, 71)],
}
BARS = L.compose({"intro": ["Am7", "Fmaj7", "C", "G"], "verse": ["Am7", "Fmaj7", "C", "G"], "chorus": ["Fmaj7", "G", "Em7", "Am7"],
                  "break": ["Fmaj7", "G"], "outro": ["Am7"]}, [
    ("intro", 4, {"lead": ["i1", "i2", "i1", "i2"]}),
    ("verse", ["A", "A", "B", "A", "A", "B", "C", "D"]),
    ("chorus", ["c2", "C", "c2", "D", "c1", "c2", "c1", "c3"], {"lead": ["m1", "m2", "m3", "m4"]}),
    ("break", 2, {"lead": ["i1", "i2"]}),
    ("verse", ["B", "C", "B", "D", "C", "C", "D", "D"], {"lead": [None, None, "i1", "i2"]}),
    ("chorus", ["c2", "C", "c2", "D", "c1", "c2", "c3", "f"], {"lead": ["m1", "m2", "m3", "m4"]}),
    ("outro", 1),
])
SONG = {
    "title": "네온 하우스", "bpm": 124, "level": 3, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": BARS,
    "reverb": 0.18, "mix": {0: 104, 1: 88, 2: 72, 3: 127, 9: 120},
    "programs": {0: (0, 39), 1: (0, 0), 2: (0, 89), 3: (0, 81), 9: (128, 0)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 100, "style": "steps", "shift": -12,
         "steps": [(2, 1.5, 0, 0), (6, 1.5, 0, -4), (10, 1.5, 0, 0), (14, 1.5, 12, -10)]},
        {"type": "chord", "ch": 1, "vel": 82, "skip": ["intro"], "steps": [(0, 1, 84), (3, 1, 74), (6, 1, 80), (10, 1, 74), (12, 2, 80)]},
        {"type": "pad", "ch": 2, "vel": 62, "steps": [(0, 16, 62)]},
        {"type": "lead", "ch": 3, "vel": 82},
        {"type": "perc", "ch": 9, "key": 46, "outro_key": 49, "skip": ["break"], "steps": [(2, 52), (6, 48), (10, 52), (14, 48)]},
        {"type": "perc", "ch": 9, "key": 42, "steps": [(s, 30 if s % 2 else 22) for s in range(16) if s % 4 != 2]},
    ],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "house", sys.argv)
