#!/bin/bash
# 인공지능 진영 리그전: 5개 진영의 모든 조합을 양쪽 자리에서 1판씩(20판), 4판씩 동시에 돌리고 승수를 센다.
# 사용법: GODOT=/path/to/godot tools/tournament.sh [결과 폴더]   (godot/ 폴더에서 실행)
G=${GODOT:-godot}
P=$(pwd)
OUT=${1:-/tmp/ant-rts-tournament}
mkdir -p "$OUT"; rm -f "$OUT"/*.log
F=(fire leaf weaver trap army)
jobs=()
for i in 0 1 2 3 4; do for j in 0 1 2 3 4; do
  [ $i -eq $j ] && continue
  jobs+=("${F[$i]} ${F[$j]}")
done; done
run() { set -- $1; timeout 400 "$G" --headless --path "$P" -- --autotest --p0=$1 --p1=$2 > "$OUT/$1-$2.log" 2>&1; }
export -f run; export G P OUT
printf '%s\n' "${jobs[@]}" | xargs -P 4 -I{} bash -c 'run "{}"'
python3 - "$OUT" <<'PY'
import sys, glob, re, collections
w = collections.Counter(); g = collections.Counter(); errs = 0; to = 0
for f in sorted(glob.glob(sys.argv[1] + '/*.log')):
    a, b = f.split('/')[-1][:-4].split('-')
    s = open(f, errors='ignore').read()
    errs += len(re.findall(r'SCRIPT ERROR', s))
    m = re.search(r'winner_team=(-?\d+) t=(\d+)', s)
    g[a] += 1; g[b] += 1
    if not m:
        to += 1; print(f"{a} vs {b}: 시간 초과"); continue
    win = [a, b][int(m.group(1))] if m.group(1) in '01' else '?'
    w[win] += 1
    print(f"{a} vs {b}: {win} 승 ({m.group(2)}초)")
print("---")
for k in ['fire', 'leaf', 'weaver', 'trap', 'army']:
    print(f"{k}: {w[k]}승 / {g[k]}판")
print(f"오류 {errs}, 시간 초과 {to}")
PY
