# Spec-Locked Prompts (PS) — Port-Contract-Mandated Variants of P1/P2/P3

## How to use

These are the PS variants of P1/P2/P3. Each is the original prompt VERBATIM
plus an appended mandatory PORT CONTRACT section that hard-locks the exact
port names, directions, and widths expected by the reference
`chip_top`/`tb_bscan` fixture.

The reference fixture (rtl/chip_top.sv + tb/tb_bscan.sv) instantiates:
  - `pad_input`  with .pad_pin, .core_data
  - `pad_output` with .core_data, .oe, .pad_pin
  - `bsc_cell`   with .tck, .shift_dr, .capture_dr, .update_dr, .mode,
                      .serial_in, .serial_out, .data_in, .data_out
  - `tap_controller` with .tck, .tms, .tdi, .trst_n, .tdo, .tdo_en,
                          .shift_dr, .capture_dr, .update_dr,
                          .shift_ir, .capture_ir, .update_ir,
                          .bsr_tdo, .tdr_tdo, .tdr_select, .ir_reg_out

Bundle each PS prompt into a fresh API conversation. Record the FIRST
code block and save. Score with speclocked_scores.csv.

All prompts target IEEE 1149.1-2013 and SystemVerilog IEEE 1800-2017.

---

## Shared architectural context (every prompt repeats this inline)

Every prompt is self-contained with these design conventions:

- TCK is the test clock. TMS, TDI are sampled on posedge TCK.
- TDO is launched on NEGEDGE TCK (IEEE 1149.1 requirement).
- TRST_N is an asynchronous active-low reset.
- Boundary scan cells (BC_1): capture/shift on posedge TCK,
  update on negedge TCK.
- Instructions (4-bit IR):
    EXTEST=4'b0010, SAMPLE=4'b0011, CLAMP=4'b0110,
    UTDR=4'b0111, IDCODE=4'b1110, BYPASS=4'b1111
- IDCODE value: 32'hDEADBEEF.
- 8-bit TDR accessed via UTDR instruction.

---

## P1_PS -- pad_cell (spec-locked)

You are generating SystemVerilog for an IEEE 1149.1 boundary scan
subsystem. Generate a module file that provides two simple behavioral
pad models used at chip I/O:

1. `pad_input`  -- a transparent input pad. Buffers the signal from the
   chip boundary into the core.
2. `pad_output` -- a tristate output pad. When `oe=1`, the output pin
   drives the core data; when `oe=0`, the output pin is 1'bz.

Both should be behavioral (no process library cells). Target
SystemVerilog IEEE 1800-2017, synthesizable. Put both modules in one
file.

Return ONLY SystemVerilog code in a single ```systemverilog``` code
block. No prose outside the code block.

PORT CONTRACT (MANDATORY - non-negotiable):
The modules MUST declare exactly these ports, with exactly these names,
directions, and widths. Do not rename. Do not add extra ports. Do not
reorder. Any deviation makes the response invalid.

  module pad_input (
      input  logic pad_pin,
      output logic core_data
  );

  module pad_output (
      input  logic core_data,
      input  logic oe,
      output logic pad_pin
  );

---

## P2_PS -- bsc_cell (spec-locked)

Generate a SystemVerilog module called `bsc_cell` implementing an IEEE
1149.1 BC_1 boundary scan cell.

Behavior:
- On posedge TCK: if capture_dr, the capture register samples data_in;
                  else if shift_dr, the capture register samples
                  serial_in.
- On negedge TCK: if update_dr, the update register latches the
  capture register.
- serial_out = capture register (always).
- Output mux: data_out = mode ? update_reg : data_in.

Target approx 60-80 lines, synthesizable SystemVerilog. Return ONLY
SystemVerilog code in a single ```systemverilog``` code block. No prose
outside the code block.

PORT CONTRACT (MANDATORY - non-negotiable):
The module MUST declare exactly these ports, with exactly these names,
directions, and widths. Do not rename (no "parallel_in"/"parallel_out",
no "si"/"so" — use data_in/data_out and serial_in/serial_out). Do not
add extra ports. Do not reorder. Any deviation makes the response
invalid.

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

---

## P3_PS -- tap_controller (spec-locked)

Generate a SystemVerilog module called `tap_controller` implementing the
full IEEE 1149.1 TAP controller.

Requirements:
- 16-state FSM (Test-Logic-Reset, Run-Test-Idle, Select-DR, Capture-DR,
  Shift-DR, Exit1-DR, Pause-DR, Exit2-DR, Update-DR, Select-IR,
  Capture-IR, Shift-IR, Exit1-IR, Pause-IR, Exit2-IR, Update-IR).
- State register clocks on posedge TCK; async reset TRST_N jumps to
  Test-Logic-Reset.
- 4-bit Instruction Register (IR). After TRST_N, IR defaults to IDCODE.
- 6 instructions (4-bit codes): EXTEST=0010, SAMPLE=0011, CLAMP=0110,
  UTDR=0111, IDCODE=1110, BYPASS=1111.
- Internal 32-bit IDCODE shift register holding 32'hDEADBEEF.
- Internal 1-bit BYPASS register (also used by CLAMP).
- TDO launched on NEGEDGE TCK. During SHIFT_DR select TDO source:
    * bsr_tdo when ir == EXTEST or SAMPLE
    * idcode shift reg when ir == IDCODE
    * tdr_tdo when ir == UTDR
    * bypass reg otherwise (including BYPASS, CLAMP)
  During SHIFT_IR, TDO = IR shift register LSB.
- `tdr_select` asserted when current instruction == UTDR.
- `ir_reg_out` = 4-bit current (holding) IR value.
- `tdo_en` asserted on SHIFT_DR / SHIFT_IR states.

Target approx 250 lines, synthesizable SystemVerilog. Return ONLY
SystemVerilog code in a single ```systemverilog``` code block. No prose
outside the code block.

PORT CONTRACT (MANDATORY - non-negotiable):
The module MUST declare exactly these ports, with exactly these names,
directions, and widths. Do not rename. Do not add extra ports. Do not
reorder. Any deviation makes the response invalid.

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
