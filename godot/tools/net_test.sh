#!/bin/bash
# 온라인 대전 점검: 방장 1 + 참가자(처음 접속 → 나감 → 같은 표로 재접속)를 각각 다른 프로그램으로 실행한다.
# 사용법: GODOT=/path/to/godot tools/net_test.sh [ffa|team]   (godot 폴더에서)
G=${GODOT:-godot}
MODE=${1:-ffa}
PORT=$((7700 + RANDOM % 200))
TOK=tok$RANDOM
OUT=$(mktemp -d)
"$G" --headless --path . -s tests/net_test.gd -- host $PORT $MODE > $OUT/host.log 2>&1 &
HP=$!
sleep 2
"$G" --headless --path . -s tests/net_test.gd -- client $PORT $TOK first > $OUT/c1.log 2>&1
sleep 2
"$G" --headless --path . -s tests/net_test.gd -- client $PORT $TOK rejoin > $OUT/c2.log 2>&1
wait $HP
echo "== 방장"; grep -E "^ok|^FAIL|RESULT|SCRIPT|ERROR" $OUT/host.log
echo "== 참가자(처음)"; grep -E "^ok|^FAIL|RESULT|SCRIPT|ERROR" $OUT/c1.log
echo "== 참가자(재접속)"; grep -E "^ok|^FAIL|RESULT|SCRIPT|ERROR" $OUT/c2.log
! grep -qE "^FAIL|SCRIPT ERROR" $OUT/*.log
