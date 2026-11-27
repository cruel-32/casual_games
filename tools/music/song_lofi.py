"""곡: 느긋한 오후 (80 BPM, F장조, 쉬움 ★) — 로파이: 로즈 피아노, 콘트라베이스, 플루트, 살짝 끄는 엇박 킥"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L
from song_lib import P

CHORDS = {
    "Fmaj7": {"voicing": [53, 57, 60, 64], "root": 41},
    "Em7": {"voicing": [52, 55, 59, 62], "root": 40},
    "Dm7": {"voicing": [50, 53, 57, 60], "root": 38},
    "Cmaj7": {"voicing": [52, 55, 59, 60], "root": 36},
    "Bbmaj7": {"voicing": [50, 53, 57, 58], "root": 34},
}
PATTERNS = {
    "A": P("D.......K......."),
    "B": P("D.....D.K......."),       # 엇박 킥
    "C": P("D.......K.....D."),
    "c1": P("D.......K...D..."),
    "c2": P("D.....D.K......."),
    "f": P("H=======K......."),       # 둥~ 피버 (2박)
}
RIFFS = {
    "i1": [(0, 4, 72), (6, 2, 69), (8, 8, 67)],
    "i2": [(2, 2, 65), (4, 4, 67), (8, 6, 64)],
    "i3": [(0, 6, 69), (6, 2, 67), (8, 4, 65), (12, 4, 62)],
    "i4": [(0, 12, 64), (14, 2, 67)],
    "m1": [(0, 3, 76), (3, 3, 74), (6, 2, 72), (8, 8, 69)],
    "m2": [(2, 2, 71), (4, 4, 72), (8, 8, 74)],
    "m3": [(0, 3, 72), (3, 3, 69), (6, 2, 67), (8, 8, 65)],
    "m4": [(0, 10, 67), (10, 2, 69), (12, 4, 72)],
}
PROG = ["Fmaj7", "Em7", "Dm7", "Cmaj7"]
BARS = L.compose({"intro": PROG, "verse": PROG, "chorus": ["Bbmaj7", "Cmaj7", "Fmaj7", "Dm7"], "break": ["Bbmaj7", "Cmaj7"], "outro": ["Fmaj7"]}, [
    ("intro", 2, {"lead": ["i1", "i2"]}),
    ("verse", ["A", "A", "B", "A", "A", "A", "C", "B"], {"lead": [None, None, None, "i4"]}),
    ("chorus", ["c1", "c2", "c1", "c2"], {"lead": ["m1", "m2", "m3", "m4"]}),
    ("break", 2, {"lead": ["i3", "i4"]}),
    ("verse", ["B", "A", "C", "A"]),
    ("chorus", ["c1", "c2", "c1", "f"], {"lead": ["m1", "m2", "m3", "m4"]}),
    ("outro", 1, {"lead": ["i1"]}),
])
SONG = {
    "title": "느긋한 오후", "bpm": 80, "level": 1, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": BARS,
    "reverb": 0.24, "mix": {0: 96, 1: 120, 3: 92, 9: 127},
    "programs": {0: (0, 32), 1: (0, 4), 3: (0, 73), 9: (128, 0)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 104, "style": "boom"},
        {"type": "chord", "ch": 1, "vel": 80, "shift": 12, "steps": [(0, 6, 82), (7, 1, 60), (10, 5, 72)]},
        {"type": "lead", "ch": 3, "vel": 88},
        {"type": "perc", "ch": 9, "key": 42, "outro_key": 49, "steps": [(0, 62), (2, 44), (4, 56), (6, 44), (7, 30), (8, 62), (10, 44), (12, 56), (14, 48)]},
    ],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "lofi", sys.argv)
