#!/bin/bash
# score_speclocked.sh -- Score the PS (Spec-Locked) experiment responses.
# Produces paper/web_ai_eval/speclocked_scores.csv (per-response rows) and
# paper/web_ai_eval/speclocked_summary.csv (per-condition aggregates).
#
# Per-response columns:
#   condition,trial,module,compliance,elab_only,stitch_funccheck
# Per-condition summary columns:
#   condition,n_trials,compliance_rate,elab_rate,funccheck_pass
#
# compliance       : 1 iff all mandated ports appear with correct name+direction
#                    (whitespace-tolerant grep), else 0.
# elab_only        : 1 iff `vcs +define+ELAB_ONLY <module>.sv` (with stub where
#                    needed) compiles standalone, else 0.
# stitch_funccheck : for module=tap_controller (P3), assemble the PS P1/P2/P3
#                    of the same trial with reference chip_top + tb_bscan and
#                    run full sim -- 1 iff simulation reports results and all
#                    tests pass, else 0. For P1_PS/P2_PS, blank (N/A).
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESP_ROOT="$REPO/paper/web_ai_eval/responses/speclocked"
OUT_CSV="$REPO/paper/web_ai_eval/speclocked_scores.csv"
SUM_CSV="$REPO/paper/web_ai_eval/speclocked_summary.csv"
SANDBOX_ROOT="$REPO/sim/speclocked_sandbox"

VCS_BIN="$(command -v vcs || true)"
if [ -z "$VCS_BIN" ] && [ -x /ce/vendors/synopsys/vcs/W-2024.09-SP2-2/bin/vcs ]; then
    VCS_BIN=/ce/vendors/synopsys/vcs/W-2024.09-SP2-2/bin/vcs
    export PATH="/ce/vendors/synopsys/vcs/W-2024.09-SP2-2/bin:$PATH"
fi
if [ -z "$VCS_BIN" ]; then
    echo "[ERROR] VCS not found" >&2
    exit 2
fi

# Strip fenced-code markers in-place
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

# Compliance grep: check each required "<direction> ... <name>" token.
# Tolerates `logic`/`wire`/`reg` keyword and whitespace, optional width.
# Returns 0 if ALL required ports match, 1 otherwise.
check_compliance() {
    local file="$1" module="$2"
    # Define required ports per module as "direction:name" entries
    local -a req=()
    case "$module" in
        P1_PS)
            # pad_input
            req=("input:pad_pin" "output:core_data"
                 # pad_output
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
        # Regex: <dir>   (wire|logic|reg)?   [width]?   <name>  [,);]
        # Accept comma or close-paren or semicolon terminator.
        if ! grep -Eq "(^|[[:space:],(])${dir}[[:space:]]+(wire[[:space:]]+|logic[[:space:]]+|reg[[:space:]]+)?(\[[^]]*\][[:space:]]*)?${nm}([[:space:]]*[,;)]|[[:space:]]*$)" "$file"; then
            return 1
        fi
    done
    return 0
}

# Build a one-module standalone ELAB_ONLY sandbox and compile.
# For P1_PS and P2_PS and P3_PS we only need to check that the RTL file
# elaborates on its own (no reference fixture), under the `ELAB_ONLY` flag.
elab_only_check() {
    local src="$1"
    local sand="$2"
    rm -rf "$sand"; mkdir -p "$sand"
    local local_src="$sand/dut.sv"
    cp "$src" "$local_src"
    strip_fences "$local_src"
    (
        cd "$sand"
        "$VCS_BIN" -full64 -sverilog -timescale=1ns/1ps \
            +define+ELAB_ONLY \
            -l elab.log dut.sv -top "$3" \
            +error+50 -o simv >/dev/null 2>&1
    )
    local rc=$?
    if [ $rc -eq 0 ] && [ -x "$sand/simv" ]; then
        return 0
    fi
    return 1
}

