"""곡: 살사 열정 (100 BPM, A단조, ★★★★) — 피아노 몬투노(엇박 화음), 툼바오 베이스(앞당김), 트럼펫, 카우벨. 북은 손 클라베 리듬"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L
from song_lib import P

CHORDS = {
    "Am": {"voicing": [57, 60, 64, 69], "root": 45},
    "Dm": {"voicing": [57, 62, 65, 69], "root": 38},
    "E7": {"voicing": [56, 59, 62, 64], "root": 40},
    "G7": {"voicing": [55, 59, 62, 65], "root": 43},
    "C": {"voicing": [55, 60, 64, 67], "root": 36},
    "F": {"voicing": [57, 60, 65, 69], "root": 41},
}
PATTERNS = {
    "s1": P("D..K..K...K.K..."),          # 손 클라베 3-2 (둥으로 시작)
    "s2": P("D..K..K.D.K.K..."),
    "s3": P("K..K..K.D.K.K.D."),
    "s4": P("D..K..KD..K.K..D"),
    "c1": P("D..K..K.D.K.K.D."),
    "c2": P("D.DK..K.D.K.K..."),
    "c3": P("K..K.DK.D.K.KD.."),
    "f": P("D..K..K.H=====K."),
}
RIFFS = {
    "t1": [(0, 2, 76), (3, 2, 76), (6, 2, 77), (8, 4, 76), (12, 2, 74), (14, 2, 72)],
    "t2": [(0, 2, 71), (3, 2, 72), (6, 2, 74), (8, 6, 76), (14, 2, 68)],
    "t3": [(0, 3, 69), (3, 3, 72), (6, 2, 76), (8, 3, 81), (11, 3, 79), (14, 2, 77)],
    "t4": [(0, 6, 76), (6, 2, 74), (8, 8, 69)],
}
BARS = L.compose({"intro": ["Am", "Dm", "E7", "Am"], "verse": ["Am", "Dm", "E7", "Am"], "chorus": ["F", "G7", "C", "Am", "Dm", "E7", "Am", "E7"],
                  "break": ["Dm", "E7"], "outro": ["Am"]}, [
    ("intro", 4, {"lead": ["t1", "t2", "t3", "t4"]}),
    ("verse", ["s1", "s1", "s2", "s1", "s1", "s2", "s4", "s2"], {"lead": [None, None, None, "t4"]}),
    ("chorus", ["c1", "c2", "c1", "c3", "c1", "c2", "s4", "c3"], {"lead": ["t1", "t2", "t3", "t4"]}),
    ("break", 2, {"lead": ["t3", "t4"]}),
    ("verse", ["s2", "s3", "s2", "s4", "s3", "s3", "s4", "s2"]),
    ("chorus", ["c1", "c2", "c1", "c3", "c2", "c3", "s4", "f"], {"lead": ["t1", "t2", "t3", "t4"]}),
    ("outro", 1, {"lead": ["t4"]}),
])
SONG = {
    "title": "살사 열정", "bpm": 100, "level": 4, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": BARS,
    "reverb": 0.18, "mix": {0: 92, 1: 104, 2: 104, 3: 100, 9: 100},
    "programs": {0: (0, 32), 1: (0, 0), 2: (0, 0), 3: (0, 56), 9: (128, 0)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 104, "style": "tumbao"},
        # 몬투노: 낮은 화음과 높은 화음이 16분 엇박으로 번갈아
        {"type": "chord", "ch": 1, "vel": 82, "voices": [0, 2], "shift": 12, "skip": ["break"], "steps": [(0, 1, 82), (3, 1, 74), (6, 1, 80), (10, 1, 74), (13, 1, 78)]},
        {"type": "chord", "ch": 2, "vel": 76, "voices": [2, 4], "shift": 12, "skip": ["break"], "steps": [(2, 1, 72), (5, 1, 70), (8, 1, 76), (12, 1, 72), (15, 1, 70)]},
        {"type": "lead", "ch": 3, "vel": 96},
        {"type": "perc", "ch": 9, "key": 56, "outro_key": 49, "steps": [(0, 44), (4, 34), (8, 44), (12, 34)]},
        {"type": "perc", "ch": 9, "key": 69, "steps": [(s, 30 if s % 2 == 0 else 20) for s in range(16)]},
    ],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "salsa", sys.argv)
