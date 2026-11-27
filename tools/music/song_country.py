"""곡: 카우보이 질주 (160 BPM, G장조, ★★★★) — 밴조 16분 굴리기, 쿵짝 베이스(근음·5도), 피들 가락, 통기타 엇박"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L
from song_lib import P

CHORDS = {
    "G": {"voicing": [55, 59, 62, 67], "root": 43},
    "C": {"voicing": [55, 60, 64, 67], "root": 48},
    "D": {"voicing": [54, 57, 62, 66], "root": 38},
    "Em": {"voicing": [55, 59, 64, 67], "root": 40},
}
PATTERNS = {
    "A": P("D...K...D...K..."),
    "B": P("D...K...D.D.K..."),
    "C": P("D...K.K.D...K..."),
    "D": P("D.D.K...D.D.K..."),
    "c1": P("D...K.K.D.D.K.K."),
    "c2": P("D.K.D.K.D...K..."),
    "c3": P("D.D.K.K.D...K.K."),
    "x": P("D.K.D.K.D.K.K.K."),
    "f": P("D...K...H=======") ,
}
RIFFS = {
    "i1": [(0, 2, 74), (2, 2, 76), (4, 2, 79), (6, 2, 76), (8, 2, 74), (10, 2, 71), (12, 4, 67)],
    "i2": [(0, 2, 72), (2, 2, 74), (4, 2, 76), (6, 2, 79), (8, 8, 81)],
    "i3": [(0, 2, 78), (2, 2, 79), (4, 4, 81), (8, 2, 79), (10, 2, 78), (12, 4, 74)],
    "i4": [(0, 4, 79), (4, 4, 74), (8, 8, 71)],
    "m1": [(0, 4, 83), (4, 2, 81), (6, 2, 79), (8, 8, 79)],
    "m2": [(0, 4, 84), (4, 2, 83), (6, 2, 81), (8, 8, 79)],
    "m3": [(0, 4, 81), (4, 2, 79), (6, 2, 78), (8, 4, 76), (12, 4, 78)],
    "m4": [(0, 12, 79), (12, 4, 74)],
}
BARS = L.compose({"intro": ["G", "C", "D", "G"], "verse": ["G", "G", "C", "G", "G", "G", "D", "D"], "chorus": ["C", "G", "D", "G"],
                  "break": ["Em", "C", "D", "D"], "outro": ["G"]}, [
    ("intro", 4, {"lead": ["i1", "i2", "i3", "i4"]}),
    ("verse", ["A", "A", "B", "A", "A", "C", "B", "D", "A", "B", "C", "D"], {"lead": [None, None, "i1", None, None, None, "i3", "i4"]}),
    ("chorus", ["c1", "c2", "c1", "x", "c1", "c2", "c3", "x"], {"lead": ["m1", "m2", "m3", "m4"]}),
    ("break", 4, {"lead": ["i1", "i2", "i3", "i4"]}),
    ("verse", ["B", "C", "D", "B", "C", "D", "c2", "x"], {"lead": [None, "i2", None, "i4"]}),
    ("chorus", ["c1", "c2", "c1", "x", "c1", "c3", "c2", "x", "c1", "c2", "c3", "f"], {"lead": ["m1", "m2", "m3", "m4"]}),
    ("outro", 1, {"lead": ["i4"]}),
])
SONG = {
    "title": "카우보이 질주", "bpm": 160, "level": 4, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": BARS,
    "reverb": 0.14, "mix": {0: 92, 1: 100, 2: 124, 3: 100, 9: 127},
    "programs": {0: (0, 32), 1: (0, 105), 2: (0, 25), 3: (0, 110), 9: (128, 0)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 104, "style": "steps",
         "steps": [(0, 3, 0, 0), (4, 3, 7, -10), (8, 3, 0, -2), (12, 3, 7, -10)]},
        {"type": "arp", "ch": 1, "vel": 64, "order": [0, 2, 3, 1, 3, 2], "every": 1, "dur": 0.8, "shift": 12},
        {"type": "chord", "ch": 2, "vel": 70, "steps": [(4, 2, 72), (12, 2, 72), (14, 1, 56)]},
        {"type": "lead", "ch": 3, "vel": 96},
        {"type": "perc", "ch": 9, "key": 42, "outro_key": 49, "steps": [(s * 2, 44 if s % 2 else 34) for s in range(8)]},
    ],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "country", sys.argv)
