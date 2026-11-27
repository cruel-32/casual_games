"""곡: 질주 록 (140 BPM, A단조, 약 1분 15초) — 디스토션 기타 파워코드, 8분 베이스, 리드 기타
  python3 tools/music/song_rock.py [미리듣기.wav] → audio/drum/songs/rock/backing.ogg, song.gd
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L

CHORDS = {
    "Am": {"voicing": [57, 60, 64, 69], "root": 45},
    "F": {"voicing": [53, 57, 60, 65], "root": 41},
    "G": {"voicing": [55, 59, 62, 67], "root": 43},
    "C": {"voicing": [55, 60, 64, 67], "root": 48},
    "Dm": {"voicing": [53, 57, 62, 65], "root": 38},
    "E": {"voicing": [56, 59, 64, 68], "root": 40},
}
PATTERNS = {
    "A": {"don": [0, 8], "ka": [4, 12]},
    "B": {"don": [0, 6, 8], "ka": [4, 12]},
    "C": {"don": [0, 8, 10], "ka": [4, 12]},
    "D": {"don": [0, 2, 8], "ka": [4, 12]},
    "E": {"don": [0, 2, 8, 10], "ka": [4, 12]},
    "c1": {"don": [0, 8], "ka": [4, 12, 14]},
    "c2": {"don": [0, 6, 8], "ka": [4, 10, 12, 14]},
    "c3": {"don": [0, 2, 8], "ka": [4, 12]},
    "c4": {"don": [0, 8, 10], "ka": [4, 12, 14]},
    "g1": {"don": [0, 6, 10], "ka": [4, 12]},
    "g2": {"don": [0, 2, 6, 8], "ka": [4, 12]},
    "g3": {"don": [0, 8, 10], "ka": [4, 12, 14]},
    "g4": {"don": [0, 6, 8, 10], "ka": [4, 12]},
    "k1": {"don": [0, 8], "ka": [4, 12, 14]},
    "k2": {"don": [0, 8], "ka": [4, 12], "hold": {8: 4}},          # 둥~ 피버
    "l1": {"don": [0, 6, 8], "ka": [4, 12, 14]},
    "l2": {"don": [0, 2], "ka": [4, 6, 8, 10, 12, 14]},            # 마지막 필인
}
RIFFS = {
    "r1": [(0, 2, 69), (2, 2, 72), (4, 2, 74), (6, 2, 76), (8, 4, 79), (12, 4, 76)],
    "r2": [(0, 4, 72), (4, 2, 74), (6, 2, 72), (8, 6, 69), (14, 2, 67)],
    "r3": [(0, 2, 76), (2, 2, 74), (4, 2, 72), (6, 2, 74), (8, 8, 76)],
    "r4": [(0, 4, 79), (4, 4, 76), (8, 4, 74), (12, 4, 71)],
    "m1": [(0, 6, 72), (6, 2, 74), (8, 8, 77)],
    "m2": [(0, 6, 76), (6, 2, 74), (8, 8, 72)],
    "m3": [(0, 4, 74), (4, 4, 71), (8, 4, 74), (12, 4, 79)],
    "m4": [(0, 12, 76), (12, 4, 72)],
    "b1": [(0, 2, 74), (2, 2, 77), (4, 2, 81), (6, 2, 77), (8, 4, 74), (12, 4, 77)],
    "b2": [(0, 2, 76), (2, 2, 80), (4, 2, 83), (6, 2, 80), (8, 8, 76)],
}

B = L.Bars({"intro": ["Am", "Am", "F", "G"], "verse": ["Am", "Am", "F", "G"], "chorus": ["F", "C", "G", "Am"],
            "break": ["Dm", "E"], "outro": ["Am"]})
B.section("intro").plain("intro", 4, leads=("r1", "r3", "r2", "r4"))
B.section("verse").echo(["A", "B", "C"], rest=True, rest_leads=("r3", "r4", "r1"))
B.echo(["D", "E"])
B.section("chorus").echo2([("c1", "c2"), ("c3", "c4")])
B.section("break").plain("break", 2, leads=("b1", "b2"))
B.section("verse").echo(["g1", "g2", "g3", "g4"])
B.section("chorus").echo2([("k1", "k2"), ("l1", "l2")])
B.section("outro").plain("outro", 1)
k = 0
for bar in B.bars:
    if bar["sec"] == "chorus":
        bar["lead"] = ("m1", "m2", "m3", "m4")[k % 4]
        k += 1

EIGHTHS = [(s * 2, 0.8, 72 if s % 2 == 0 else 62) for s in range(8)]
BIG = [(0, 6, 98), (6, 2, 84), (8, 6, 98), (14, 2, 84)]
SONG = {
    "title": "질주 록", "bpm": 140, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": B.bars,
    "reverb": 0.12,
    "mix": {9: 120},
    "programs": {0: (0, 34), 1: (0, 30), 2: (0, 18), 3: (0, 29), 9: (128, 0)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 104, "style": "eighths"},
        {"type": "power", "ch": 1, "vel": 104, "shift": 0,
         "steps": {"verse": EIGHTHS, "break": [(0, 15, 88)], "default": BIG}},
        {"type": "chord", "ch": 2, "vel": 54, "when": ["chorus", "break", "outro"], "steps": [(0, 15, 54)]},
        {"type": "lead", "ch": 3, "vel": 92},
        {"type": "perc", "ch": 9, "key": 42, "skip": ["break"], "outro_key": 49,
         "steps": [(s * 2, 64 if s % 2 == 0 else 48) for s in range(8)]},
    ],
    "extra": [(i, 0, 8, 9, 49, 70) for i, b in enumerate(B.bars) if b["sec"] == "chorus" and (i == 0 or B.bars[i - 1]["sec"] != "chorus")],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "rock", sys.argv)