# Stitch LLM P1_PS + P2_PS + P3_PS with reference chip_top and tb_bscan,
# compile and run simulation.  Returns 0 on full pass (7 PASS, 0 FAIL).
stitch_funccheck() {
    local cond="$1" trial="$2" sand="$3"
    local rdir="$RESP_ROOT/$cond"
    local p1="$rdir/${cond}_P1_PS_trial${trial}.sv"
    local p2="$rdir/${cond}_P2_PS_trial${trial}.sv"
    local p3="$rdir/${cond}_P3_PS_trial${trial}.sv"

    for f in "$p1" "$p2" "$p3"; do
        [ -f "$f" ] || return 1
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
    return 1
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
echo "condition,trial,module,compliance,elab_only,stitch_funccheck" > "$OUT_CSV"

CONDITIONS=()
for d in "$RESP_ROOT"/*/; do
    [ -d "$d" ] || continue
    CONDITIONS+=("$(basename "$d")")
done

for cond in "${CONDITIONS[@]}"; do
    rdir="$RESP_ROOT/$cond"
    for pid in P1_PS P2_PS P3_PS; do
        # top module per prompt
        case "$pid" in
            P1_PS) top="pad_input" ;;
            P2_PS) top="bsc_cell" ;;
            P3_PS) top="tap_controller" ;;
        esac
        for trial in $(seq 1 10); do
            src="$rdir/${cond}_${pid}_trial${trial}.sv"
            if [ ! -f "$src" ]; then
                continue
            fi
            # Make a throwaway stripped copy for compliance scoring (keep
            # original untouched).
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

            if check_compliance "$tmp" "$pid"; then
                comp=1
            else
                comp=0
            fi

            sand_elab="$SANDBOX_ROOT/${cond}_${pid}_t${trial}_elab"
            if elab_only_check "$tmp" "$sand_elab" "$top"; then
                elab=1
            else
                elab=0
            fi
            rm -f "$tmp"

            stitch=""
            if [ "$pid" = "P3_PS" ]; then
                sand_st="$SANDBOX_ROOT/${cond}_t${trial}_stitch"
                if stitch_funccheck "$cond" "$trial" "$sand_st"; then
                    stitch=1
                else
                    stitch=0
                fi
            fi

            echo "${cond},${trial},${pid},${comp},${elab},${stitch}" >> "$OUT_CSV"
            echo "[${cond} ${pid} t${trial}] compliance=${comp} elab=${elab} stitch=${stitch}"
        done
    done
done

# ---------------------------------------------------------------------------
# Per-condition aggregate summary
# ---------------------------------------------------------------------------
python3 - "$OUT_CSV" "$SUM_CSV" <<'PY'
import csv, sys, collections
rows=list(csv.DictReader(open(sys.argv[1])))
by_cond=collections.defaultdict(list)
for r in rows:
    by_cond[r['condition']].append(r)
out=open(sys.argv[2],'w',newline='')
w=csv.writer(out)
w.writerow(['condition','n_trials','compliance_rate','elab_rate','funccheck_pass'])
for cond, rs in sorted(by_cond.items()):
    n_total = len(rs)
    n_comp  = sum(1 for r in rs if r['compliance']=='1')
    n_elab  = sum(1 for r in rs if r['elab_only']=='1')
    # funccheck: only P3_PS rows have non-empty value
    fc_rows = [r for r in rs if r['module']=='P3_PS']
    fc_pass = sum(1 for r in fc_rows if r['stitch_funccheck']=='1')
    fc_tot  = len(fc_rows)
    w.writerow([
        cond,
        n_total,
        "{0}/{1}".format(n_comp, n_total),
        "{0}/{1}".format(n_elab, n_total),
        "{0}/{1}".format(fc_pass, fc_tot),
    ])
out.close()
PY

echo ""
echo "[DONE] wrote $OUT_CSV"
echo "[DONE] wrote $SUM_CSV"
cat "$SUM_CSV"
