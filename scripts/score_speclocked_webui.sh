#!/bin/bash
# score_speclocked_webui.sh -- Web-UI variant of score_speclocked.sh.
#
# Scores ONLY the three hand-collected web-UI conditions (claude_web, gpt,
# gemini) at 3 trials each (total 27 trials x 3 prompts = 81 rows, with
# a 27-row per-trial summary). Does not touch claude_api / claude46_api
# which are already scored in paper/web_ai_eval/speclocked_scores.csv.
#
# Per-prompt detail CSV (speclocked_webui_detail.csv):
#   condition,trial,module,compliance,elab_only,stitch_funccheck
# Per-trial summary CSV (speclocked_webui_scores.csv):
#   condition,trial,prompt,compile,stitch,sim
#   (prompt = "P1_P2_P3"; compile = AND(elab) across P1/P2/P3;
#    stitch = P3 stitch_funccheck pass; sim = same as stitch (stitch
#    already requires 7 PASS / 0 FAIL simulation result))
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESP_ROOT="$REPO/paper/web_ai_eval/responses/speclocked"
DETAIL_CSV="$REPO/paper/web_ai_eval/speclocked_webui_detail.csv"
OUT_CSV="$REPO/paper/web_ai_eval/speclocked_webui_scores.csv"
SUM_CSV="$REPO/paper/web_ai_eval/speclocked_webui_summary.csv"
ERR_LOG="$REPO/paper/web_ai_eval/speclocked_webui_errors.log"
SANDBOX_ROOT="$REPO/sim/speclocked_webui_sandbox"

# Only these three conditions; everything else is skipped.
WEBUI_CONDITIONS=(claude_web gpt gemini)
WEBUI_TRIALS=(1 2 3)

VCS_BIN="$(command -v vcs || true)"
if [ -z "$VCS_BIN" ] && [ -x /ce/vendors/synopsys/vcs/W-2024.09-SP2-2/bin/vcs ]; then
    VCS_BIN=/ce/vendors/synopsys/vcs/W-2024.09-SP2-2/bin/vcs
    export PATH="/ce/vendors/synopsys/vcs/W-2024.09-SP2-2/bin:$PATH"
fi
if [ -z "$VCS_BIN" ]; then
    echo "[ERROR] VCS not found" >&2
    exit 2
fi

: > "$ERR_LOG"

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

check_compliance() {
    local file="$1" module="$2"
    local -a req=()
    case "$module" in
        P1_PS)
            req=("input:pad_pin" "output:core_data"
                 "input:core_data" "input:oe" "output:pad_pin")
            ;;
        P2_PS)
            req=("input:tck" "input:shift_dr" "input:capture_dr"
                 "input:update_dr" "input:mode" "input:serial_in"
                 "output:serial_out" "input:data_in" "output:data_out")
            ;;
        P3_PS)
            req=("input:tck" "input:tms" "input:tdi" "input:trst_n"
                 "output:tdo" "output:tdo_en"
                 "output:shift_dr" "output:capture_dr" "output:update_dr"
                 "output:shift_ir" "output:capture_ir" "output:update_ir"
                 "input:bsr_tdo" "input:tdr_tdo"
                 "output:tdr_select" "output:ir_reg_out")
            ;;
    esac
    for item in "${req[@]}"; do
        local dir="${item%%:*}"
        local nm="${item##*:}"
        if ! grep -Eq "(^|[[:space:],(])${dir}[[:space:]]+(wire[[:space:]]+|logic[[:space:]]+|reg[[:space:]]+)?(\[[^]]*\][[:space:]]*)?${nm}([[:space:]]*[,;)]|[[:space:]]*$)" "$file"; then
            return 1
        fi
    done
    return 0
}

elab_only_check() {
    local src="$1"
    local sand="$2"
    local top="$3"
    rm -rf "$sand"; mkdir -p "$sand"
    local local_src="$sand/dut.sv"
    cp "$src" "$local_src"
    strip_fences "$local_src"
    (
        cd "$sand"
        "$VCS_BIN" -full64 -sverilog -timescale=1ns/1ps \
            +define+ELAB_ONLY \
            -l elab.log dut.sv -top "$top" \
            +error+50 -o simv >/dev/null 2>&1
    )
    local rc=$?
    if [ $rc -eq 0 ] && [ -x "$sand/simv" ]; then
        return 0
    fi
    return 1
}

