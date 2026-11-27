"""곡: 픽셀 모험 (150 BPM, C장조, 약 1분 10초) — 8비트 게임기 소리: 사각파 멜로디·아르페지오, 톱니파 베이스
  python3 tools/music/song_chip.py [미리듣기.wav] → audio/drum/songs/chip/backing.ogg, song.gd
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import song_lib as L

CHORDS = {
    "C": {"voicing": [60, 64, 67], "root": 36},
    "Am": {"voicing": [60, 64, 69], "root": 33},
    "F": {"voicing": [60, 65, 69], "root": 41},
    "G": {"voicing": [59, 62, 67], "root": 43},
    "Em": {"voicing": [59, 64, 67], "root": 40},
    "Dm": {"voicing": [62, 65, 69], "root": 38},
}
PATTERNS = {
    "A": {"don": [0, 8], "ka": [4, 12]},
    "B": {"don": [0, 6, 8], "ka": [4, 12]},
    "C": {"don": [0, 8], "ka": [4, 10, 12]},
    "D": {"don": [0, 2, 8], "ka": [4, 12, 14]},
    "p1": {"don": [0, 6, 8], "ka": [4, 12]},
    "p2": {"don": [0, 8], "ka": [4, 12, 14]},
    "p3": {"don": [0, 2, 8, 10], "ka": [4, 12]},
    "p4": {"don": [0, 8], "ka": [4, 10, 12, 14]},
    "E": {"don": [0, 6, 10], "ka": [4, 12]},
    "F": {"don": [0, 2, 8], "ka": [4, 12]},
    "G": {"don": [0, 8, 10], "ka": [4, 12, 14]},
    "H": {"don": [0, 6, 8], "ka": [4, 10, 12]},
    "k1": {"don": [0, 6, 8], "ka": [4, 12]},
    "k2": {"don": [0, 8], "ka": [4, 12], "hold": {8: 4}},             # 둥~ 피버
    "l1": {"don": [0, 2, 8, 10], "ka": [4, 12]},
    "l2": {"don": [0, 4, 8], "ka": [2, 6, 10, 12, 14]},              # 마지막 필인
}
RIFFS = {
    "i1": [(0, 2, 72), (2, 2, 76), (4, 2, 79), (6, 2, 84), (8, 4, 83), (12, 4, 79)],
    "i2": [(0, 2, 81), (2, 2, 79), (4, 2, 76), (6, 2, 72), (8, 6, 76), (14, 2, 74)],
    "i3": [(0, 2, 77), (2, 2, 76), (4, 2, 74), (6, 2, 72), (8, 4, 69), (12, 4, 72)],
    "i4": [(0, 2, 74), (2, 2, 76), (4, 2, 77), (6, 2, 79), (8, 8, 83)],
    "m1": [(0, 4, 81), (4, 2, 79), (6, 2, 77), (8, 6, 77), (14, 2, 76)],
    "m2": [(0, 4, 79), (4, 2, 77), (6, 2, 76), (8, 6, 74), (14, 2, 72)],
    "m3": [(0, 4, 76), (4, 2, 79), (6, 2, 83), (8, 6, 84), (14, 2, 83)],
    "m4": [(0, 12, 81), (12, 2, 79), (14, 2, 76)],
    "b1": [(0, 1, 74), (1, 1, 77), (2, 1, 81), (3, 1, 86), (4, 4, 84), (8, 8, 81)],
    "b2": [(0, 1, 74), (1, 1, 79), (2, 1, 83), (3, 1, 86), (4, 4, 83), (8, 8, 79)],
}

B = L.Bars({"intro": ["C", "Am", "F", "G"], "verse": ["C", "Am", "F", "G"], "chorus": ["F", "G", "Em", "Am"],
            "break": ["Dm", "G"], "outro": ["C"]})
B.section("intro").plain("intro", 4, leads=("i1", "i2", "i3", "i4"))
B.section("verse").echo(["A", "B", "C"], rest=True, rest_leads=("i1", "i3", "i4"))
B.echo(["D", "E"])
B.section("chorus").echo2([("p1", "p2"), ("p3", "p4")])
B.section("break").plain("break", 2, leads=("b1", "b2"))
B.section("verse").echo(["F", "G", "H", "B"])
B.section("chorus").echo2([("k1", "k2"), ("l1", "l2")])
B.section("outro").plain("outro", 1)
k = 0
for bar in B.bars:
    if bar["sec"] == "chorus":
        bar["lead"] = ("m1", "m2", "m3", "m4")[k % 4]
        k += 1

SONG = {
    "title": "픽셀 모험", "bpm": 150, "level": 4, "chords": CHORDS, "patterns": PATTERNS, "riffs": RIFFS, "bars": B.bars,
    "reverb": 0.08,
    "programs": {0: (0, 81), 1: (0, 80), 2: (0, 80), 9: (128, 0)},
    "layers": [
        {"type": "bass", "ch": 0, "vel": 84, "style": "eighths", "oct": True, "shift": 12},
        {"type": "arp", "ch": 1, "vel": 52, "order": {"break": [0, 1, 2, 1], "default": [0, 1, 2]}, "every": 1, "dur": 0.7, "shift": 0},
        {"type": "lead", "ch": 2, "vel": 90, "shift": 0},
        {"type": "perc", "ch": 9, "key": 42, "outro_key": 49, "steps": [(s * 2, 44 if s % 2 == 0 else 30) for s in range(8)]},
    ],
}
SONG["arrange"] = L.generic_arrange

if __name__ == "__main__":
    L.main(SONG, "chip", sys.argv)
