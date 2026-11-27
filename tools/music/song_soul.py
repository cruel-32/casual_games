"""곡: 소울 파티 (100 BPM, F장조, ★★) — 오르간, 피아노, 브라스 찌르기, 핑거 베이스, 탬버린"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L
from song_lib import P

CHORDS = {
    "F": {"voicing": [57, 60, 65, 69], "root": 41},
    "Bb": {"voicing": [58, 62, 65, 70], "root": 46},
    "Gm7": {"voicing": [55, 58, 62, 65], "root": 43},
    "C7": {"voicing": [55, 58, 60, 64], "root": 36},
    "Dm": {"voicing": [57, 62, 65, 69], "root": 38},
}
PATTERNS = {
    "A": P("D...K...D...K..."),
    "B": P("D...K...D.D.K..."),
    "C": P("D...K..DD...K..."),
    "D": P("D.D.K...D...K.K."),
    "c1": P("D...K...D.D.K.K."),
    "c2": P("D..DK...D...K..."),
    "f": P("D...K...H=====K."),
}
RIFFS = {
    "b1": [(2, 2, 72), (6, 2, 72), (10, 2, 74), (12, 4, 77)],
    "b2": [(2, 2, 70), (6, 2, 70), (10, 2, 72), (12, 4, 74)],
    "m1": [(0, 4, 81), (4, 2, 79), (6, 2, 77), (8, 8, 77)],
    "m2": [(0, 4, 82), (4, 2, 81), (6, 2, 79), (8, 8, 77)],
    "m3": [(0, 4, 79), (4, 2, 77), (6, 2, 74), (8, 6, 72), (14, 2, 74)],
    "m4": [(0, 12, 77), (12, 4, 72)],
}
BARS = L.compose({"intro": ["F", "Bb"], "verse": ["F", "Bb", "F", "C7"], "chorus": ["Bb", "C7", "F", "Dm", "Gm7", "C7", "F", "F"],
                  "break": ["Gm7", "C7"], "outro": ["F"]}, [
    ("intro", 2, {"lead": ["b1", "b2"]}),
    ("verse", ["A", "A", "B", "A", "A", "C", "B", "D"], {"lead": [None, "b2", None, "b1"]}),
    ("chorus", ["c1", "A", "c2", "B", "c1", "C", "c2", "D"], {"lead": ["m1", "m2", "m3", "m4"]}),
    ("break", 2, {"lead": ["b1", "b2"]}),
    ("verse", ["B", "C", "B", "D"], {"lead": [None, "b2", None, "b1"]}),
    ("chorus", ["c1", "A", "c2", "B", "c1", "C", "c2", "f"], {"lead": ["m1", "m2", "m3", "m4"]}),
    ("outro", 1, {"lead": ["m4"]}),
])
SONG = {
    "title": "소울 파티", "bpm": 100, "level": 2, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": BARS,
    "reverb": 0.18, "mix": {0: 96, 1: 96, 2: 100, 3: 108, 9: 112},
    "programs": {0: (0, 33), 1: (0, 16), 2: (0, 0), 3: (0, 61), 9: (128, 0)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 100, "style": "anchor"},
        {"type": "pad", "ch": 1, "vel": 60, "steps": [(0, 16, 60)], "shift": 0},
        {"type": "chord", "ch": 2, "vel": 76, "shift": 12, "steps": [(2, 1.5, 76), (6, 1.5, 70), (10, 1.5, 76), (14, 1.5, 70)]},
        {"type": "lead", "ch": 3, "vel": 96},
        {"type": "perc", "ch": 9, "key": 54, "outro_key": 49, "steps": [(s, 44 if s % 4 == 2 else 28) for s in range(0, 16, 2)]},
    ],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "soul", sys.argv)
