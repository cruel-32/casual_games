"""곡: 한낮의 레게 (76 BPM, G장조, 쉬움 ★) — 2·4박 기타 스캥크, 오르간 버블, 노래하는 베이스, 원드롭 북"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L
from song_lib import P

CHORDS = {
    "G": {"voicing": [55, 59, 62, 67], "root": 43},
    "C": {"voicing": [55, 60, 64, 67], "root": 36},
    "D": {"voicing": [54, 57, 62, 66], "root": 38},
    "Em": {"voicing": [55, 59, 64, 67], "root": 40},
}
PATTERNS = {
    "A": P("........D......."),        # 원드롭: 셋째 박만 쿵
    "B": P("D.......K......."),
    "C": P("........D...K..."),
    "c1": P("D.......D...K..."),
    "c2": P("....K...D......."),
    "f": P("D.......H=======") ,       # 셋째 박부터 둥~ 피버
}
RIFFS = {
    "i1": [(0, 4, 74), (4, 2, 71), (6, 2, 67), (8, 8, 71)],
    "i2": [(0, 4, 72), (4, 4, 71), (8, 4, 69), (12, 4, 67)],
    "i3": [(2, 2, 67), (4, 2, 69), (6, 2, 71), (8, 8, 74)],
    "i4": [(0, 8, 74), (8, 4, 72), (12, 4, 69)],
    "m1": [(0, 6, 76), (6, 2, 74), (8, 8, 72)],
    "m2": [(2, 2, 72), (4, 4, 74), (8, 8, 78)],
    "m3": [(0, 6, 79), (6, 2, 78), (8, 6, 74), (14, 2, 71)],
    "m4": [(0, 12, 71), (12, 4, 74)],
}
BARS = L.compose({"intro": ["G", "C"], "verse": ["G", "C", "G", "D"], "chorus": ["C", "D", "G", "Em"], "break": ["C", "D"], "outro": ["G"]}, [
    ("intro", 2, {"lead": ["i1", "i2"]}),
    ("verse", ["A", "A", "B", "A", "A", "A", "C", "B"], {"lead": [None, None, "i3", None]}),
    ("chorus", ["c1", "c2", "c1", "c2"], {"lead": ["m1", "m2", "m3", "m4"]}),
    ("break", 2, {"lead": ["i3", "i4"]}),
    ("verse", ["A", "B", "C", "A"]),
    ("chorus", ["c1", "c2", "c1", "f"], {"lead": ["m1", "m2", "m3", "m4"]}),
    ("outro", 1, {"lead": ["i1"]}),
])
SONG = {
    "title": "한낮의 레게", "bpm": 76, "level": 1, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": BARS,
    "reverb": 0.2, "mix": {0: 92, 1: 98, 2: 127, 3: 127, 9: 120},
    "programs": {0: (0, 33), 1: (0, 27), 2: (0, 16), 3: (0, 22), 9: (128, 0)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 104, "style": "steps",
         "steps": [(0, 3, 0, 0), (4, 1.5, 7, -10), (6, 2, 12, -14), (10, 2, 7, -8), (12, 3, 0, -4)]},
        {"type": "chord", "ch": 1, "vel": 86, "shift": 12, "voices": [0, 3], "steps": [(4, 1, 88), (12, 1, 88)]},     # 스캥크
        {"type": "chord", "ch": 2, "vel": 58, "steps": [(2, 1, 58), (6, 1, 52), (10, 1, 58), (14, 1, 52)]},            # 오르간 버블
        {"type": "lead", "ch": 3, "vel": 92},
        {"type": "perc", "ch": 9, "key": 42, "outro_key": 49, "steps": [(s * 2, 54 if s % 2 else 40) for s in range(8)]},
    ],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "reggae", sys.argv)
