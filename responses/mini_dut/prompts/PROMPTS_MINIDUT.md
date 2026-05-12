# Mini-DUT Spec-Locked Prompts

## PS_TAP -- tap_fsm (spec-locked, mini-DUT)

Generate a SystemVerilog module called `tap_fsm` implementing ONLY the
IEEE 1149.1 TAP controller state machine. This mini-DUT has no
instruction register, no data registers, no boundary-scan chain, no
TDI/TDO, no IDCODE/BYPASS/BSR logic. It is strictly the 16-state FSM
plus output decodes.

Requirements:
- 16-state FSM (Test-Logic-Reset, Run-Test-Idle, Select-DR, Capture-DR,
  Shift-DR, Exit1-DR, Pause-DR, Exit2-DR, Update-DR, Select-IR,
  Capture-IR, Shift-IR, Exit1-IR, Pause-IR, Exit2-IR, Update-IR) with
  the canonical IEEE 1149.1 TMS transition table.
- State register clocks on posedge TCK; async active-low TRST_N forces
  the state to Test-Logic-Reset.
- Expose the current state as a 4-bit encoded output `state[3:0]`. Any
  encoding is acceptable as long as it is a pure function of the
  current FSM state.
- Expose one-hot state-decode strobes:
    * `shift_dr`   = 1 iff current state == Shift-DR
    * `capture_dr` = 1 iff current state == Capture-DR
    * `update_dr`  = 1 iff current state == Update-DR
    * `shift_ir`   = 1 iff current state == Shift-IR
    * `capture_ir` = 1 iff current state == Capture-IR
    * `update_ir`  = 1 iff current state == Update-IR
  All six strobes are 0 in every other state.

Target ~60-100 lines, synthesizable SystemVerilog. Return ONLY
SystemVerilog code in a single ```systemverilog``` code block. No prose
outside the code block.

PORT CONTRACT (MANDATORY - non-negotiable):
The module MUST declare exactly these ports, with exactly these names,
directions, and widths. Do not rename. Do not add extra ports. Do not
reorder. Any deviation makes the response invalid.

  module tap_fsm (
      input  logic       tck,
      input  logic       tms,
      input  logic       trst_n,
      output logic [3:0] state,
      output logic       shift_dr,
      output logic       capture_dr,
      output logic       update_dr,
      output logic       shift_ir,
      output logic       capture_ir,
      output logic       update_ir
  );
