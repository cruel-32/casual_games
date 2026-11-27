"""곡: 느린 블루스 (84 BPM, E, ★★) — 12마디 블루스: 클린 기타 셔플, 오르간, 걷는 베이스, 하모니카"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L
from song_lib import P

CHORDS = {
    "E7": {"voicing": [52, 56, 59, 62], "root": 40},
    "A7": {"voicing": [55, 57, 61, 64], "root": 45},
    "B7": {"voicing": [54, 57, 59, 63], "root": 47},
}
TWELVE = ["E7", "E7", "E7", "E7", "A7", "A7", "E7", "E7", "B7", "A7", "E7", "B7"]
PATTERNS = {
    "A": P("D.......K......."),
    "B": P("D.....D.K......."),
    "C": P("D.......K.....D."),
    "D": P("D..D....K......."),
    "E": P("D.....D.K.....D."),
    "f": P("D.......H======="),
}
RIFFS = {
    "h1": [(0, 3, 71), (3, 3, 74), (6, 2, 76), (8, 8, 79)],
    "h2": [(0, 3, 79), (3, 3, 76), (6, 2, 74), (8, 6, 71), (14, 2, 69)],
    "h3": [(0, 8, 76), (10, 2, 74), (12, 4, 71)],
    "h4": [(0, 3, 64), (3, 3, 67), (6, 2, 69), (8, 4, 70), (12, 4, 71)],
    "h5": [(0, 16, 76)],
}
BARS = L.compose({"intro": ["B7", "B7"], "verse": TWELVE, "solo": TWELVE, "outro": ["E7"]}, [
    ("intro", 2, {"lead": ["h4", "h3"]}),
    ("verse", ["A", "B", "A", "C", "A", "B", "A", "D", "B", "C", "A", "B"], {"lead": [None, "h4", None, "h3", None, None, None, "h4", "h1", "h2", "h3", None]}),
    ("solo", ["B", "E", "B", "D", "B", "E", "D", "C", "E", "D", "B", "f"], {"lead": ["h1", "h2", "h1", "h3", "h1", "h2", "h4", "h3", "h1", "h2", "h5", "h3"]}),
    ("outro", 1, {"lead": ["h5"]}),
])
SONG = {
    "title": "느린 블루스", "bpm": 84, "level": 2, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": BARS,
    "reverb": 0.2, "mix": {0: 96, 1: 104, 2: 105, 3: 112, 9: 127},
    "programs": {0: (0, 33), 1: (0, 27), 2: (0, 16), 3: (0, 22), 9: (128, 0)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 100, "style": "steps", "steps": [(0, 3, 0, 0), (4, 3, 4, -6), (8, 3, 7, -4), (12, 3, 9, -8)]},
        {"type": "chord", "ch": 1, "vel": 78, "voices": [0, 2], "steps": [(0, 2, 82), (3, 1, 60), (4, 2, 78), (7, 1, 58), (8, 2, 82), (11, 1, 60), (12, 2, 78), (15, 1, 58)]},
        {"type": "pad", "ch": 2, "vel": 54, "steps": [(0, 16, 54)], "shift": 12},
        {"type": "lead", "ch": 3, "vel": 96},
        {"type": "perc", "ch": 9, "key": 51, "outro_key": 49, "steps": [(0, 44), (3, 30), (4, 40), (7, 30), (8, 44), (11, 30), (12, 40), (15, 30)]},
    ],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "blues", sys.argv)