stitch_funccheck() {
    local cond="$1" trial="$2" sand="$3"
    local rdir="$RESP_ROOT/$cond"
    local p1="$rdir/${cond}_P1_PS_trial${trial}.sv"
    local p2="$rdir/${cond}_P2_PS_trial${trial}.sv"
    local p3="$rdir/${cond}_P3_PS_trial${trial}.sv"

    for f in "$p1" "$p2" "$p3"; do
        [ -f "$f" ] || { echo "[${cond} t${trial}] MISSING $f" >> "$ERR_LOG"; return 1; }
    done

    rm -rf "$sand"
    mkdir -p "$sand/rtl" "$sand/tb" "$sand/sim"
    cp "$p1" "$sand/rtl/pad_cell.sv";       strip_fences "$sand/rtl/pad_cell.sv"
    cp "$p2" "$sand/rtl/bsc_cell.sv";       strip_fences "$sand/rtl/bsc_cell.sv"
    cp "$p3" "$sand/rtl/tap_controller.sv"; strip_fences "$sand/rtl/tap_controller.sv"
    cp "$REPO/rtl/chip_top.sv" "$sand/rtl/chip_top.sv"
    cp "$REPO/tb/tb_bscan.sv"  "$sand/tb/tb_bscan.sv"

    cat > "$sand/sim/flist.f" <<EOF
+incdir+../rtl
+incdir+../tb
../rtl/pad_cell.sv
../rtl/bsc_cell.sv
../rtl/tap_controller.sv
../rtl/chip_top.sv
../tb/tb_bscan.sv
EOF
    (
        cd "$sand/sim"
        "$VCS_BIN" -full64 -sverilog -timescale=1ns/1ps \
            -l compile.log -f flist.f -top tb_bscan \
            +error+100 -o simv >/dev/null 2>&1
    )
    local vrc=$?
    if [ $vrc -ne 0 ] || [ ! -x "$sand/sim/simv" ]; then
        # Capture one-line error excerpt for reporting.
        local clog="$sand/sim/compile.log"
        local excerpt=""
        if [ -f "$clog" ]; then
            excerpt=$(grep -E "^Error|^\s*Error-" "$clog" 2>/dev/null | head -1 | tr -d '\n' | cut -c1-200)
            [ -z "$excerpt" ] && excerpt=$(grep -iE "error" "$clog" 2>/dev/null | head -1 | tr -d '\n' | cut -c1-200)
        fi
        echo "[${cond} t${trial}] STITCH_COMPILE_FAIL rc=$vrc :: ${excerpt}" >> "$ERR_LOG"
        return 1
    fi
    (
        cd "$sand/sim"
        ./simv -l sim.log +vcs+finish+500us >/dev/null 2>&1
    )
    local slog="$sand/sim/sim.log"
    local passed failed
    passed=$(grep -c "^PASS:" "$slog" 2>/dev/null)
    [ -z "$passed" ] && passed=0
    failed=$(grep -c "^FAIL:" "$slog" 2>/dev/null)
    [ -z "$failed" ] && failed=0
    if [ "$passed" -ge 7 ] 2>/dev/null && [ "$failed" -eq 0 ] 2>/dev/null; then
        return 0
    fi
    echo "[${cond} t${trial}] SIM_FAIL passed=$passed failed=$failed" >> "$ERR_LOG"
    return 1
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo "condition,trial,module,compliance,elab_only,stitch_funccheck" > "$DETAIL_CSV"

for cond in "${WEBUI_CONDITIONS[@]}"; do
    rdir="$RESP_ROOT/$cond"
    if [ ! -d "$rdir" ]; then
        echo "[ERROR] missing $rdir" >> "$ERR_LOG"
        continue
    fi
    for pid in P1_PS P2_PS P3_PS; do
        case "$pid" in
            P1_PS) top="pad_input" ;;
            P2_PS) top="bsc_cell" ;;
            P3_PS) top="tap_controller" ;;
        esac
        for trial in "${WEBUI_TRIALS[@]}"; do
            src="$rdir/${cond}_${pid}_trial${trial}.sv"
            if [ ! -f "$src" ]; then
                echo "[${cond} ${pid} t${trial}] MISSING_SOURCE" >> "$ERR_LOG"
                continue
            fi
            tmp="$(mktemp --suffix=.sv)"
            cp "$src" "$tmp"
            python3 -c "
import sys
p=sys.argv[1]
with open(p) as f:
    lines=f.read().splitlines()
