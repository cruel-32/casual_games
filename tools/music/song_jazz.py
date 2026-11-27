"""곡: 재즈 클럽 (132 BPM, B♭장조, ★★★) — 걷는 콘트라베이스, 피아노 엇박 컴핑, 약음기 트럼펫, 라이드 심벌"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L
from song_lib import P

CHORDS = {
    "Cm7": {"voicing": [58, 60, 63, 67], "root": 36},
    "F7": {"voicing": [57, 60, 63, 65], "root": 41},
    "Bbmaj7": {"voicing": [57, 58, 62, 65], "root": 46},
    "Gm7": {"voicing": [58, 62, 65, 67], "root": 43},
    "Ebmaj7": {"voicing": [58, 62, 63, 67], "root": 39},
    "D7": {"voicing": [57, 60, 62, 66], "root": 38},
}
PATTERNS = {
    "A": P("D...K...D...K..."),
    "B": P("D.....K.D...K..."),
    "C": P("D...K..KD...K..."),
    "D": P("D..K....D..K...."),
    "c1": P("D...K.K.D...K..K"),
    "c2": P("D..K..K.D...K..."),
    "c3": P("D.....K.D..K..K."),
    "f": P("D...K...H=====K."),
}
RIFFS = {
    "t1": [(0, 3, 74), (3, 3, 75), (6, 2, 77), (8, 6, 79), (14, 2, 77)],
    "t2": [(0, 3, 75), (3, 3, 74), (6, 2, 72), (8, 8, 70)],
    "t3": [(2, 2, 77), (4, 2, 79), (6, 2, 81), (8, 4, 82), (12, 4, 79)],
    "t4": [(0, 6, 77), (6, 2, 75), (8, 8, 74)],
    "t5": [(0, 2, 70), (3, 3, 72), (6, 2, 74), (8, 3, 75), (11, 3, 77), (14, 2, 79)],
}
BARS = L.compose({"intro": ["Cm7", "F7"], "verse": ["Cm7", "F7", "Bbmaj7", "Gm7"], "chorus": ["Ebmaj7", "D7", "Gm7", "Gm7", "Cm7", "F7", "Bbmaj7", "Bbmaj7"],
                  "break": ["Cm7", "F7"], "outro": ["Bbmaj7"]}, [
    ("intro", 2, {"lead": ["t1", "t2"]}),
    ("verse", ["A", "B", "A", "C", "A", "B", "D", "C"], {"lead": [None, "t2", None, "t4"]}),
    ("chorus", ["c1", "c2", "c1", "c3", "c1", "c2", "c3", "C"], {"lead": ["t3", "t4", "t5", "t2", "t1", "t2", "t5", "t4"]}),
    ("break", 2, {"lead": ["t5", "t1"]}),
    ("verse", ["B", "C", "D", "C", "B", "C", "D", "c2"], {"lead": [None, "t2", None, "t4"]}),
    ("chorus", ["c1", "c2", "c1", "c3", "c1", "c2", "c3", "f"], {"lead": ["t3", "t4", "t5", "t2", "t1", "t2", "t5", "t4"]}),
    ("outro", 1, {"lead": ["t4"]}),
])
SONG = {
    "title": "재즈 클럽", "bpm": 132, "level": 3, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": BARS,
    "reverb": 0.22, "mix": {0: 104, 1: 100, 3: 127, 9: 127},
    "programs": {0: (0, 32), 1: (0, 0), 3: (0, 59), 9: (128, 0)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 100, "style": "steps", "steps": [(0, 3.5, 0, 0), (4, 3.5, 3, -6), (8, 3.5, 7, -4), (12, 3.5, 10, -8)]},
        {"type": "chord", "ch": 1, "vel": 72, "steps": [(3, 1.5, 74), (6, 1, 60), (10, 2, 70), (14, 1, 58)]},
        {"type": "lead", "ch": 3, "vel": 96},
        {"type": "perc", "ch": 9, "key": 51, "outro_key": 49, "steps": [(0, 48), (4, 44), (7, 30), (8, 48), (12, 44), (15, 30)]},
        {"type": "perc", "ch": 9, "key": 44, "steps": [(4, 40), (12, 40)]},
    ],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "jazz", sys.argv)
