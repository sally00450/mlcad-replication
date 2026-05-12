```systemverilog
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

  // --------------------------------------------------------------------------
  // TAP FSM: 16 states per IEEE 1149.1
  // --------------------------------------------------------------------------
  typedef enum logic [3:0] {
    TEST_LOGIC_RESET = 4'h0,
    RUN_TEST_IDLE    = 4'h1,
    SELECT_DR_SCAN   = 4'h2,
    CAPTURE_DR       = 4'h3,
    SHIFT_DR_S       = 4'h4,
    EXIT1_DR         = 4'h5,
    PAUSE_DR         = 4'h6,
    EXIT2_DR         = 4'h7,
    UPDATE_DR_S      = 4'h8,
    SELECT_IR_SCAN   = 4'h9,
    CAPTURE_IR       = 4'hA,
    SHIFT_IR_S       = 4'hB,
    EXIT1_IR         = 4'hC,
    PAUSE_IR         = 4'hD,
    EXIT2_IR         = 4'hE,
    UPDATE_IR_S      = 4'hF
  } tap_state_e;

  tap_state_e state_q, state_d;

  // --------------------------------------------------------------------------
  // Instructions (4-bit)
  // --------------------------------------------------------------------------
  localparam logic [3:0] IR_EXTEST = 4'b0010;
  localparam logic [3:0] IR_SAMPLE = 4'b0011;
  localparam logic [3:0] IR_CLAMP  = 4'b0110;
  localparam logic [3:0] IR_UTDR   = 4'b0111;
  localparam logic [3:0] IR_IDCODE = 4'b1110;
  localparam logic [3:0] IR_BYPASS = 4'b1111;

  // Holding IR and shift IR
  logic [3:0] ir_q, ir_d;
  logic [3:0] ir_shift_q, ir_shift_d;

  // DRs: IDCODE (32-bit) and BYPASS (1-bit, also for CLAMP)
  logic [31:0] idcode_shift_q, idcode_shift_d;
  logic        bypass_q, bypass_d;

  // --------------------------------------------------------------------------
  // Next-state logic (combinational)
  // --------------------------------------------------------------------------
  always_comb begin
    state_d = state_q;
    unique case (state_q)
      TEST_LOGIC_RESET: state_d = (tms) ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
      RUN_TEST_IDLE:    state_d = (tms) ? SELECT_DR_SCAN   : RUN_TEST_IDLE;

      SELECT_DR_SCAN:   state_d = (tms) ? SELECT_IR_SCAN   : CAPTURE_DR;
      CAPTURE_DR:       state_d = (tms) ? EXIT1_DR         : SHIFT_DR_S;
      SHIFT_DR_S:       state_d = (tms) ? EXIT1_DR         : SHIFT_DR_S;
      EXIT1_DR:         state_d = (tms) ? UPDATE_DR_S      : PAUSE_DR;
      PAUSE_DR:         state_d = (tms) ? EXIT2_DR         : PAUSE_DR;
      EXIT2_DR:         state_d = (tms) ? UPDATE_DR_S      : SHIFT_DR_S;
      UPDATE_DR_S:      state_d = (tms) ? SELECT_DR_SCAN   : RUN_TEST_IDLE;

      SELECT_IR_SCAN:   state_d = (tms) ? TEST_LOGIC_RESET : CAPTURE_IR;
      CAPTURE_IR:       state_d = (tms) ? EXIT1_IR         : SHIFT_IR_S;
      SHIFT_IR_S:       state_d = (tms) ? EXIT1_IR         : SHIFT_IR_S;
      EXIT1_IR:         state_d = (tms) ? UPDATE_IR_S      : PAUSE_IR;
      PAUSE_IR:         state_d = (tms) ? EXIT2_IR         : PAUSE_IR;
      EXIT2_IR:         state_d = (tms) ? UPDATE_IR_S      : SHIFT_IR_S;
      UPDATE_IR_S:      state_d = (tms) ? SELECT_DR_SCAN   : RUN_TEST_IDLE;

      default:          state_d = TEST_LOGIC_RESET;
    endcase
  end

  // --------------------------------------------------------------------------
  // State register with async reset to Test-Logic-Reset
  // --------------------------------------------------------------------------
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      state_q <= TEST_LOGIC_RESET;
    end else begin
      state_q <= state_d;
    end
  end

  // --------------------------------------------------------------------------
  // IR/DR sequential logic
  // - After TRST_N, IR defaults to IDCODE.
  // - IR shifts during SHIFT_IR; latched at UPDATE_IR.
  // - IDCODE shift register loads 32'hDEADBEEF at CAPTURE_DR when selected.
  // - BYPASS reg captures 0 at CAPTURE_DR when selected, shifts during SHIFT_DR.
  // --------------------------------------------------------------------------
  always_comb begin
    ir_d           = ir_q;
    ir_shift_d     = ir_shift_q;
    idcode_shift_d = idcode_shift_q;
    bypass_d       = bypass_q;

    // IR shift path
    if (state_q == CAPTURE_IR) begin
      // Per common JTAG behavior, capture a fixed pattern in LSBs (01).
      // Keep current instruction in upper bits for predictable behavior.
      ir_shift_d = {ir_q[3:2], 2'b01};
    end
    if (state_q == SHIFT_IR_S) begin
      ir_shift_d = {tdi, ir_shift_q[3:1]};
    end
    if (state_q == UPDATE_IR_S) begin
      ir_d = ir_shift_q;
    end

    // DR capture/shift for IDCODE and BYPASS/CLAMP
    if (state_q == CAPTURE_DR) begin
      if (ir_q == IR_IDCODE) begin
        idcode_shift_d = 32'hDEADBEEF;
      end else begin
        // For BYPASS/CLAMP and any unspecified DR, capture 0
        bypass_d = 1'b0;
      end
    end
    if (state_q == SHIFT_DR_S) begin
      if (ir_q == IR_IDCODE) begin
        idcode_shift_d = {tdi, idcode_shift_q[31:1]};
      end else begin
        // BYPASS reg is used for BYPASS and CLAMP and all other "otherwise" cases
        bypass_d = tdi;
      end
    end
  end

  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      ir_q           <= IR_IDCODE;
      ir_shift_q     <= IR_IDCODE;
      idcode_shift_q <= 32'hDEADBEEF;
      bypass_q       <= 1'b0;
    end else begin
      ir_q           <= ir_d;
      ir_shift_q     <= ir_shift_d;
      idcode_shift_q <= idcode_shift_d;
      bypass_q       <= bypass_d;
    end
  end

  // --------------------------------------------------------------------------
  // Outputs: decode states
  // --------------------------------------------------------------------------
  always_comb begin
    shift_dr   = (state_q == SHIFT_DR_S);
    capture_dr = (state_q == CAPTURE_DR);
    update_dr  = (state_q == UPDATE_DR_S);

    shift_ir   = (state_q == SHIFT_IR_S);
    capture_ir = (state_q == CAPTURE_IR);
    update_ir  = (state_q == UPDATE_IR_S);

    tdo_en     = shift_dr | shift_ir;

    tdr_select = (ir_q == IR_UTDR);

    ir_reg_out = ir_q;
  end

  // --------------------------------------------------------------------------
  // TDO launched on negedge TCK
  // - SHIFT_IR: output IR shift reg LSB
  // - SHIFT_DR: select by current instruction
  // --------------------------------------------------------------------------
  always_ff @(negedge tck or negedge trst_n) begin
    if (!trst_n) begin
      tdo <= 1'b0;
    end else begin
      if (state_q == SHIFT_IR_S) begin
        tdo <= ir_shift_q[0];
      end else if (state_q == SHIFT_DR_S) begin
        unique case (ir_q)
          IR_EXTEST,
          IR_SAMPLE: tdo <= bsr_tdo;

          IR_IDCODE: tdo <= idcode_shift_q[0];

          IR_UTDR:   tdo <= tdr_tdo;

          default:   tdo <= bypass_q; // includes BYPASS and CLAMP
        endcase
      end else begin
        tdo <= tdo; // hold last value when not shifting
      end
    end
  end

endmodule
```
