# Multi-LLM BSCAN Benchmark -- Bundled Prompt (PB)

## Purpose

This file defines a single "bundled" prompt PB that asks the model to
produce ALL FOUR RTL modules (pad_cell, bsc_cell, tap_controller,
chip_top) in ONE SystemVerilog response, so that port lists and
instance connections are internally consistent by construction.

This is a controlled experiment against the unbundled P1..P4 flow in
PROMPTS.md (which collected the four modules in FOUR separate fresh
conversations). The hypothesis under test is: bundling increases
Tessent ELAB pass rate because cross-module port mismatches vanish.

Repeat PB 3 times per model (fresh session each). Target: 1 prompt x 5
conditions x 3 trials = 15 responses.

Models under evaluation (April 2026 frontier):
  - Claude Opus 4.7 (Anthropic)  -- web UI + cloud-hosted LLM API
  - Claude Opus 4.6 (Anthropic)  -- cloud-hosted LLM API only
  - GPT-5.2         (OpenAI)     -- chatgpt.com
  - Gemini 3.1 Pro  (Google)     -- gemini.google.com

---

## PB -- Bundled 4-module chip_top

Generate ONE SystemVerilog file containing all four modules needed for
an IEEE 1149.1-2013 JTAG boundary scan subsystem. The four modules
must appear in the same response, in the same ```systemverilog``` code
block, in this order:

  1. module `pad_cell`        (actually two modules: `pad_input`,
                               `pad_output`)
  2. module `bsc_cell`
  3. module `tap_controller`
  4. module `chip_top`

Target SystemVerilog IEEE 1800-2017, synthesizable. No testbench.

### Shared architectural conventions (inline; do not reference any
###                                    external spec)

- TCK is the test clock. TMS, TDI are sampled on posedge TCK.
- TDO is launched on NEGEDGE TCK (IEEE 1149.1 requirement).
- TRST_N is asynchronous active-low reset.
- BC_1 boundary scan cells: capture/shift on posedge TCK, update on
  negedge TCK.
- BSR chain has 3*N_IO cells for N_IO I/O pairs:
    BSC[0..N_IO-1]        = input-data
    BSC[N_IO..2*N_IO-1]   = output-data
    BSC[2*N_IO..3*N_IO-1] = output-OE (tristate control)
- Chain bit ordering: after shifting 3*N_IO bits into TDI LSB-first,
  cell BSC[k] holds tdi_data[3*N_IO-1-k]. First bit in ends up at
  BSC[3*N_IO-1].
- Instruction Register is 4 bits:
    EXTEST=4'b0010, SAMPLE=4'b0011, CLAMP=4'b0110,
    UTDR=4'b0111,   IDCODE=4'b1110, BYPASS=4'b1111
- IDCODE value: 32'hDEADBEEF.
- 8-bit TDR accessed via UTDR instruction.
- N_IO = 10 in chip_top (parameterized, default 10).

### Module 1 -- pad_cell

Two behavioral modules in the same section:

- `pad_input`:  transparent input. Ports: `pad_in` (input),
                `to_core` (output). Just assigns `to_core = pad_in`.
- `pad_output`: tristate output. Ports: `from_core` (input),
                `oe` (input), `pad_out` (output).
                `pad_out = oe ? from_core : 1'bz`.

No process library cells. Approx 30-40 lines.

### Module 2 -- bsc_cell

BC_1 boundary scan cell.

- Inputs:  tck, trst_n, shift_dr, capture_dr, update_dr, mode,
           serial_in, parallel_in
- Outputs: serial_out, parallel_out

Behavior:
- posedge TCK: if capture_dr, capture_reg <= parallel_in;
               else if shift_dr, capture_reg <= serial_in.
- negedge TCK: if update_dr, update_reg <= capture_reg.
- Async reset on trst_n=0 clears both registers.
- serial_out = capture_reg.
- Output mux: parallel_out = mode ? update_reg : parallel_in.

Approx 60-80 lines.

### Module 3 -- tap_controller

Full IEEE 1149.1 TAP controller.

- 16-state FSM (Test-Logic-Reset, Run-Test-Idle, Select-DR,
  Capture-DR, Shift-DR, Exit1-DR, Pause-DR, Exit2-DR, Update-DR,
  Select-IR, Capture-IR, Shift-IR, Exit1-IR, Pause-IR, Exit2-IR,
  Update-IR).
- State register clocks on posedge TCK; async TRST_N jumps to
  Test-Logic-Reset.
- 4-bit IR. After TRST_N, IR defaults to IDCODE (4'b1110).
- Six instructions as above.
- Internal 32-bit IDCODE shift register holding 32'hDEADBEEF.
- Internal 1-bit BYPASS register.
- TDO output: launched on NEGEDGE TCK. Mux:
    * BSR (external `bsr_tdo` input)  when ir == EXTEST or SAMPLE
    * IDCODE shift reg                when ir == IDCODE
    * TDR (external `tdr_tdo` input)  when ir == UTDR
    * BYPASS                          otherwise
- Control outputs: capture_dr, shift_dr, update_dr, capture_ir,
  shift_ir, update_ir, bsr_select, tdr_select, ir[3:0].
- Top inputs: tck, tms, tdi, trst_n, bsr_tdo, tdr_tdo.
- Top output: tdo.

Approx 250 lines.

### Module 4 -- chip_top

Integration module. Parameter N_IO=10 (so 30 BSCs, 20 pads).

- Top-level ports:
    input  tck, tms, tdi, trst_n
    output tdo
    input  [N_IO-1:0] chip_in
    output [N_IO-1:0] chip_out   (tristate)

- Instantiates one `tap_controller`.
- Instantiates 3*N_IO `bsc_cell`s in the BSR chain, layout:
    BSC[0..N_IO-1]          input-data   (parallel_in = input-pad core side)
    BSC[N_IO..2*N_IO-1]     output-data  (parallel_in = core_out)
    BSC[2*N_IO..3*N_IO-1]   output-OE    (parallel_in = core_oe)
- Instantiates N_IO `pad_input` and N_IO `pad_output` modules.
- BSR serial chain wiring:
    bsc_serial_chain[0]     = tdi
    bsc_serial_chain[k+1]   = bsc[k].serial_out
    bsr_tdo                 = bsc_serial_chain[3*N_IO]
- Output pad drive comes from BSC output-data cell's parallel_out
  (mode-muxed: EXTEST uses update_reg, normal uses core_out).
- Output pad OE comes from BSC output-OE cell's parallel_out.
- Core logic is a 10-bit inverter. When tdr_config[0]=1, core
  instead outputs (chip_in XOR tdr_config). core_oe is all-1 in
  normal operation.
- TDR: 8-bit shift register.
    * Capture-DR while ir==UTDR: captures tdr_config.
    * Shift-DR  while tdr_select: shifts TDI through register.
    * Update on negedge TCK when update_dr && tdr_select:
      tdr_config <= shift_reg.
- `tdr_tdo` (to tap_controller) = LSB of TDR shift register.

Approx 220 lines.

---

### Response format

Return ONLY SystemVerilog code in a SINGLE ```systemverilog``` code
block containing all four modules (pad_input, pad_output, bsc_cell,
tap_controller, chip_top), in that order. No prose outside the code
block. No separate code blocks.
