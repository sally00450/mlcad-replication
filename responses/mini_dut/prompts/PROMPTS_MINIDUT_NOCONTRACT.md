# Mini-DUT No-Contract Prompts

## PS_TAP -- tap_fsm (no port contract, mini-DUT)

Generate a SystemVerilog module called `tap_fsm` implementing ONLY the
IEEE 1149.1 TAP controller state machine. This mini-DUT has no
instruction register, no data registers, no boundary-scan chain, no
serial data in/out, no IDCODE/BYPASS/BSR logic. It is strictly the
16-state FSM plus output decodes.

Requirements:
- 16-state FSM (Test-Logic-Reset, Run-Test-Idle, Select-DR, Capture-DR,
  Shift-DR, Exit1-DR, Pause-DR, Exit2-DR, Update-DR, Select-IR,
  Capture-IR, Shift-IR, Exit1-IR, Pause-IR, Exit2-IR, Update-IR) with
  the canonical IEEE 1149.1 mode-select transition table.
- The state register must advance on the rising edge of the test clock;
  an asynchronous active-low test reset forces the state to
  Test-Logic-Reset.
- Expose the current state as a 4-bit encoded output. Any encoding is
  acceptable as long as it is a pure function of the current FSM state.
- Expose one-hot state-decode strobes, one per each of these six states:
    * Shift-DR
    * Capture-DR
    * Update-DR
    * Shift-IR
    * Capture-IR
    * Update-IR
  Each strobe must be 1 iff the FSM is in the corresponding state, and
  0 in every other state.

Target ~60-100 lines, synthesizable SystemVerilog. Return ONLY
SystemVerilog code in a single ```systemverilog``` code block. No prose
outside the code block.
