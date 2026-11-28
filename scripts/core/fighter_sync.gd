extends RefCounted
## 온라인 동기화용 캐릭터 상태 인코딩 · 보간 도우미 (게임 모듈 공용)
##
## 한 캐릭터 상태 = 12개 float (PackedFloat32Array 에 이어 붙임)
##   [slot, dt, px, py, pz, rot_y, vx, vy, vz, flags, charge_time, helmets]
##   slot: 게임 안 캐릭터 번호(0~), dt: 메시지 기준 시각과의 차(초)
## 시각은 모두 "서버 시계"(Net.server_now()) 기준

const STRIDE := 12

const F_FLOOR := 1
const F_CHARGING := 2
const F_INVULN := 4
const F_PUSH_ANIM := 8
const F_STUN := 16
# 32: (예전 무거운 신발 — 비워 둠)
const F_SHIELD := 64             # 무적 아이템 보호막 (보기용)
const F_PUSH_WINDOW := 128

const BUFFER_MAX := 32
const EXTRAPOLATE_MAX := 0.12        # 최신 상태가 늦으면 속도로 이만큼까지만 앞질러 그린다


static func flags_of(f: Fighter) -> int:
    var fl := 0
    if (f.net_on_floor if f.remote else f.is_on_floor()):
        fl |= F_FLOOR
    if f.charging:
        fl |= F_CHARGING
    if f.is_invulnerable():
        fl |= F_INVULN
    if f.push_anim > 0.0:
        fl |= F_PUSH_ANIM
    if f.is_stunned():
        fl |= F_STUN
    if f.shield_timer > 0.0:
        fl |= F_SHIELD
    if f.push_window > 0.0:
        fl |= F_PUSH_WINDOW
    return fl


## f 의 현재 상태를 out 에 덧붙인다
static func append(out: PackedFloat32Array, f: Fighter, dt: float) -> void:
    var p := f.global_position
    var v := f.velocity
    out.append_array(PackedFloat32Array([
        f.slot, dt, p.x, p.y, p.z, f.rotation.y, v.x, v.y, v.z,
        flags_of(f), f.charge_time, f.helmets]))


## 상태 1개를 보간 버퍼용 항목으로: [t, pos, rot_y, vel, flags, charge_time, helmets]
static func entry_at(data: PackedFloat32Array, i: int, base_t: float) -> Array:
    var k := i * STRIDE
    return [
        base_t + data[k + 1],
        Vector3(data[k + 2], data[k + 3], data[k + 4]),
        data[k + 5],
        Vector3(data[k + 6], data[k + 7], data[k + 8]),
        int(data[k + 9]),
        data[k + 10],
        int(data[k + 11]),
    ]


static func slot_at(data: PackedFloat32Array, i: int) -> int:
    return int(data[i * STRIDE])


static func count(data: PackedFloat32Array) -> int:
    return data.size() / STRIDE


## 보간 버퍼에 시간순으로 넣는다 (같거나 오래된 것은 버림)
static func push_entry(f: Fighter, e: Array) -> void:
    var b: Array = f.net_buffer
    if not b.is_empty() and float(e[0]) <= float(b[-1][0]):
        return
    b.append(e)
    if b.size() > BUFFER_MAX:
        b.pop_front()


## 원격 캐릭터를 render_t 시점 모습으로 (클라이언트에서 남의 캐릭터를 그릴 때)
static func apply_interpolated(f: Fighter, render_t: float) -> void:
    var b: Array = f.net_buffer
    if b.is_empty():
        return
    var e: Array
    if render_t <= float(b[0][0]):
        e = b[0]
        _apply(f, e[1], e[2], e[3], e)
        return
    var last: Array = b[-1]
    if render_t >= float(last[0]):
        var ahead := minf(render_t - float(last[0]), EXTRAPOLATE_MAX)
        var vel: Vector3 = last[3]
        _apply(f, last[1] + Vector3(vel.x, 0.0, vel.z) * ahead, last[2], vel, last)
        return
    for i in range(b.size() - 1, 0, -1):
        var a: Array = b[i - 1]
        var c: Array = b[i]
        if float(a[0]) <= render_t:
            var span := maxf(float(c[0]) - float(a[0]), 0.0001)
            var k := clampf((render_t - float(a[0])) / span, 0.0, 1.0)
            var pos: Vector3 = (a[1] as Vector3).lerp(c[1], k)
            var rot := lerp_angle(float(a[2]), float(c[2]), k)
            var vel: Vector3 = (a[3] as Vector3).lerp(c[3], k)
            _apply(f, pos, rot, vel, c if k > 0.5 else a)
            # 오래된 항목 정리
            while b.size() > 2 and float(b[1][0]) < render_t - 0.5:
                b.pop_front()
            return


static func _apply(f: Fighter, pos: Vector3, rot: float, vel: Vector3, e: Array) -> void:
    f.global_position = pos
    f.rotation.y = rot
    f.velocity = vel
    apply_flags(f, int(e[4]), float(e[5]))
    f.helmets = int(e[6])
    var fl := int(e[4])
    f.invuln_timer = 0.3 if fl & F_INVULN else 0.0
    f.shield_timer = 1.0 if fl & F_SHIELD else 0.0


## 보기용 상태 플래그 (서버의 사람 캐릭터와 클라이언트의 원격 캐릭터 공용)
static func apply_flags(f: Fighter, fl: int, charge_time: float) -> void:
    # 다른 사람 캐릭터의 목소리: 밀치기(던지기)를 시작하면 기합, 경직(밀려서 맞음)이 시작되면 비명
    #   그 사람 PC 에서만 나던 소리를 내 PC 에서도 (같은 일로 두 번 나는 건 Fighter._voice 가 막음)
    var rise := fl & ~f.net_prev_flags          # 이번에 새로 켜진 표시
    f.net_prev_flags = fl
    if f.remote and not f.dead and f.game and not f.game.is_server():
        if rise & F_PUSH_ANIM:
            f.voice("push")
        if rise & F_STUN:
            f.voice("hit")
    f.net_on_floor = (fl & F_FLOOR) != 0
    f.charging = (fl & F_CHARGING) != 0
    f.charge_time = charge_time
    f.net_invuln = (fl & F_INVULN) != 0
    f.push_anim = 0.2 if fl & F_PUSH_ANIM else 0.0
    f.push_window = 0.15 if fl & F_PUSH_WINDOW else 0.0
    f.stun_timer = 0.15 if fl & F_STUN else 0.0
