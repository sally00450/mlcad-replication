# Multi-LLM BSCAN Benchmark -- Library-Aware Bundled Prompt (PB')

## Purpose

This file defines the library-aware bundled prompt PB'. It is identical
to PB (see PROMPTS_BUNDLED.md) except for one additional constraint:
the port names of `pad_input` and `pad_output` MUST match the Tessent
pad library contract exactly (see scripts/mock_padlib.mdt). Everything
else -- the four-module structure, BSR layout, IR encoding, TAP FSM,
N_IO=10, response format, etc. -- is unchanged.

PB' is the Layer-3 mitigation pilot requested by Reviewer W2: does
telling the LLM the library's exact pad port names make Tessent ELAB
pass? PB (no library awareness) scored 0/6 at ELAB across claude-opus
-4-7 and claude-opus-4-6-v1 Bedrock API trials.

Repeat PB' 3 times per model (fresh session each).
  - Claude Opus 4.7 (Bedrock API, us.anthropic.claude-opus-4-7)
  - Claude Opus 4.6 (Bedrock API, us.anthropic.claude-opus-4-6-v1)
Target: 1 prompt x 2 models x 3 trials = 6 responses.

---

## PB' -- Library-Aware Bundled 4-module chip_top

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

### Module 1 -- pad_cell  **[LIBRARY-AWARE OVERRIDE]**

This section OVERRIDES the generic pad_cell conventions. The two pad
modules are consumed by a Tessent BSD Compiler pad library
(`mock_padlib.mdt`). Tessent will only recognize these pads as pad
cells if the Verilog port NAMES exactly match the library contract.
The port names below are MANDATORY; do NOT rename them to pad_in /
to_core / from_core / pad_out or any other synonym.

Two behavioral modules in the same section:

- `pad_input`  -- transparent input pad (pad side to core side).
  - input  port `pad_pad_io`      (connects to the chip boundary)
  - output port `pad_from_pad`    (connects to the core)
  - Body: `assign pad_from_pad = pad_pad_io;`

- `pad_output` -- tristate output pad (core side to pad side).
  - input  port `pad_to_pad`      (data in, from core)
  - input  port `pad_enable_high` (active-high output enable)
  - output port `pad_pad_io`      (connects to the chip boundary)
  - Body: `assign pad_pad_io = pad_enable_high ? pad_to_pad : 1'bz;`

These four names -- `pad_pad_io`, `pad_from_pad`, `pad_to_pad`,
`pad_enable_high` -- are the Tessent pad library contract. They are
MANDATORY for every port of `pad_input` and `pad_output`. The
chip_top instantiations in Module 4 must use these names in their
`.port_name(signal)` connections.

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
- Instantiates N_IO `pad_input` and N_IO `pad_output` modules. The
  pad instances MUST use the library-contract port names from Module 1
  (`pad_pad_io`, `pad_from_pad`, `pad_to_pad`, `pad_enable_high`) on
  their `.port(signal)` connections.
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
