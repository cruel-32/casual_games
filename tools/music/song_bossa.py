"""곡: 해변 보사노바 (128 BPM, D장조, ★★★) — 나일론 기타 엇박 반주, 콘트라베이스 근음·5도, 플루트, 쉐이커. 북도 엇박이 많다"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L
from song_lib import P

CHORDS = {
    "Dmaj7": {"voicing": [54, 57, 61, 64], "root": 38},
    "Em7": {"voicing": [55, 59, 62, 64], "root": 40},
    "A7": {"voicing": [55, 57, 61, 64], "root": 45},
    "Gmaj7": {"voicing": [54, 59, 62, 66], "root": 43},
    "F#m7": {"voicing": [52, 57, 61, 64], "root": 42},
    "Bm7": {"voicing": [54, 57, 59, 62], "root": 47},
}
PATTERNS = {
    "A": P("D.......D...K..."),
    "B": P("D..K....D..K...."),          # 3칸 엇박 딱
    "C": P("D..K..D.D..K...."),
    "D": P("D..K..K.D.....K."),
    "c1": P("D..K..D.D..K..D."),
    "c2": P("D..K..K.D..K..K."),
    "c3": P("D.....K.D..K.K.."),
    "f": P("D..K....H=====K."),
}
RIFFS = {
    "i1": [(0, 6, 78), (6, 2, 76), (8, 4, 73), (12, 4, 71)],
    "i2": [(0, 3, 69), (3, 3, 71), (6, 2, 73), (8, 8, 76)],
    "v1": [(2, 2, 73), (4, 4, 76), (10, 2, 74), (12, 4, 73)],
    "v2": [(0, 6, 71), (6, 2, 69), (8, 8, 67)],
    "v3": [(2, 2, 69), (4, 4, 71), (10, 2, 73), (12, 4, 74)],
    "v4": [(0, 8, 73), (10, 6, 69)],
    "m1": [(0, 3, 78), (3, 3, 79), (6, 2, 78), (8, 6, 74), (14, 2, 71)],
    "m2": [(0, 3, 76), (3, 3, 78), (6, 2, 76), (8, 6, 73), (14, 2, 69)],
    "m3": [(0, 3, 74), (3, 3, 76), (6, 2, 74), (8, 6, 71), (14, 2, 73)],
    "m4": [(0, 6, 73), (6, 2, 76), (8, 8, 81)],
}
BARS = L.compose({"intro": ["Dmaj7", "Bm7"], "verse": ["Dmaj7", "Dmaj7", "Em7", "A7"], "chorus": ["Gmaj7", "F#m7", "Em7", "A7"],
                  "break": ["Bm7", "Em7", "A7", "A7"], "outro": ["Dmaj7"]}, [
    ("intro", 2, {"lead": ["i1", "i2"]}),
    ("verse", ["A", "B", "A", "C", "A", "B", "C", "D"], {"lead": ["v1", "v2", "v3", "v4"]}),
    ("chorus", ["c1", "c2", "c1", "c3", "c1", "c2", "c1", "c3"], {"lead": ["m1", "m2", "m3", "m4"]}),
    ("break", 4, {"lead": ["i1", "i2", "v1", "v4"]}),
    ("verse", ["B", "C", "B", "D", "B", "C", "D", "D"], {"lead": ["v1", "v2", "v3", "v4"]}),
    ("chorus", ["c1", "c2", "c1", "c3", "c1", "c2", "c3", "f"], {"lead": ["m1", "m2", "m3", "m4"]}),
    ("outro", 1, {"lead": ["i2"]}),
])
SONG = {
    "title": "해변 보사노바", "bpm": 128, "level": 3, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": BARS,
    "reverb": 0.2, "mix": {0: 90, 1: 112, 2: 104, 3: 92, 9: 116},
    "programs": {0: (0, 32), 1: (0, 24), 2: (0, 49), 3: (0, 73), 9: (128, 0)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 100, "style": "steps",
         "steps": [(0, 5, 0, 0), (6, 2, 7, -12), (8, 5, 7, -4), (14, 2, 0, -12)]},
        {"type": "chord", "ch": 1, "vel": 78, "shift": 12, "steps": [(0, 2, 80), (3, 2, 66), (6, 2, 74), (10, 2, 66), (12, 3, 72)]},
        {"type": "pad", "ch": 2, "vel": 50, "when": ["chorus", "break", "outro"], "steps": [(0, 16, 50)], "shift": 12},
        {"type": "lead", "ch": 3, "vel": 90},
        {"type": "perc", "ch": 9, "key": 70, "outro_key": 49, "steps": [(s, 40 if s % 4 == 0 else (30 if s % 2 == 0 else 22)) for s in range(16)]},
    ],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "bossa", sys.argv)
