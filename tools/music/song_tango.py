"""곡: 열정 탱고 (116 BPM, D단조, ★★★) — 반도네온(아코디언) 끊어 치기, 하바네라 베이스, 바이올린, 피아노"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L
from song_lib import P

CHORDS = {
    "Dm": {"voicing": [57, 62, 65, 69], "root": 38},
    "A7": {"voicing": [57, 61, 64, 67], "root": 45},
    "Gm": {"voicing": [55, 58, 62, 67], "root": 43},
    "Bb": {"voicing": [58, 62, 65, 70], "root": 46},
    "E7": {"voicing": [56, 59, 62, 64], "root": 40},
}
PATTERNS = {
    "A": P("D.....D.D...K..."),          # 하바네라
    "B": P("D..K..D.D...K..."),
    "C": P("D.....D.D..KK..."),
    "D": P("D...K...D...K..."),
    "c1": P("D..K..D.D..K..K."),
    "c2": P("D.....D.D.K.K.K."),
    "c3": P("K..K..K.D...D..."),
    "f": P("D.....D.H======="),
}
RIFFS = {
    "v1": [(0, 6, 74), (6, 2, 73), (8, 4, 74), (12, 4, 77)],
    "v2": [(0, 6, 76), (6, 2, 74), (8, 6, 73), (14, 2, 69)],
    "v3": [(0, 2, 81), (2, 2, 79), (4, 2, 77), (6, 2, 76), (8, 8, 74)],
    "v4": [(0, 3, 70), (3, 3, 69), (6, 2, 67), (8, 8, 69)],
    "v5": [(0, 12, 74), (12, 4, 69)],
}
BARS = L.compose({"intro": ["Dm", "A7"], "verse": ["Dm", "Dm", "A7", "A7", "Gm", "Dm", "E7", "A7"], "chorus": ["Bb", "A7", "Dm", "Dm", "Gm", "A7", "Dm", "A7"],
                  "break": ["Gm", "A7"], "outro": ["Dm"]}, [
    ("intro", 2, {"lead": ["v1", "v2"]}),
    ("verse", ["A", "A", "B", "A", "D", "A", "C", "B"], {"lead": ["v1", None, "v2", None, "v4", None, "v2", None]}),
    ("chorus", ["c1", "A", "c2", "B", "c1", "C", "c3", "c2"], {"lead": ["v3", "v2", "v1", "v5", "v4", "v2", "v1", "v2"]}),
    ("break", 2, {"lead": ["v4", "v2"]}),
    ("verse", ["B", "C", "B", "A", "D", "B", "C", "c3"], {"lead": ["v1", None, "v2", None, "v4", None, "v2", None]}),
    ("chorus", ["c1", "A", "c2", "B", "c1", "C", "c3", "f"], {"lead": ["v3", "v2", "v1", "v5", "v4", "v2", "v1", "v2"]}),
    ("outro", 1, {"lead": ["v5"]}),
])
SONG = {
    "title": "열정 탱고", "bpm": 116, "level": 3, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": BARS,
    "reverb": 0.2, "mix": {0: 100, 1: 127, 2: 119, 3: 112},
    "programs": {0: (0, 32), 1: (0, 23), 2: (0, 0), 3: (0, 40)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 104, "style": "steps", "steps": [(0, 3, 0, 0), (6, 2, 7, -8), (8, 3, 7, -2), (12, 2, 0, -8)]},
        {"type": "chord", "ch": 1, "vel": 86, "steps": [(0, 1, 92), (4, 1, 78), (8, 1, 88), (12, 1, 78)]},
        {"type": "chord", "ch": 2, "vel": 70, "voices": [0, 3], "skip": ["intro"], "steps": [(6, 1, 70), (14, 1, 66)]},
        {"type": "lead", "ch": 3, "vel": 96},
    ],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "tango", sys.argv)
