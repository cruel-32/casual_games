"""곡: 아침 햇살 (72 BPM, G장조, 쉬움 ★) — 잔잔하게: 피아노 펼침화음, 하프, 스트링, 플루트"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L
from song_lib import P

CHORDS = {
    "G": {"voicing": [55, 59, 62, 67], "root": 43},
    "Em": {"voicing": [55, 59, 64, 67], "root": 40},
    "C": {"voicing": [55, 60, 64, 67], "root": 36},
    "D": {"voicing": [54, 57, 62, 66], "root": 38},
    "Am": {"voicing": [57, 60, 64, 69], "root": 45},
}
PATTERNS = {
    "A": P("D.......K......."),
    "B": P("D..............."),
    "C": P("D.......D...K..."),
    "D": P("D.....D.K......."),
    "f": P("H=======K......."),
}
RIFFS = {
    "a": [(0, 6, 74), (6, 2, 72), (8, 8, 71)],
    "b": [(0, 6, 76), (6, 2, 74), (8, 8, 72)],
    "c": [(0, 4, 72), (4, 4, 74), (8, 8, 76)],
    "d": [(0, 12, 74), (12, 4, 71)],
    "e": [(0, 4, 79), (4, 4, 78), (8, 4, 76), (12, 4, 74)],
    "g": [(0, 16, 71)],
}
BARS = L.compose({"intro": ["G", "D"], "verse": ["G", "Em", "C", "D"], "chorus": ["C", "D", "G", "Em", "Am", "D", "G", "G"],
                  "break": ["C", "D"], "outro": ["G"]}, [
    ("intro", 2, {"lead": ["a", "d"]}),
    ("verse", ["B", "A", "B", "A", "A", "A", "C", "A"], {"lead": ["a", "b", "c", "d"]}),
    ("chorus", ["A", "C", "A", "D", "A", "C", "A", "B"], {"lead": ["e", "c", "a", "b", "c", "e", "d", "g"]}),
    ("break", 2, {"lead": ["c", "d"]}),
    ("chorus", ["A", "C", "D", "f"], {"lead": ["e", "c", "d", "g"]}),
    ("outro", 1, {"lead": ["g"]}),
])
SONG = {
    "title": "아침 햇살", "bpm": 72, "level": 1, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": BARS,
    "reverb": 0.3, "mix": {0: 90, 1: 104, 2: 106, 3: 79, 4: 121},
    "programs": {0: (0, 32), 1: (0, 0), 2: (0, 48), 3: (0, 73), 4: (0, 46)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 90, "style": "long", "second": 7},
        {"type": "arp", "ch": 1, "vel": 66, "order": [0, 1, 2, 3, 2, 1, 0, 2], "every": 2, "dur": 3.0, "shift": 0},
        {"type": "pad", "ch": 2, "vel": 56, "steps": [(0, 16, 56)], "shift": 12},
        {"type": "lead", "ch": 3, "vel": 92},
        {"type": "arp", "ch": 4, "vel": 60, "when": ["chorus", "outro"], "order": [0, 2, 3, 1], "every": 4, "dur": 4.0, "shift": 12},
    ],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "morning", sys.argv)
