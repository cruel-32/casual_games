"""곡: 무협 활극 (128 BPM, E 5음, ★★★★) — 해금 같은 피들, 샤미센(비파 대신), 대나무 피리 같은 플루트, 스트링 찌르기. 16분 엇박 북"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L
from song_lib import P

CHORDS = {
    "Em": {"voicing": [52, 59, 64, 67], "root": 40},
    "D": {"voicing": [50, 57, 62, 66], "root": 38},
    "C": {"voicing": [48, 55, 60, 64], "root": 36},
    "Bm": {"voicing": [47, 54, 59, 62], "root": 35},
    "Am": {"voicing": [57, 60, 64, 69], "root": 45},
}
PATTERNS = {
    "A": P("D...K...D.D.K..."),
    "B": P("D..D..K.D...K..."),
    "C": P("D...K.K.D..DK..."),
    "D": P("DD..K...DD..K..."),
    "c1": P("D..D..K.D...K.K."),
    "c2": P("DD..K..DD.D.K..."),
    "c3": P("D..DK..D.DK.K..."),
    "c4": P("D.K.D.K.DD..KK.."),
    "f": P("D..D..K.H======="),
}
RIFFS = {
    "w1": [(0, 2, 76), (2, 2, 79), (4, 2, 81), (6, 2, 83), (8, 6, 86), (14, 2, 83)],
    "w2": [(0, 3, 81), (3, 3, 79), (6, 2, 76), (8, 6, 74), (14, 2, 76)],
    "w3": [(0, 1, 88), (1, 1, 86), (2, 2, 83), (4, 4, 81), (8, 4, 79), (12, 4, 76)],
    "w4": [(0, 12, 76), (12, 2, 74), (14, 2, 71)],
    "s1": [(0, 1, 64), (2, 1, 67), (4, 1, 69), (6, 1, 71), (8, 1, 74), (10, 1, 71), (12, 1, 69), (14, 1, 67)],
}
BARS = L.compose({"intro": ["Em", "D", "C", "D"], "verse": ["Em", "Em", "D", "Em"], "chorus": ["C", "D", "Em", "Em", "C", "D", "Bm", "Em"],
                  "break": ["Am", "Bm"], "outro": ["Em"]}, [
    ("intro", 4, {"lead": ["w4", None, "w2", "w4"], "lead2": ["s1", "s1", "s1", "s1"]}),
    ("verse", ["A", "B", "A", "C", "A", "B", "D", "C"], {"lead2": ["s1"]}),
    ("chorus", ["c1", "c2", "c1", "c3", "c1", "c2", "c3", "c4"], {"lead": ["w1", "w2", "w3", "w4"]}),
    ("break", 2, {"lead": ["w3", "w4"]}),
    ("verse", ["B", "D", "C", "D", "B", "D", "c2", "c4"], {"lead2": ["s1"]}),
    ("chorus", ["c1", "c2", "c1", "c3", "c1", "c2", "c4", "f"], {"lead": ["w1", "w2", "w3", "w4"]}),
    ("outro", 1, {"lead": ["w4"]}),
])
SONG = {
    "title": "무협 활극", "bpm": 128, "level": 4, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": BARS,
    "reverb": 0.24, "mix": {0: 96, 1: 121, 2: 96, 3: 112, 4: 100},
    "programs": {0: (0, 32), 1: (0, 48), 2: (0, 106), 3: (0, 110), 4: (0, 106)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 100, "style": "anchor", "pops": ()},
        {"type": "chord", "ch": 1, "vel": 80, "when": ["chorus", "break", "outro"], "steps": [(0, 1, 88), (3, 1, 76), (6, 1, 80), (10, 1, 76), (12, 2, 84)]},
        {"type": "arp", "ch": 2, "vel": 62, "skip": ["break"], "order": [0, 2, 3, 2], "every": 2, "dur": 1.0, "shift": 12},
        {"type": "lead", "ch": 3, "vel": 98},
        {"type": "lead", "ch": 4, "vel": 80, "key": "lead2"},
    ],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "wuxia", sys.argv)
