# Multi-LLM BSCAN Benchmark -- Real-Port Bundled Prompt (PB'')

## Purpose

This file defines the real-port bundled prompt PB'' (read "PB double-
prime"). It is identical to PB (see PROMPTS_BUNDLED.md) except for one
substituted constraint: the port names of `pad_input`, `pad_output`,
`bsc_cell`, and `tap_controller` MUST match the REAL VCS fixture port
contract used by the per-module PS prompts (see PROMPTS_SPECLOCKED.md),
verbatim. This replaces the Tessent pad-library attribute-tag token
guidance of PB' (pad_pad_io, pad_from_pad, pad_to_pad, pad_enable_high)
with the "normal" engineer-facing names (pad_pin, core_data, oe, etc.).

PB'' answers the reviewer question: what happens on the Tessent side
when a bundled prompt is given the same real-port contract that PS used
on VCS, instead of the library-attribute-tag tokens that PB' used? That
is: is the Layer-3 Tessent ELAB failure deeper than port-name prompting,
or is it just that we named the wrong ports in PB'?

Everything else -- the four-module structure, BSR layout, IR encoding,
TAP FSM, N_IO=10, response format -- is unchanged from PB.

Repeat PB'' 3 times per model (fresh session each).
  - Claude Opus 4.7 (Bedrock API, us.anthropic.claude-opus-4-7)
  - Claude Opus 4.6 (Bedrock API, us.anthropic.claude-opus-4-6-v1)
Target: 1 prompt x 2 models x 3 trials = 6 responses.

---

## PB'' -- Real-Port Bundled 4-module chip_top

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

### PORT CONTRACT (MANDATORY -- non-negotiable, applies to all modules)

All four modules (`pad_input`, `pad_output`, `bsc_cell`,
`tap_controller`) MUST declare exactly these ports, with exactly these
names, directions, and widths. Do not rename. Do not add extra ports.
Do not reorder. Do not substitute synonyms. Any deviation makes the
response invalid. The chip_top instantiations (Module 4) MUST use these
names in their `.port_name(signal)` connections.

  module pad_input (
      input  logic pad_pin,
      output logic core_data
  );

  module pad_output (
      input  logic core_data,
      input  logic oe,
      output logic pad_pin
  );

  module bsc_cell (
      input  logic tck,
      input  logic shift_dr,
      input  logic capture_dr,
      input  logic update_dr,
      input  logic mode,
      input  logic serial_in,
      output logic serial_out,
      input  logic data_in,
      output logic data_out
  );

  module tap_controller (
      input  logic        tck,
      input  logic        tms,
      input  logic        tdi,
      input  logic        trst_n,
      output logic        tdo,
      output logic        tdo_en,
      output logic        shift_dr,
      output logic        capture_dr,
      output logic        update_dr,
      output logic        shift_ir,
      output logic        capture_ir,
      output logic        update_ir,
      input  logic        bsr_tdo,
      input  logic        tdr_tdo,
      output logic        tdr_select,
      output logic [3:0]  ir_reg_out
  );

### Module 1 -- pad_cell

Two behavioral modules in the same section, using the PORT CONTRACT
above verbatim:

- `pad_input`:  transparent input. Body: `assign core_data = pad_pin;`
- `pad_output`: tristate output.
                Body: `assign pad_pin = oe ? core_data : 1'bz;`

No process library cells. Approx 30-40 lines.

### Module 2 -- bsc_cell

BC_1 boundary scan cell, using the PORT CONTRACT above verbatim (ports
are `tck, shift_dr, capture_dr, update_dr, mode, serial_in, serial_out,
data_in, data_out`; no `parallel_in`/`parallel_out`, no `trst_n` on
this module).

Behavior:
- posedge TCK: if capture_dr, capture_reg <= data_in;
               else if shift_dr, capture_reg <= serial_in.
- negedge TCK: if update_dr, update_reg <= capture_reg.
- serial_out = capture_reg.
- Output mux: data_out = mode ? update_reg : data_in.

Approx 60-80 lines.

### Module 3 -- tap_controller

Full IEEE 1149.1 TAP controller, using the PORT CONTRACT above
verbatim.

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
- TDO output: launched on NEGEDGE TCK. During SHIFT_DR select TDO
  source:
    * `bsr_tdo`                       when ir == EXTEST or SAMPLE
    * IDCODE shift reg                when ir == IDCODE
    * `tdr_tdo`                       when ir == UTDR
    * BYPASS                          otherwise
  During SHIFT_IR, TDO = IR shift register LSB.
- `tdr_select` asserted when current instruction == UTDR.
- `ir_reg_out` = 4-bit current (holding) IR value.
- `tdo_en` asserted on SHIFT_DR / SHIFT_IR states.

Approx 250 lines.

### Module 4 -- chip_top

Integration module. Parameter N_IO=10 (so 30 BSCs, 20 pads).

- Top-level ports:
    input  tck, tms, tdi, trst_n
    output tdo
    input  [N_IO-1:0] chip_in
    output [N_IO-1:0] chip_out   (tristate)

- Instantiates one `tap_controller`. Use the tap_controller PORT
  CONTRACT port names above in the `.name(sig)` connections.
- Instantiates 3*N_IO `bsc_cell`s in the BSR chain, layout:
    BSC[0..N_IO-1]          input-data   (data_in = input-pad core side)
    BSC[N_IO..2*N_IO-1]     output-data  (data_in = core_out)
    BSC[2*N_IO..3*N_IO-1]   output-OE    (data_in = core_oe)
  Use the bsc_cell PORT CONTRACT port names (`data_in`, `data_out`,
  `serial_in`, `serial_out`, etc.) in the `.name(sig)` connections.
- Instantiates N_IO `pad_input` and N_IO `pad_output` modules. The
  pad instances MUST use the PORT CONTRACT port names (`pad_pin`,
  `core_data`, `oe`) on their `.port(signal)` connections.
- BSR serial chain wiring:
    bsc_serial_chain[0]     = tdi
    bsc_serial_chain[k+1]   = bsc[k].serial_out
    bsr_tdo                 = bsc_serial_chain[3*N_IO]
- Output pad drive comes from BSC output-data cell's data_out
  (mode-muxed: EXTEST uses update_reg, normal uses core_out).
- Output pad OE comes from BSC output-OE cell's data_out.
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
