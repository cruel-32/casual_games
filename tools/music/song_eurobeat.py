"""곡: 유로 질주 (160 BPM, F#단조, ★★★★★) — 옥타브 신스 베이스, 톱니파 리드, 신스 브라스 찌르기, 피아노 코드. 8분음표만"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L
from song_lib import P

CHORDS = {
    "F#m": {"voicing": [61, 66, 69], "root": 42},
    "D": {"voicing": [62, 66, 69], "root": 38},
    "E": {"voicing": [59, 64, 68], "root": 40},
    "C#m": {"voicing": [61, 64, 68], "root": 37},
    "Bm": {"voicing": [59, 62, 66], "root": 35},
}
PATTERNS = {
    "A": P("D...K...D...K..."),
    "B": P("D...K.K.D...K..."),
    "C": P("D.K.D...D...K.K."),
    "D": P("D...K.K.D.K.K..."),
    "c1": P("D.K.D.K.D...K.K."),
    "c2": P("D...K.K.D.K.D.K."),
    "c3": P("D.K.K.D.D.K.K..."),
    "c4": P("D.D.K.K.D.K.D.K."),
    "f": P("D.K.D.K.H======="),
}
RIFFS = {
    "e1": [(0, 2, 78), (2, 2, 81), (4, 2, 85), (6, 2, 81), (8, 2, 83), (10, 2, 81), (12, 4, 78)],
    "e2": [(0, 2, 81), (2, 2, 83), (4, 2, 85), (6, 2, 86), (8, 4, 85), (12, 2, 83), (14, 2, 81)],
    "e3": [(0, 4, 85), (4, 2, 83), (6, 2, 81), (8, 4, 83), (12, 4, 80)],
    "e4": [(0, 2, 78), (2, 2, 80), (4, 2, 81), (6, 2, 83), (8, 8, 81)],
    "h1": [(0, 1, 69), (3, 1, 69), (6, 2, 71)],
}
BARS = L.compose({"intro": ["F#m", "D", "E", "C#m"], "verse": ["F#m", "D", "E", "F#m"], "chorus": ["D", "E", "C#m", "F#m", "D", "E", "Bm", "C#m"],
                  "break": ["Bm", "C#m"], "outro": ["F#m"]}, [
    ("intro", 4, {"lead": ["e1", "e2", "e1", "e3"]}),
    ("verse", ["A", "B", "A", "C", "A", "B", "D", "C"], {"lead2": ["h1", None, "h1", None]}),
    ("chorus", ["c1", "c2", "c1", "c3", "c1", "c2", "c3", "c4"], {"lead": ["e1", "e2", "e3", "e4"], "lead2": ["h1"]}),
    ("break", 2, {"lead": ["e3", "e4"]}),
    ("verse", ["B", "D", "C", "D", "B", "D", "c2", "c4"], {"lead2": ["h1", None, "h1", None]}),
    ("chorus", ["c1", "c2", "c1", "c3", "c1", "c2", "c3", "c4", "c1", "c2", "c4", "f"], {"lead": ["e1", "e2", "e3", "e4"], "lead2": ["h1"]}),
    ("outro", 1, {"lead": ["e4"]}),
])
SONG = {
    "title": "유로 질주", "bpm": 160, "level": 5, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": BARS,
    "reverb": 0.18, "mix": {0: 91, 1: 84, 3: 127, 4: 127, 9: 127},
    "programs": {0: (0, 38), 1: (0, 0), 3: (0, 81), 4: (0, 62), 9: (128, 0)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 100, "style": "steps", "steps": [(s * 2, 1.6, 12 if s % 2 else 0, 0 if s % 2 == 0 else -8) for s in range(8)]},
        {"type": "chord", "ch": 1, "vel": 70, "skip": ["intro"], "steps": [(2, 1.5, 70), (6, 1.5, 66), (10, 1.5, 70), (14, 1.5, 66)]},
        {"type": "lead", "ch": 3, "vel": 96},
        {"type": "lead", "ch": 4, "vel": 88, "key": "lead2"},
        {"type": "perc", "ch": 9, "key": 42, "outro_key": 49, "skip": ["intro", "break"], "steps": [(s * 2 + 1, 36) for s in range(8)]},
    ],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "eurobeat", sys.argv)
