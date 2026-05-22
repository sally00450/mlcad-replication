#!/bin/bash
# score_axi.sh -- Score third-DUT AXI4-Lite responses.
# Per-trial scores: compile (standalone VCS elab), stitch (swap into
# reference TB), sim (simv exits with RESULT: ALL_PASS).
#
# Usage:
#   score_axi.sh [PS|NC|BOTH]
# Writes:
#   third_dut_pilot/logs/axi_scores.csv           (PS_AXI)
#   third_dut_pilot/logs/axi_nocontract_scores.csv (PS_AXI^nc)
set -u

MODE="${1:-BOTH}"

PILOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX_ROOT="$PILOT/sim/sandbox"
REF_TB="$PILOT/tb/tb_axi_lite.sv"

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
            +define+ELAB_ONLY -l elab.log dut.sv -top axi_lite_regs \
            +error+50 -o simv >/dev/null 2>&1
    )
    [ $? -eq 0 ] && [ -x "$sand/simv" ]
}

stitch_sim_check() {
    local src="$1" sand="$2"
    rm -rf "$sand"; mkdir -p "$sand/rtl" "$sand/tb" "$sand/sim"
    cp "$src" "$sand/rtl/axi_lite_regs.sv"
    strip_fences "$sand/rtl/axi_lite_regs.sv"
    cp "$REF_TB" "$sand/tb/tb_axi_lite.sv"
    cat > "$sand/sim/flist.f" <<EOF
../rtl/axi_lite_regs.sv
../tb/tb_axi_lite.sv
EOF
    (
        cd "$sand/sim"
        "$VCS_BIN" -full64 -sverilog -timescale=1ns/1ps \
            -l compile.log -f flist.f -top tb_axi_lite \
            +error+100 -o simv >/dev/null 2>&1
    )
    if [ $? -ne 0 ] || [ ! -x "$sand/sim/simv" ]; then
        echo "stitch_compile_fail"; return 1
    fi
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

score_condition() {
    local resp_root="$1" out_csv="$2"
    echo "condition,trial,compile,stitch,sim" > "$out_csv"
    for d in "$resp_root"/*/; do
        [ -d "$d" ] || continue
        cond="$(basename "$d")"
        for trial in $(seq 1 10); do
            src="$d/${cond}_PS_AXI_trial${trial}.sv"
            [ -f "$src" ] || continue

            tmp="$(mktemp --suffix=.sv)"
            cp "$src" "$tmp"
            strip_fences "$tmp"

            sand_c="$SANDBOX_ROOT/${cond}_t${trial}_compile"
            if compile_check "$tmp" "$sand_c"; then comp=1; else comp=0; fi
            rm -f "$tmp"

            sand_s="$SANDBOX_ROOT/${cond}_t${trial}_stitch"
            out="$(stitch_sim_check "$src" "$sand_s")"
            case "$out" in
                *"sim_pass"*)          stitch=1; sim=1 ;;
                *"stitch_compile_ok"*) stitch=1; sim=0 ;;
                *)                     stitch=0; sim=0 ;;
            esac

            echo "${cond},${trial},${comp},${stitch},${sim}" >> "$out_csv"
            echo "[${cond} t${trial}] compile=${comp} stitch=${stitch} sim=${sim}"
        done
    done
    echo "[DONE] wrote $out_csv"
    cat "$out_csv"
}

mkdir -p "$PILOT/logs"

if [ "$MODE" = "PS" ] || [ "$MODE" = "BOTH" ]; then
    echo "=== PS_AXI (port contract) ==="
    score_condition "$PILOT/responses" "$PILOT/logs/axi_scores.csv"
fi

if [ "$MODE" = "NC" ] || [ "$MODE" = "BOTH" ]; then
    echo ""
    echo "=== PS_AXI^nc (no port contract) ==="
    score_condition "$PILOT/responses_nocontract" "$PILOT/logs/axi_nocontract_scores.csv"
fi
