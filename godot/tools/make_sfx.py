#!/usr/bin/env python3
# 효과음 합성기: 외부 소리 파일 없이 사인파·잡음으로 짧은 효과음을 만든다(저작권 걱정 없음).
# 실행: python3 tools/make_sfx.py   → godot/sounds/*.wav
import math, random, struct, wave, os

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "sounds")
random.seed(3)

def env(i, n, attack=0.01, release=None):
    t = i / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    if release is None:
        return a * (1.0 - i / n)
    return a * math.exp(-t / release)

def write(name, samples, vol=0.6):
    peak = max(1e-6, max(abs(s) for s in samples))
    with wave.open(os.path.join(OUT, name + ".wav"), "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s / peak * vol)) * 32767)) for s in samples))

def tone(freq_fn, dur, release=None, attack=0.005, shape="sine"):
    n = int(dur * RATE)
    out, ph = [], 0.0
    for i in range(n):
        f = freq_fn(i / n)
        ph += 2 * math.pi * f / RATE
        s = math.sin(ph) if shape == "sine" else (1.0 if math.sin(ph) > 0 else -1.0) * 0.5
        out.append(s * env(i, n, attack, release))
    return out

def noise(dur, smooth=0.5, release=None):
    n = int(dur * RATE)
    out, last = [], 0.0
    for i in range(n):
        last = last * smooth + random.uniform(-1, 1) * (1 - smooth)
        out.append(last * env(i, n, 0.002, release))
    return out

def mix(*parts):
    n = max(len(p) for p in parts)
    return [sum(p[i] for p in parts if i < len(p)) for i in range(n)]

def seq(*parts, gap=0.0):
    out = []
    for p in parts:
        out += p + [0.0] * int(gap * RATE)
    return out

# 선택: 짧고 부드러운 딸깍
write("select", tone(lambda t: 1100 - 300 * t, 0.045, release=0.015), 0.35)
# 명령: 올라가는 짹
write("order", tone(lambda t: 520 + 420 * t, 0.09, release=0.05), 0.4)
# 근접 공격(물기): 짧은 잡음 + 낮은 딱
write("bite", mix(noise(0.06, 0.3, 0.015), tone(lambda t: 180 - 80 * t, 0.06, release=0.02)), 0.35)
# 원거리 공격(분사): 쉬익
write("spit", noise(0.16, 0.85, 0.05), 0.3)
# 턱 타격: 강한 딱
write("snap", mix(noise(0.05, 0.1, 0.008), tone(lambda t: 900 - 700 * t, 0.07, release=0.02)), 0.5)
# 죽음: 내려가는 찍
write("death", tone(lambda t: 700 - 450 * t, 0.16, release=0.07), 0.3)
# 건물 완성: 두 음 종소리
write("built", mix(tone(lambda t: 660, 0.45, release=0.15), tone(lambda t: 990, 0.45, release=0.1)), 0.45)
# 유닛 완성: 퐁
write("ready", tone(lambda t: 440 + 220 * t, 0.12, release=0.05), 0.4)
# 연구 완료: 세 음 상승
write("research", seq(tone(lambda t: 523, 0.1, release=0.06), tone(lambda t: 659, 0.1, release=0.06), tone(lambda t: 784, 0.22, release=0.1)), 0.45)
# 공격받음: 두 번 삐삐
write("alarm", seq(tone(lambda t: 880, 0.08, release=0.05, shape="square"), tone(lambda t: 880, 0.08, release=0.05, shape="square"), gap=0.06), 0.3)
# 안 됨: 낮은 부저
write("error", tone(lambda t: 140, 0.16, release=0.08, shape="square"), 0.25)
# 승리·패배
write("win", seq(*[tone(lambda t, f=f: f, 0.14, release=0.09) for f in (523, 659, 784)], tone(lambda t: 1047, 0.5, release=0.25)), 0.5)
write("lose", seq(*[tone(lambda t, f=f: f, 0.18, release=0.12) for f in (392, 330, 262)], tone(lambda t: 196, 0.6, release=0.3)), 0.5)
print("ok", sorted(os.listdir(OUT)))
