"""효과음 생성: python3 tools/audio/gen_sfx.py  →  audio/sfx/*.wav (44.1kHz 16bit 모노)
레트로 장난감 느낌: 짧은 칩튠 음 + 부드러운 노이즈. 음량은 0.89 피크로 맞추고 게임에서 dB로 조절."""
import os, sys
import numpy as np
from scipy.io import wavfile
sys.path.insert(0, os.path.dirname(__file__))
from synth import *

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'audio', 'sfx')
os.makedirs(OUT, exist_ok=True)
sfx = {}


def blip(midi, sec, duty=.25, decay=14, vib=0.0):
    t = t_(sec)
    ph = 2 * np.pi * np.cumsum(hz(midi) * (1 + vib * np.sin(2 * np.pi * 7 * t))) / SR
    return lp(sq(ph, duty), 6000) * np.exp(-t * decay)


def bell(midi, sec, decay=5, idx=1.8, ratio=3.5):
    t = t_(sec); f = hz(midi)
    return np.sin(2 * np.pi * f * t + idx * np.exp(-t * 6) * np.sin(2 * np.pi * f * ratio * t)) * np.exp(-t * decay)


def seq(notes, gap, fn, **kw):
    """notes 를 gap 초 간격으로 이어 붙임"""
    out = np.zeros(int((len(notes) * gap + 0.6) * SR))
    for i, n in enumerate(notes):
        mixat(out, fn(n, .5, **kw), i * gap)
    return out


# ---------------- UI ----------------
# 버튼 클릭: 짧고 둥근 '톡'
t = t_(.07)
sfx['click'] = np.sin(sweep(900, 520, .07)) * np.exp(-t * 55) + .25 * lp(noise(.07), 3000) * np.exp(-t * 120)
# 준비 완료 / 해제
sfx['ready_on'] = seq([72, 79], .07, blip, duty=.5, decay=12)
sfx['ready_off'] = seq([74, 67], .07, blip, duty=.5, decay=12)
# 플레이어 입장·퇴장
sfx['join'] = seq([67, 72, 76], .06, bell, decay=7)
sfx['leave'] = seq([72, 67, 60], .07, bell, decay=8) * .8
# 채팅 수신 '뽁'
t = t_(.12)
sfx['chat'] = np.sin(sweep(600, 1300, .12)) * np.exp(-t * 28)
# 알림(토스트)
sfx['notify'] = seq([76, 84], .08, bell, decay=6)
# 오류 '뿌우'
t = t_(.28)
sfx['error'] = lp(sq(sweep(220, 160, .28), .5), 2200) * adsr(len(t), .005, .05, .7, .05, .22) * .8

# ---------------- 경기 진행 ----------------
sfx['count_tick'] = blip(72, .25, duty=.5, decay=9) + .4 * bell(84, .25, decay=14)
go = np.zeros(int(1.0 * SR))
for i, n in enumerate([72, 76, 79, 84]):
    mixat(go, blip(n, .6, duty=.5, decay=5 if i == 3 else 10), i * .045)
mixat(go, .5 * bell(96, .8, decay=4), .14)
sfx['count_go'] = go
# 승리 팡파레 (C-E-G-C 아르페지오 + 긴 화음)
win = np.zeros(int(2.2 * SR))
for i, n in enumerate([60, 64, 67, 72, 67, 72]):
    mixat(win, blip(n + 12, .3, duty=.25, decay=7), i * .09)
for n in (72, 76, 79, 84):
    mixat(win, .45 * blip(n, 1.4, duty=.5, decay=2.2, vib=.004), .56)
mixat(win, .6 * bell(96, 1.4, decay=2.5), .56)
sfx['win'] = win
# 패배 (반음씩 내려가는 '와와와와~')
lose = np.zeros(int(2.0 * SR))
for i, n in enumerate([67, 66, 65]):
    mixat(lose, blip(n, .35, duty=.5, decay=5), i * .3)
