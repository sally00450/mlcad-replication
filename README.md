# Replication Package — LLM Port-Contract Drift Case Study

Anonymous replication package for MLCAD 2026 submission.

## Contents

```
prompts/               Verbatim prompts used across all experiments
  PROMPTS_SPECLOCKED.md    PS variants of P1/P2/P3 (spec-locked port contract)
  PROMPTS_BUNDLED.md        PB (bundled 4-module chip_top)
  PROMPTS_BUNDLED_LIBAWARE.md   PB' (paraphrased .mdt attribute tags)
  PROMPTS_BUNDLED_REALPORTS.md  PB'' (toolchain-synthesized stub ports)

responses/
  main_bscan/speclocked/   PS responses: 5 conditions × 3 prompts × up to 10 trials
  mini_dut/                TAP-only mini-DUT pilot (n=10 PS + n=10 no-contract)
  axi/                     AXI4-Lite scope probe (n=10 PS + n=10 no-contract)

scores/                Score CSVs referenced in the paper
  funccheck_scores.csv              §6.5 VCS stitch-in baseline (0/15)
  speclocked_scores.csv             §7.5 PS main pilot (n=10 Claude API, 20/20)
  speclocked_webui_scores.csv       §8.6 cross-vendor web-UI (Claude/GPT/Gemini)
  speclocked_webui_summary.csv      Aggregated web-UI Wilson CIs
  tessent_bundled_scores.csv        §7.4 PB bundled (0/15)
  tessent_libaware_scores.csv       §7.5 PB'/PB'' (0/6 vs 6/6)
  layer2_bundled_scores.csv         §7.4 L2a cross-check
  scores.csv                        Main 0-3 rubric matrix (legacy, see paper Table per-stage)

scripts/               Collection + scoring scripts
  collect_*.py          Bedrock API collection (boto3)
  score_*.sh            VCS compile + stitch-in + sim scoring

reference_design/
  src/hdl/              Reference chip_top RTL
  tb/tb_bscan.sv        Reference BSCAN testbench (7 functional tests)
  tb/tb_compliance.sv   Larger compliance testbench (29 tests)
```

## Reproducing results

1. API collection requires AWS Bedrock access to
   `us.anthropic.claude-opus-4-7` and `us.anthropic.claude-opus-4-6-v1`.
   Web-UI conditions (Claude 4.7 web, GPT-5.2, Gemini 3.1 Pro) were
   collected by hand through an enterprise gateway; the raw `.sv`
   responses are archived under `responses/main_bscan/speclocked/`
   (subdirs `claude_web/`, `gpt/`, `gemini/`).
2. Scoring requires Synopsys VCS W-2024.09-SP2-2 or compatible.
3. Tessent BSD Compiler scoring is vendor-locked; the sandbox
   directories and compile.log / sim.log artifacts are archived
   under the respective pilot directories.

## Statistics

Per-condition Fisher's exact p-values referenced in §7.6 of the paper
are computed from these CSVs using `scipy.stats.fisher_exact`.
