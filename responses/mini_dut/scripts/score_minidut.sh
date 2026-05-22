#!/bin/bash
# score_minidut.sh -- Score mini-DUT PS_TAP responses.
# Per-trial scores: compile (standalone VCS elab), stitch (swap into
# reference TB), sim (simv exits with RESULT: ALL_PASS).
#
# Writes: mini_dut_pilot/logs/minidut_scores.csv
#   columns: condition,trial,compile,stitch,sim
set -u

PILOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESP_ROOT="$PILOT/responses"
OUT_CSV="$PILOT/logs/minidut_scores.csv"
SANDBOX_ROOT="$PILOT/sim/sandbox"
REF_TB="$PILOT/tb/tb_tap_fsm.sv"

VCS_BIN="$(command -v vcs || true)"
if [ -z "$VCS_BIN" ] && [ -x <VCS_BIN> ]; then
    VCS_BIN=<VCS_BIN>
    export PATH="<VCS_DIR>:$PATH"
fi
[ -z "$VCS_BIN" ] && { echo "[ERROR] VCS not found" >&2; exit 2; }

strip_fences() {
    python3 -c "
import sys
p = sys.argv[1]
with open(p) as f:
    lines = f.read().splitlines()
cleaned = [ln for ln in lines if not ln.lstrip().startswith('\`\`\`')]
with open(p, 'w') as f:
    f.write('\n'.join(cleaned) + '\n')
" "$1"
}

compile_check() {
    local src="$1" sand="$2"
    rm -rf "$sand"; mkdir -p "$sand"
    cp "$src" "$sand/dut.sv"
    strip_fences "$sand/dut.sv"
    (
        cd "$sand"
        "$VCS_BIN" -full64 -sverilog -timescale=1ns/1ps \
            +define+ELAB_ONLY -l elab.log dut.sv -top tap_fsm \
            +error+50 -o simv >/dev/null 2>&1
    )
    [ $? -eq 0 ] && [ -x "$sand/simv" ]
}

stitch_sim_check() {
    local src="$1" sand="$2"
    rm -rf "$sand"; mkdir -p "$sand/rtl" "$sand/tb" "$sand/sim"
    cp "$src" "$sand/rtl/tap_fsm.sv"
    strip_fences "$sand/rtl/tap_fsm.sv"
    cp "$REF_TB" "$sand/tb/tb_tap_fsm.sv"
    cat > "$sand/sim/flist.f" <<EOF
../rtl/tap_fsm.sv
../tb/tb_tap_fsm.sv
EOF
    (
        cd "$sand/sim"
        "$VCS_BIN" -full64 -sverilog -timescale=1ns/1ps \
            -l compile.log -f flist.f -top tb_tap_fsm \
            +error+100 -o simv >/dev/null 2>&1
    )
    [ $? -ne 0 ] || [ ! -x "$sand/sim/simv" ] && { echo "stitch_compile_fail"; return 1; }
    echo "stitch_compile_ok"
    (
        cd "$sand/sim"
        ./simv -l sim.log >/dev/null 2>&1
    )
    if grep -q "^RESULT: ALL_PASS" "$sand/sim/sim.log" 2>/dev/null; then
        echo "sim_pass"
        return 0
    fi
    echo "sim_fail"
    return 1
}

mkdir -p "$PILOT/logs"
echo "condition,trial,compile,stitch,sim" > "$OUT_CSV"

for d in "$RESP_ROOT"/*/; do
    [ -d "$d" ] || continue
    cond="$(basename "$d")"
    for trial in $(seq 1 10); do
        src="$d/${cond}_PS_TAP_trial${trial}.sv"
        [ -f "$src" ] || continue

        # Strip fences on a tmp copy for compile check
        tmp="$(mktemp --suffix=.sv)"
        cp "$src" "$tmp"
        strip_fences "$tmp"

        sand_c="$SANDBOX_ROOT/${cond}_t${trial}_compile"
        if compile_check "$tmp" "$sand_c"; then
            comp=1
        else
            comp=0
        fi
        rm -f "$tmp"

        sand_s="$SANDBOX_ROOT/${cond}_t${trial}_stitch"
        out="$(stitch_sim_check "$src" "$sand_s")"
        case "$out" in
            *"sim_pass"*)            stitch=1; sim=1 ;;
            *"stitch_compile_ok"*)   stitch=1; sim=0 ;;
            *)                       stitch=0; sim=0 ;;
        esac

        echo "${cond},${trial},${comp},${stitch},${sim}" >> "$OUT_CSV"
        echo "[${cond} t${trial}] compile=${comp} stitch=${stitch} sim=${sim}"
    done
done

echo ""
echo "[DONE] wrote $OUT_CSV"
cat "$OUT_CSV"