t = t_(1.0)
mixat(lose, lp(sq(2 * np.pi * np.cumsum(hz(64) * (1 + .02 * np.sin(2 * np.pi * 6 * t))) / SR, .5), 2500) * np.exp(-t * 2.2), .9)
sfx['lose'] = lose
# 경기 끝(관전자용) 호루라기
t = t_(.6)
w = np.sin(2 * np.pi * np.cumsum(2400 * (1 + .03 * np.sin(2 * np.pi * 32 * t))) / SR) * adsr(len(t), .01, .05, .8, .08, .5)
sfx['whistle'] = w * .7 + .15 * bp(noise(.6), 2000, 4000) * adsr(len(t), .01, .05, .8, .08, .5)

# ---------------- 캐릭터 ----------------
# 점프: 위로 '뿅'
t = t_(.16)
sfx['jump'] = lp(sq(sweep(330, 760, .16), .5), 3000) * np.exp(-t * 14) * .8
# 착지: 작은 '툭'
t = t_(.1)
sfx['land'] = (np.sin(sweep(140, 70, .1)) * .9 + .4 * lp(noise(.1), 900)) * np.exp(-t * 40)
# 차징 루프 (게임에서 pitch_scale 을 올리며 반복) — 0.5초 길이, 끊김 없이 반복되게 주기를 맞춤
t = t_(.5)
f0 = 220.0  # 0.5초에 정확히 110 주기
ch = .55 * sq(2 * np.pi * f0 * t, .5) + .45 * np.sin(2 * np.pi * f0 * 2 * t) * (0.6 + .4 * np.sin(2 * np.pi * 8 * t))
sfx['charge_loop'] = lp(ch, 2400) * .6
# 풀차징 '띵!'
sfx['charge_full'] = bell(91, .5, decay=7) + .5 * bell(96, .5, decay=9)
# 제자리 밀기 '휙'
t = t_(.18)
sfx['push'] = bp(noise(.18), 700, 4500) * np.sin(np.pi * np.clip(t / .18, 0, 1)) ** 2 * 1.2
# 돌진 '슈웅'
t = t_(.32)
dn = bp(noise(.32), 400, 3000) * np.sin(np.pi * np.clip(t / .32, 0, 1)) ** 1.5
sfx['dash'] = dn * 1.2 + .35 * lp(saw(sweep(180, 420, .32)), 1500) * np.exp(-t * 6)
# 맞음 '퐁' (장난감 망치)
t = t_(.22)
sfx['hit'] = (np.sin(sweep(620, 160, .22)) * np.exp(-t * 16) + .5 * lp(noise(.22), 2500) * np.exp(-t * 60)) * 1.0
# 회전 기둥에 맞음 '빡'
t = t_(.3)
sfx['swat'] = (lp(noise(.3), 1800) * np.exp(-t * 30) * 1.2 + np.sin(sweep(300, 90, .3)) * np.exp(-t * 12))
# 벽꽝 '깡'
t = t_(.45)
metal = sum(np.sin(2 * np.pi * f * t) * np.exp(-t * d) for f, d in ((523, 9), (1307, 12), (2093, 16), (2911, 20)))
sfx['wall'] = metal * .5 + .6 * lp(noise(.45), 1200) * np.exp(-t * 35)
# 몸끼리 부딪힘 '뽀잉'
t = t_(.2)
sfx['bump'] = np.sin(2 * np.pi * np.cumsum(260 * (1 + .25 * np.sin(2 * np.pi * 18 * t) * np.exp(-t * 10))) / SR) * np.exp(-t * 14) * .7
# 헬멧 깨짐 '깡 + 짤랑'
t = t_(.6)
hb = sum(np.sin(2 * np.pi * f * t) * np.exp(-t * d) for f, d in ((880, 10), (1760, 14), (2640, 22)))
for i in range(6):
    mixat(hb, .25 * bell(96 + int(rng.integers(0, 8)), .2, decay=20), .05 + i * .045)
sfx['helmet_break'] = hb + .5 * hp(noise(.6), 3000) * np.exp(-t * 25)
# 탈락 (낙석에 깔림) '쿵 + 뿌잉~'
t = t_(.9)
die = np.zeros(len(t))
mixat(die, (np.sin(sweep(160, 40, .35)) + .7 * lp(noise(.35), 600)) * np.exp(-t_(.35) * 9), 0)
mixat(die, .55 * lp(sq(sweep(700, 180, .55), .5), 2500) * np.exp(-t_(.55) * 3), .12)
sfx['die'] = die
# 경직(어지러움) '삐요삐요'
st = np.zeros(int(.6 * SR))
for i, n in enumerate([88, 84, 88, 84]):
    mixat(st, .6 * blip(n, .12, duty=.5, decay=18), i * .11)
