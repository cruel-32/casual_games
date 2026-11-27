"""곡: 반짝 K팝 (128 BPM, B단조, ★★★★) — 댄스 팝: 엇박 신스 베이스, 신스 브라스 찌르기, 사각파 아르페지오, 신스 리드. 16분 엇박 북"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L
from song_lib import P

CHORDS = {
    "Bm": {"voicing": [59, 62, 66], "root": 47},
    "G": {"voicing": [59, 62, 67], "root": 43},
    "D": {"voicing": [57, 62, 66], "root": 38},
    "A": {"voicing": [57, 61, 64], "root": 45},
    "Em": {"voicing": [59, 64, 67], "root": 40},
}
PATTERNS = {
    "v1": P("D...K..D..D.K..."),
    "v2": P("D..D..K.D...K..."),
    "v3": P("D...K..DD...K..K"),
    "v4": P("D..D..K.D.D.K.K."),
    "c1": P("D.D.K..DD.D.K..."),
    "c2": P("D..DK..D.DD.K..."),
    "c3": P("D.D.K..D..D.K.K."),
    "c4": P("D..DK..D.D..KK.K"),
    "f": P("D..DK..DH=====K."),
}
RIFFS = {
    "i1": [(0, 2, 78), (3, 2, 78), (6, 2, 76), (8, 2, 74), (11, 2, 74), (14, 2, 71)],
    "i2": [(0, 2, 74), (3, 2, 74), (6, 2, 73), (8, 6, 69), (14, 2, 71)],
    "m1": [(0, 2, 83), (3, 3, 81), (6, 2, 78), (8, 3, 78), (11, 3, 81), (14, 2, 83)],
    "m2": [(0, 3, 86), (3, 3, 83), (6, 2, 81), (8, 8, 78)],
    "m3": [(0, 2, 81), (3, 3, 78), (6, 2, 76), (8, 3, 76), (11, 3, 78), (14, 2, 81)],
    "m4": [(0, 6, 78), (6, 2, 76), (8, 6, 73), (14, 2, 74)],
}
PROG = ["Bm", "G", "D", "A"]
BARS = L.compose({"intro": PROG, "verse": PROG, "chorus": ["G", "A", "Bm", "Bm", "G", "A", "D", "A"], "break": ["Em", "A"], "outro": ["Bm"]}, [
    ("intro", 4, {"lead": ["i1", "i2", "i1", "i2"]}),
    ("verse", ["v1", "v2", "v1", "v3", "v1", "v2", "v4", "v3"], {"lead": [None, "i2", None, "i1"]}),
    ("chorus", ["c1", "c2", "c1", "c3", "c1", "c2", "c4", "c3"], {"lead": ["m1", "m2", "m3", "m4"]}),
    ("break", 2, {"lead": ["i1", "i2"]}),
    ("verse", ["v2", "v4", "v2", "v3", "v2", "v4", "v3", "v4"], {"lead": [None, "i2", None, "i1"]}),
    ("chorus", ["c1", "c2", "c1", "c3", "c2", "c4", "c3", "f"], {"lead": ["m1", "m2", "m3", "m4"]}),
    ("outro", 1, {"lead": ["m4"]}),
])
SONG = {
    "title": "반짝 K팝", "bpm": 128, "level": 4, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": BARS,
    "reverb": 0.16, "mix": {0: 96, 1: 120, 2: 112, 3: 127, 4: 100, 9: 116},
    "programs": {0: (0, 38), 1: (0, 62), 2: (0, 80), 3: (0, 81), 4: (0, 90), 9: (128, 0)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 100, "style": "steps", "shift": -12,
         "steps": [(0, 2, 0, 0), (3, 2, 0, -8), (6, 2, 12, -10), (8, 2, 0, 0), (11, 2, 0, -8), (14, 2, 10, -10)]},
        {"type": "chord", "ch": 1, "vel": 80, "when": ["chorus", "intro"], "shift": 12, "steps": [(0, 1, 84), (3, 1, 76), (6, 1, 80), (14, 1, 72)]},
        {"type": "arp", "ch": 2, "vel": 54, "order": [0, 1, 2, 1], "every": 1, "dur": 0.7, "shift": 12, "skip": ["break"]},
        {"type": "lead", "ch": 3, "vel": 90},
        {"type": "pad", "ch": 4, "vel": 60, "steps": [(0, 16, 60)]},
        {"type": "perc", "ch": 9, "key": 42, "outro_key": 49, "steps": [(s, 40 if s % 2 == 0 else 26) for s in range(16)]},
    ],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "kpop", sys.argv)
