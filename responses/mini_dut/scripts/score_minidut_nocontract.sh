#!/bin/bash
# score_minidut_nocontract.sh -- Score NO-PORT-CONTRACT mini-DUT responses.
# Reuses the exact compile/stitch/sim logic from score_minidut.sh, but
# scans responses_nocontract/ and writes to logs/minidut_nocontract_scores.csv.
set -u

PILOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESP_ROOT="$PILOT/responses_nocontract"
OUT_CSV="$PILOT/logs/minidut_nocontract_scores.csv"
SANDBOX_ROOT="$PILOT/sim/sandbox_nocontract"
REF_TB="$PILOT/tb/tb_tap_fsm.sv"
STITCH_LOG_DIR="$PILOT/logs/nocontract_stitch_logs"
mkdir -p "$STITCH_LOG_DIR"

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
    local src="$1" sand="$2" trial_tag="$3"
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
    # Archive stitch compile log for error extraction
    cp "$sand/sim/compile.log" "$STITCH_LOG_DIR/${trial_tag}_stitch_compile.log" 2>/dev/null || true
    [ $? -ne 0 ] || [ ! -x "$sand/sim/simv" ] && { echo "stitch_compile_fail"; return 1; }
    echo "stitch_compile_ok"
    (
        cd "$sand/sim"
        ./simv -l sim.log >/dev/null 2>&1
    )
    cp "$sand/sim/sim.log" "$STITCH_LOG_DIR/${trial_tag}_sim.log" 2>/dev/null || true
    if grep -q "^RESULT: ALL_PASS" "$sand/sim/sim.log" 2>/dev/null; then
        echo "sim_pass"
        return 0
    fi
    echo "sim_fail"
    return 1
}

mkdir -p "$PILOT/logs"
echo "condition,trial,compile,stitch,sim" > "$OUT_CSV"

for d in "$RESP_ROOT"/claude_api_nocontract/; do
    [ -d "$d" ] || continue
    cond="$(basename "$d")"
    for trial in $(seq 1 10); do
        src="$d/${cond}_PS_TAP_trial${trial}.sv"
        [ -f "$src" ] || continue

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
        out="$(stitch_sim_check "$src" "$sand_s" "${cond}_t${trial}")"
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