sfx['dizzy'] = st

# ---------------- 낙석 ----------------
# 떨어지는 소리 '휘이이' (내려가는 휘파람, 1.1초)
t = t_(1.1)
sfx['rock_fall'] = np.sin(sweep(1400, 500, 1.1)) * adsr(len(t), .25, .1, .9, .05, 1.05) * .35 + .1 * bp(noise(1.1), 1000, 3000) * adsr(len(t), .3, .1, .8, .05, 1.0)
# 땅에 떨어짐 '쿵'
t = t_(.5)
sfx['rock_land'] = (np.sin(sweep(110, 38, .5)) * 1.0 + .9 * lp(noise(.5), 500)) * np.exp(-t * 8)
# 돌 부서짐 '와작'
t = t_(.35)
cr = np.zeros(len(t))
for i in range(7):
    mixat(cr, bp(noise(.05), 800 + i * 300, 5000) * np.exp(-t_(.05) * 60), i * .02 + rng.random() * .01)
sfx['rock_break'] = cr + .6 * np.sin(sweep(180, 60, .35)) * np.exp(-t * 12)

# ---------------- 아이템 ----------------
t = t_(.15)
sfx['item_spawn'] = np.sin(sweep(300, 1200, .15)) * np.exp(-t * 18) * .8
sfx['pickup'] = seq([79, 84, 88], .05, bell, decay=9)
sfx['pickup_helmet'] = seq([72, 79], .06, bell, decay=6, ratio=2.0, idx=2.5)
pc = np.zeros(int(.6 * SR))
mixat(pc, lp(sq(sweep(300, 1600, .3), .25), 5000) * np.exp(-t_(.3) * 5) * .8, 0)
mixat(pc, .6 * bell(91, .4, decay=8), .22)
sfx['pickup_charge'] = pc
cd = np.zeros(int(.7 * SR))
for i, n in enumerate([84, 79, 84, 79, 91]):
    mixat(cd, .7 * blip(n, .1, duty=.5, decay=25) if i < 4 else bell(n, .4, decay=8), i * .07)
sfx['pickup_cooldown'] = cd
bt = np.zeros(int(.5 * SR))
for i in range(2):
    mixat(bt, (np.sin(sweep(120, 60, .15)) + .5 * lp(noise(.15), 700)) * np.exp(-t_(.15) * 20), i * .13)
sfx['pickup_boots'] = bt
# 보호막 켜짐 '위잉~ 짠'
t = t_(.8)
sh = np.zeros(len(t))
mixat(sh, .6 * lp(saw(sweep(200, 900, .5)), 3000) * adsr(int(.5 * SR), .02, .1, .8, .05, .45), 0)
for n in (84, 88, 91, 96):
    mixat(sh, .35 * bell(n, .5, decay=5), .38)
sfx['shield_on'] = sh
t = t_(.5)
sfx['shield_off'] = .6 * lp(saw(sweep(800, 180, .5)), 2500) * adsr(len(t), .01, .1, .8, .06, .42)
# 쿨타임 다 참 (아주 작은 '틱')
sfx['ready_ping'] = .5 * bell(96, .15, decay=30)

# ---------------- 환경 ----------------
t = t_(1.8)
g = lp(noise(1.8), 900) * np.sin(np.pi * np.clip(t / 1.8, 0, 1)) ** 1.5
sfx['wind'] = g * (1 + .3 * np.sin(2 * np.pi * 1.3 * t)) * .9

for k, x in sfx.items():
    if x is None:
        continue
    y = fade(norm(np.asarray(x, dtype=float)), .001, .012 if k != 'charge_loop' else 0.0005)
    wavfile.write(os.path.join(OUT, k + '.wav'), SR, (y * 32767).astype(np.int16))
print(len([k for k in sfx if sfx[k] is not None]), 'sfx ->', os.path.abspath(OUT))
