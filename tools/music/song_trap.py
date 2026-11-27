"""곡: 트랩 비트 (140 BPM, C단조, ★★★★) — 반박자 느낌(딱은 셋째 박), 808 같은 긴 베이스, 벨 멜로디, 16분 하이햇"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L
from song_lib import P

CHORDS = {
    "Cm": {"voicing": [60, 63, 67], "root": 36},
    "Ab": {"voicing": [60, 63, 68], "root": 44},
    "Eb": {"voicing": [58, 63, 67], "root": 39},
    "G": {"voicing": [59, 62, 67], "root": 43},
    "Fm": {"voicing": [60, 65, 68], "root": 41},
}
PATTERNS = {
    "A": P("D.......K......."),
    "B": P("D......DK......."),
    "C": P("D.....D.K.....D."),
    "D": P("D..D....K..D...."),
    "c1": P("D......DK.D...K."),
    "c2": P("D..D..D.K......D"),
    "c3": P("D.....DDK..D.KK."),
    "c4": P("D..D....K.DD.K.K"),
    "f": P("D.......H======="),
}
RIFFS = {
    "b1": [(0, 2, 84), (3, 2, 87), (6, 2, 84), (8, 2, 79), (12, 4, 80)],
    "b2": [(0, 2, 84), (3, 2, 87), (6, 2, 91), (8, 4, 89), (12, 4, 87)],
    "m1": [(0, 3, 79), (3, 3, 80), (6, 2, 79), (8, 6, 75), (14, 2, 72)],
    "m2": [(0, 3, 80), (3, 3, 79), (6, 2, 75), (8, 8, 77)],
}
PROG = ["Cm", "Ab", "Eb", "G"]
BARS = L.compose({"intro": PROG, "verse": PROG, "chorus": ["Ab", "Eb", "Fm", "G"], "break": ["Fm", "G"], "outro": ["Cm"]}, [
    ("intro", 4, {"lead": ["b1", "b2", "b1", "b2"]}),
    ("verse", ["A", "B", "A", "C", "B", "D", "C", "D"], {"lead": ["b1", None, "b2", None]}),
    ("chorus", ["c1", "c2", "c1", "c3", "c1", "c2", "c4", "c3"], {"lead": ["m1", "m2", "m1", "m2"]}),
    ("break", 2, {"lead": ["b1", "b2"]}),
    ("verse", ["C", "D", "c2", "D", "C", "D", "c1", "c4"], {"lead": ["b1", None, "b2", None]}),
    ("chorus", ["c1", "c2", "c1", "c3", "c1", "c2", "c4", "f"], {"lead": ["m1", "m2", "m1", "m2"]}),
    ("outro", 1, {"lead": ["b1"]}),
])
SONG = {
    "title": "트랩 비트", "bpm": 140, "level": 4, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": BARS,
    "reverb": 0.2, "mix": {0: 112, 1: 76, 3: 127, 9: 127},
    "programs": {0: (0, 38), 1: (0, 91), 3: (0, 9), 9: (128, 0)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 104, "style": "boom", "shift": -12},
        {"type": "pad", "ch": 1, "vel": 60, "steps": [(0, 16, 60)]},
        {"type": "lead", "ch": 3, "vel": 100},
        {"type": "perc", "ch": 9, "key": 42, "outro_key": 49, "skip": ["intro"],
         "steps": {"chorus": [(s, 40 if s % 2 == 0 else 28) for s in range(16)], "default": [(s * 2, 40 if s % 2 == 0 else 30) for s in range(8)]}},
    ],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "trap", sys.argv)
