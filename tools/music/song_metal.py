"""곡: 강철 질주 (176 BPM, E단조, ★★★★★) — 메탈: 디스토션 기타 8분 질주 파워코드, 하모니 리드, 피크 베이스. 빠른 8분 북"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L
from song_lib import P

CHORDS = {
    "E5": {"voicing": [52, 59, 64], "root": 40},
    "C5": {"voicing": [48, 55, 60], "root": 36},
    "D5": {"voicing": [50, 57, 62], "root": 38},
    "G5": {"voicing": [55, 62, 67], "root": 43},
    "B5": {"voicing": [47, 54, 59], "root": 35},
    "A5": {"voicing": [45, 52, 57], "root": 45},
}
PATTERNS = {
    "A": P("D.D.K...D.D.K..."),
    "B": P("D.D.K.D.D...K..."),
    "C": P("D...K.D.D.D.K..."),
    "D": P("D.D.K.D.D.D.K..."),
    "c1": P("D.K.D.K.D.K.D.K."),
    "c2": P("D.D.K.D.D.D.K.K."),
    "c3": P("D.K.D.K.D.D.K.K."),
    "x": P("D.D.K.K.D.D.K.K."),
    "f": P("D.D.K...H=======") ,
}
RIFFS = {
    "r1": [(0, 2, 64), (2, 2, 67), (4, 2, 71), (6, 2, 67), (8, 2, 72), (10, 2, 71), (12, 2, 67), (14, 2, 64)],
    "r2": [(0, 2, 62), (2, 2, 66), (4, 2, 69), (6, 2, 66), (8, 4, 71), (12, 4, 74)],
    "m1": [(0, 4, 76), (4, 4, 79), (8, 6, 83), (14, 2, 81)],
    "m2": [(0, 4, 79), (4, 4, 76), (8, 8, 72)],
    "m3": [(0, 4, 74), (4, 4, 78), (8, 6, 81), (14, 2, 79)],
    "m4": [(0, 12, 76), (12, 4, 71)],
}
BARS = L.compose({"intro": ["E5", "E5", "C5", "D5"], "verse": ["E5", "E5", "C5", "D5"], "chorus": ["C5", "D5", "E5", "E5", "C5", "D5", "B5", "B5"],
                  "break": ["A5", "C5", "D5", "B5"], "outro": ["E5"]}, [
    ("intro", 4, {"lead": ["r1", "r1", "r2", "r2"]}),
    ("verse", ["A", "A", "B", "A", "A", "C", "B", "D", "A", "B", "C", "D"], {"lead": ["r1", None, None, None]}),
    ("chorus", ["c2", "x", "c2", "c1", "c2", "x", "c3", "c1"], {"lead": ["m1", "m2", "m3", "m4"]}),
    ("break", 4, {"lead": ["r1", "r2", "r1", "r2"]}),
    ("verse", ["B", "D", "C", "D", "B", "D", "c3", "x"], {"lead": ["r1", None, None, None]}),
    ("chorus", ["c2", "x", "c2", "c1", "c2", "x", "c3", "c1", "c2", "x", "c3", "f"], {"lead": ["m1", "m2", "m3", "m4"]}),
    ("outro", 1),
])
SONG = {
    "title": "강철 질주", "bpm": 176, "level": 5, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": BARS,
    "reverb": 0.1, "mix": {0: 92, 1: 104, 3: 100, 4: 96, 9: 116},
    "programs": {0: (0, 34), 1: (0, 30), 3: (0, 30), 4: (0, 29), 9: (128, 0)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 106, "style": "eighths"},
        {"type": "power", "ch": 1, "vel": 104, "shift": 0,
         "steps": {"break": [(0, 6, 100), (8, 6, 100)], "default": [(s * 2, 0.9, 96 if s % 2 == 0 else 84) for s in range(8)]}},
        {"type": "lead", "ch": 3, "vel": 92},
        {"type": "lead", "ch": 4, "vel": 80, "shift": -5, "when": ["chorus"]},     # 화음 리드 (완전4도 아래)
        {"type": "perc", "ch": 9, "key": 51, "outro_key": 49, "steps": [(s * 2, 52 if s % 2 == 0 else 40) for s in range(8)]},
    ],
    "extra": [(i, 0, 8, 9, 49, 80) for i, b in enumerate(BARS) if b["sec"] in ("chorus", "verse") and (i == 0 or BARS[i - 1]["sec"] != b["sec"])],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "metal", sys.argv)
