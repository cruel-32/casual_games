"""곡: 신나는 소풍 (116 BPM, C장조, 쉬움 ★) — 동요풍: 실로폰 멜로디, 통기타 엇박, 콘트라베이스 쿵짝"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L
from song_lib import P

CHORDS = {
    "C": {"voicing": [60, 64, 67], "root": 36},
    "F": {"voicing": [60, 65, 69], "root": 41},
    "G": {"voicing": [59, 62, 67], "root": 43},
    "Am": {"voicing": [60, 64, 69], "root": 45},
}
PATTERNS = {
    "A": P("D...K...D...K..."),
    "B": P("D.......K......."),
    "C": P("D...K...D.D.K..."),
    "f": P("H=======K......."),
}
RIFFS = {
    "a": [(0, 2, 72), (2, 2, 74), (4, 2, 76), (6, 2, 72), (8, 4, 76), (12, 4, 79)],
    "b": [(0, 4, 77), (4, 4, 76), (8, 4, 74), (12, 4, 72)],
    "c": [(0, 2, 74), (2, 2, 74), (4, 2, 76), (6, 2, 77), (8, 8, 79)],
    "d": [(0, 4, 79), (4, 2, 77), (6, 2, 76), (8, 4, 74), (12, 4, 72)],
    "e": [(0, 6, 76), (6, 2, 74), (8, 8, 72)],
}
BARS = L.compose({"intro": ["C", "G"], "verse": ["C", "F", "G", "C"], "chorus": ["F", "C", "G", "C", "F", "C", "G", "C"],
                  "break": ["Am", "G"], "outro": ["C"]}, [
    ("intro", 2, {"lead": ["a", "e"]}),
    ("verse", ["B", "A", "B", "A", "A", "A", "C", "A"], {"lead": ["a", "b", "c", "e"]}),
    ("chorus", ["A", "A", "C", "A", "A", "C", "A", "B"], {"lead": ["c", "a", "d", "e"]}),
    ("break", 2, {"lead": ["b", "c"]}),
    ("verse", ["A", "C", "A", "B"], {"lead": ["a", "b", "c", "e"]}),
    ("chorus", ["A", "A", "C", "A", "A", "C", "A", "f"], {"lead": ["c", "a", "d", "e"]}),
    ("outro", 1, {"lead": ["e"]}),
])
SONG = {
    "title": "신나는 소풍", "bpm": 116, "level": 1, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": BARS,
    "reverb": 0.16, "mix": {0: 96, 1: 104, 3: 127, 9: 127},
    "programs": {0: (0, 32), 1: (0, 25), 3: (0, 13), 9: (128, 0)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 100, "style": "steps", "steps": [(0, 3, 0, 0), (4, 3, 7, -10), (8, 3, 0, -4), (12, 3, 7, -10)]},
        {"type": "chord", "ch": 1, "vel": 80, "shift": 0, "steps": [(2, 1.5, 78), (6, 1.5, 72), (10, 1.5, 78), (14, 1.5, 72)]},
        {"type": "lead", "ch": 3, "vel": 100},
        {"type": "perc", "ch": 9, "key": 54, "outro_key": 49, "when": ["chorus"], "steps": [(4, 46), (12, 46)]},
    ],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "picnic", sys.argv)