cleaned=[ln for ln in lines if not ln.lstrip().startswith('\`\`\`')]
with open(p,'w') as f:
    f.write('\n'.join(cleaned)+'\n')
" "$tmp"

            if check_compliance "$tmp" "$pid"; then comp=1; else comp=0; fi

            sand_elab="$SANDBOX_ROOT/${cond}_${pid}_t${trial}_elab"
            if elab_only_check "$tmp" "$sand_elab" "$top"; then elab=1; else elab=0; fi
            rm -f "$tmp"

            stitch=""
            if [ "$pid" = "P3_PS" ]; then
                sand_st="$SANDBOX_ROOT/${cond}_t${trial}_stitch"
                if stitch_funccheck "$cond" "$trial" "$sand_st"; then stitch=1; else stitch=0; fi
            fi

            echo "${cond},${trial},${pid},${comp},${elab},${stitch}" >> "$DETAIL_CSV"
            echo "[${cond} ${pid} t${trial}] compliance=${comp} elab=${elab} stitch=${stitch}"
        done
    done
done

# ---------------------------------------------------------------------------
# Per-trial summary (27 rows) and per-condition aggregate
# ---------------------------------------------------------------------------
python3 - "$DETAIL_CSV" "$OUT_CSV" "$SUM_CSV" <<'PY'
import csv, sys, collections

detail_path, trial_csv, sum_csv = sys.argv[1], sys.argv[2], sys.argv[3]
rows = list(csv.DictReader(open(detail_path)))

# Per-trial: one row per (condition, trial).
by_trial = collections.defaultdict(dict)
for r in rows:
    key = (r['condition'], int(r['trial']))
    by_trial[key][r['module']] = r

with open(trial_csv, 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['condition', 'trial', 'prompt', 'compile', 'stitch', 'sim'])
    for (cond, trial), mods in sorted(by_trial.items()):
        elab_all = all(mods.get(m, {}).get('elab_only') == '1'
                       for m in ('P1_PS', 'P2_PS', 'P3_PS'))
        p3 = mods.get('P3_PS', {})
        stitch = p3.get('stitch_funccheck', '')
        compile_col = 1 if elab_all else 0
        stitch_col = stitch if stitch in ('0', '1') else ''
        # sim column equals stitch (stitch requires sim pass by construction)
        sim_col = stitch_col
        w.writerow([cond, trial, 'P1+P2+P3',
                    compile_col, stitch_col, sim_col])

# Per-condition summary (compile X/9, stitch X/9, sim X/9)
by_cond = collections.defaultdict(list)
trial_rows = list(csv.DictReader(open(trial_csv)))
for r in trial_rows:
    by_cond[r['condition']].append(r)

def wilson_ci(k, n, z=1.96):
    if n == 0:
        return (0.0, 0.0)
    p = k / n
    denom = 1 + z*z/n
    center = (p + z*z/(2*n)) / denom
    half = (z * ((p*(1-p)/n + z*z/(4*n*n)) ** 0.5)) / denom
    return (max(0.0, center - half), min(1.0, center + half))

with open(sum_csv, 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['condition', 'n_trials', 'compile', 'stitch', 'sim',
                'stitch_rate', 'stitch_ci95_lo', 'stitch_ci95_hi'])
    for cond in sorted(by_cond):
        rs = by_cond[cond]
        n = len(rs)
        n_comp = sum(1 for r in rs if r['compile'] == '1')
        n_st = sum(1 for r in rs if r['stitch'] == '1')
        n_sim = sum(1 for r in rs if r['sim'] == '1')
        lo, hi = wilson_ci(n_st, n)
        w.writerow([cond, n,
                    f"{n_comp}/{n}", f"{n_st}/{n}", f"{n_sim}/{n}",
                    f"{n_st/n:.3f}" if n else "0.000",
                    f"{lo:.3f}", f"{hi:.3f}"])
PY

echo ""
echo "[DONE] wrote $DETAIL_CSV"
echo "[DONE] wrote $OUT_CSV"
echo "[DONE] wrote $SUM_CSV"
echo ""
echo "=== Per-trial ==="
cat "$OUT_CSV"
echo ""
echo "=== Summary ==="
cat "$SUM_CSV"
if [ -s "$ERR_LOG" ]; then
    echo ""
    echo "=== Errors ==="
    cat "$ERR_LOG"
fi
