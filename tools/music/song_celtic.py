"""곡: 켈틱 축제 (150 BPM, D장조, ★★★★) — 피들 가락, 피콜로, 통기타 엇박, 쿵짝 베이스"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L
from song_lib import P

CHORDS = {
    "D": {"voicing": [57, 62, 66], "root": 38},
    "G": {"voicing": [59, 62, 67], "root": 43},
    "A": {"voicing": [57, 61, 64], "root": 45},
    "Bm": {"voicing": [59, 62, 66], "root": 47},
    "Em": {"voicing": [59, 64, 67], "root": 40},
}
PATTERNS = {
    "A": P("D...K...D...K..."),
    "B": P("D.K.D...D...K..."),
    "C": P("D...K.K.D...K..."),
    "D": P("D.K.D...D.K.D..."),
    "c1": P("D.K.D.K.D...K..."),
    "c2": P("D...K.K.D.K.K..."),
    "c3": P("D.K.D...D.K.D.K."),
    "f": P("D.K.D...H======="),
}
RIFFS = {
    "j1": [(0, 2, 74), (2, 2, 76), (4, 2, 78), (6, 2, 74), (8, 2, 81), (10, 2, 78), (12, 4, 74)],
    "j2": [(0, 2, 79), (2, 2, 78), (4, 2, 76), (6, 2, 74), (8, 2, 76), (10, 2, 78), (12, 4, 76)],
    "j3": [(0, 2, 78), (2, 2, 79), (4, 2, 81), (6, 2, 83), (8, 4, 81), (12, 4, 78)],
    "j4": [(0, 2, 76), (2, 2, 74), (4, 2, 73), (6, 2, 71), (8, 8, 74)],
    "p1": [(0, 4, 86), (4, 4, 85), (8, 4, 83), (12, 4, 81)],
}
BARS = L.compose({"intro": ["D", "G", "A", "D"], "verse": ["D", "G", "D", "A"], "chorus": ["G", "A", "D", "Bm", "G", "A", "Em", "A"],
                  "break": ["Bm", "A", "G", "A"], "outro": ["D"]}, [
    ("intro", 4, {"lead": ["j1", "j2", "j3", "j4"]}),
    ("verse", ["A", "B", "A", "C", "A", "B", "D", "C", "A", "B", "D", "C"], {"lead": ["j1", None, "j2", None]}),
    ("chorus", ["c1", "c2", "c1", "c3", "c1", "c2", "c3", "D"], {"lead": ["j3", "j1", "j2", "j4"], "lead2": [None, "p1", None, "p1"]}),
    ("break", 4, {"lead": ["j1", "j2", "j3", "j4"]}),
    ("chorus", ["c1", "c2", "c1", "c3", "c1", "c2", "c3", "D", "c1", "c2", "c3", "f"], {"lead": ["j3", "j1", "j2", "j4"], "lead2": [None, "p1", None, "p1"]}),
    ("outro", 1, {"lead": ["j4"]}),
])
SONG = {
    "title": "켈틱 축제", "bpm": 150, "level": 4, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": BARS,
    "reverb": 0.18, "mix": {0: 96, 1: 108, 3: 112, 4: 107, 9: 100},
    "programs": {0: (0, 32), 1: (0, 25), 3: (0, 110), 4: (0, 72), 9: (128, 0)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 100, "style": "steps", "steps": [(0, 3, 0, 0), (4, 3, 7, -10), (8, 3, 0, -2), (12, 3, 7, -10)]},
        {"type": "chord", "ch": 1, "vel": 76, "steps": [(2, 1.5, 76), (6, 1.5, 70), (10, 1.5, 76), (14, 1.5, 70)]},
        {"type": "lead", "ch": 3, "vel": 98},
        {"type": "lead", "ch": 4, "vel": 84, "key": "lead2"},
        {"type": "perc", "ch": 9, "key": 54, "outro_key": 49, "when": ["chorus"], "steps": [(s * 2, 40 if s % 2 == 0 else 28) for s in range(8)]},
    ],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "celtic", sys.argv)
