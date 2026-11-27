"""곡: 파도 질주 (172 BPM, E단조, ★★★★★) — 서프 록: 클린 기타 트레몰로, 질주 베이스, 오르간. 8분음표만"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L
from song_lib import P

CHORDS = {
    "Em": {"voicing": [59, 64, 67], "root": 40},
    "C": {"voicing": [60, 64, 67], "root": 36},
    "D": {"voicing": [57, 62, 66], "root": 38},
    "B": {"voicing": [59, 63, 66], "root": 35},
    "Am": {"voicing": [57, 60, 64], "root": 45},
}
PATTERNS = {
    "A": P("D...K...D...K..."),
    "B": P("D.D.K...D...K..."),
    "C": P("D...K...D.D.K.K."),
    "D": P("D.K.D...D.K.K..."),
    "c1": P("D.D.K.K.D...K.K."),
    "c2": P("D.K.D.K.D.D.K..."),
    "c3": P("D.D.K.D.K.D.K.K."),
    "c4": P("D.K.K.D.D.K.D.D."),
    "f": P("D.D.K.K.H======="),
}
# 트레몰로: 같은 음을 16분으로 빠르게(반주에만 — 북 노트와 무관)
def trem(notes):
    out = []
    for start, length, pitch in notes:
        for s in range(start, start + length):
            out.append((s, 1, pitch))
    return out
RIFFS = {
    "t1": trem([(0, 4, 76), (4, 4, 79), (8, 4, 83), (12, 4, 79)]),
    "t2": trem([(0, 4, 84), (4, 4, 83), (8, 4, 81), (12, 4, 79)]),
    "t3": trem([(0, 2, 76), (2, 2, 78), (4, 4, 79), (8, 8, 78)]),
    "t4": trem([(0, 8, 76), (8, 4, 75), (12, 4, 71)]),
}
BARS = L.compose({"intro": ["Em", "Em", "C", "B"], "verse": ["Em", "C", "D", "B"], "chorus": ["Am", "Em", "C", "B", "Am", "Em", "C", "B"],
                  "break": ["C", "B"], "outro": ["Em"]}, [
    ("intro", 4, {"lead": ["t4", "t1", "t2", "t3"]}),
    ("verse", ["A", "B", "A", "C", "A", "B", "D", "C"], {}),
    ("chorus", ["c1", "c2", "c1", "c3", "c1", "c2", "c3", "c4"], {"lead": ["t1", "t2", "t1", "t3"]}),
    ("break", 2, {"lead": ["t2", "t3"]}),
    ("verse", ["B", "D", "C", "D", "B", "D", "c2", "c4"], {}),
    ("chorus", ["c1", "c2", "c1", "c3", "c1", "c2", "c3", "c4", "c1", "c2", "c4", "f"], {"lead": ["t1", "t2", "t1", "t3"]}),
    ("outro", 1, {"lead": ["t4"]}),
])
SONG = {
    "title": "파도 질주", "bpm": 172, "level": 5, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": BARS,
    "reverb": 0.3, "mix": {0: 104, 1: 101, 3: 104, 9: 127},
    "programs": {0: (0, 34), 1: (0, 16), 3: (0, 27), 9: (128, 0)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 100, "style": "steps", "steps": [(0, 1.6, 0, 0), (2, 1.6, 0, -10), (4, 1.6, 7, -4), (6, 1.6, 0, -10), (8, 1.6, 12, 0), (10, 1.6, 7, -10), (12, 1.6, 0, -4), (14, 1.6, 7, -10)]},
        {"type": "pad", "ch": 1, "vel": 56, "skip": ["intro"], "steps": [(0, 16, 56)]},
        {"type": "lead", "ch": 3, "vel": 92},
        {"type": "perc", "ch": 9, "key": 51, "outro_key": 49, "skip": ["intro"], "steps": [(s * 2, 40 if s % 2 == 0 else 30) for s in range(8)]},
    ],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "surf", sys.argv)
