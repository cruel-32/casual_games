"""곡: 밤의 드라이브 (110 BPM, A단조, ★★★) — 신스웨이브: 8분 신스 베이스, 톱니파 아르페지오, 패드, 사각파 리드"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L
from song_lib import P

CHORDS = {
    "Am": {"voicing": [57, 60, 64], "root": 45},
    "F": {"voicing": [57, 60, 65], "root": 41},
    "C": {"voicing": [55, 60, 64], "root": 48},
    "G": {"voicing": [55, 59, 62], "root": 43},
    "Em": {"voicing": [55, 59, 64], "root": 40},
}
PATTERNS = {
    "A": P("D...K...D...K..."),
    "B": P("D...K...D.D.K..."),
    "C": P("D..DK...D...K..."),
    "D": P("D...K..DD...K..K"),
    "c1": P("D...K.D.D...K..."),
    "c2": P("D..DK...D.D.K..."),
    "c3": P("D...K...D..DK.K."),
    "f": P("D...K...H=====K."),
}
RIFFS = {
    "s1": [(0, 6, 76), (6, 2, 74), (8, 4, 72), (12, 4, 74)],
    "s2": [(0, 6, 72), (6, 2, 71), (8, 8, 69)],
    "s3": [(0, 4, 76), (4, 4, 79), (8, 6, 81), (14, 2, 79)],
    "s4": [(0, 12, 76), (12, 4, 74)],
}
PROG = ["Am", "F", "C", "G"]
BARS = L.compose({"intro": PROG, "verse": PROG, "chorus": ["F", "G", "Am", "Am", "F", "G", "C", "Em"], "break": ["F", "G"], "outro": ["Am"]}, [
    ("intro", 4, {"lead": [None, None, "s2", "s4"]}),
    ("verse", ["A", "A", "B", "A", "A", "C", "B", "D"]),
    ("chorus", ["c1", "c2", "c1", "c3", "c1", "c2", "c3", "D"], {"lead": ["s1", "s2", "s3", "s4"]}),
    ("break", 2, {"lead": ["s2", "s4"]}),
    ("verse", ["B", "C", "B", "D", "B", "C", "D", "c2"], {"lead": [None, None, None, "s4"]}),
    ("chorus", ["c1", "c2", "c1", "c3", "c1", "c2", "c3", "f"], {"lead": ["s1", "s2", "s3", "s4"]}),
    ("outro", 1, {"lead": ["s4"]}),
])
SONG = {
    "title": "밤의 드라이브", "bpm": 110, "level": 3, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": BARS,
    "reverb": 0.24, "mix": {0: 104, 1: 120, 2: 71, 3: 127, 9: 127},
    "programs": {0: (0, 38), 1: (0, 81), 2: (0, 89), 3: (0, 80), 9: (128, 0)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 96, "style": "eighths", "oct": True, "shift": -12},
        {"type": "arp", "ch": 1, "vel": 56, "order": [0, 1, 2, 1], "every": 1, "dur": 0.7, "shift": 12, "skip": ["intro"]},
        {"type": "pad", "ch": 2, "vel": 64, "steps": [(0, 16, 64)], "shift": 12},
        {"type": "lead", "ch": 3, "vel": 90},
        {"type": "perc", "ch": 9, "key": 42, "outro_key": 49, "skip": ["intro"], "steps": [(s * 2, 44 if s % 2 else 30) for s in range(8)]},
    ],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "synthwave", sys.argv)
