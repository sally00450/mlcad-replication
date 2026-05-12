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
  // IEEE 1149.1 TAP State Machine (16 states)
  // --------------------------------------------------------------------------
  typedef enum logic [3:0] {
    TEST_LOGIC_RESET = 4'h0,
    RUN_TEST_IDLE    = 4'h1,
    SELECT_DR_SCAN   = 4'h2,
    CAPTURE_DR       = 4'h3,
    SHIFT_DR         = 4'h4,
    EXIT1_DR         = 4'h5,
    PAUSE_DR         = 4'h6,
    EXIT2_DR         = 4'h7,
    UPDATE_DR        = 4'h8,
    SELECT_IR_SCAN   = 4'h9,
    CAPTURE_IR       = 4'hA,
    SHIFT_IR         = 4'hB,
    EXIT1_IR         = 4'hC,
    PAUSE_IR         = 4'hD,
    EXIT2_IR         = 4'hE,
    UPDATE_IR        = 4'hF
  } tap_state_e;

  tap_state_e state_q, state_d;

  // --------------------------------------------------------------------------
  // Instruction opcodes (4-bit)
  // --------------------------------------------------------------------------
  localparam logic [3:0] IR_EXTEST = 4'b0010;
  localparam logic [3:0] IR_SAMPLE = 4'b0011;
  localparam logic [3:0] IR_CLAMP  = 4'b0110;
  localparam logic [3:0] IR_UTDR   = 4'b0111;
  localparam logic [3:0] IR_IDCODE = 4'b1110;
  localparam logic [3:0] IR_BYPASS = 4'b1111;

  // --------------------------------------------------------------------------
  // IR registers: shift and holding
  // --------------------------------------------------------------------------
  logic [3:0] ir_shift_q, ir_shift_d;
  logic [3:0] ir_hold_q,  ir_hold_d;

  // --------------------------------------------------------------------------
  // DR registers: IDCODE and BYPASS
  // --------------------------------------------------------------------------
  logic [31:0] idcode_shift_q, idcode_shift_d;
  logic        bypass_q,       bypass_d;

  // --------------------------------------------------------------------------
  // Combinational next-state for TAP FSM
  // --------------------------------------------------------------------------
  always_comb begin
    state_d = state_q;
    unique case (state_q)
      TEST_LOGIC_RESET: state_d = (tms) ? TEST_LOGIC_RESET : RUN_TEST_IDLE;

      RUN_TEST_IDLE:    state_d = (tms) ? SELECT_DR_SCAN   : RUN_TEST_IDLE;

      SELECT_DR_SCAN:   state_d = (tms) ? SELECT_IR_SCAN   : CAPTURE_DR;

      CAPTURE_DR:       state_d = (tms) ? EXIT1_DR         : SHIFT_DR;

      SHIFT_DR:         state_d = (tms) ? EXIT1_DR         : SHIFT_DR;

      EXIT1_DR:         state_d = (tms) ? UPDATE_DR        : PAUSE_DR;

      PAUSE_DR:         state_d = (tms) ? EXIT2_DR         : PAUSE_DR;

      EXIT2_DR:         state_d = (tms) ? UPDATE_DR        : SHIFT_DR;

      UPDATE_DR:        state_d = (tms) ? SELECT_DR_SCAN   : RUN_TEST_IDLE;

      SELECT_IR_SCAN:   state_d = (tms) ? TEST_LOGIC_RESET : CAPTURE_IR;

      CAPTURE_IR:       state_d = (tms) ? EXIT1_IR         : SHIFT_IR;

      SHIFT_IR:         state_d = (tms) ? EXIT1_IR         : SHIFT_IR;

      EXIT1_IR:         state_d = (tms) ? UPDATE_IR        : PAUSE_IR;

      PAUSE_IR:         state_d = (tms) ? EXIT2_IR         : PAUSE_IR;

      EXIT2_IR:         state_d = (tms) ? UPDATE_IR        : SHIFT_IR;

      UPDATE_IR:        state_d = (tms) ? SELECT_DR_SCAN   : RUN_TEST_IDLE;

      default:          state_d = TEST_LOGIC_RESET;
    endcase
  end

  // --------------------------------------------------------------------------
  // State register with async reset
  // --------------------------------------------------------------------------
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      state_q <= TEST_LOGIC_RESET;
    end else begin
      state_q <= state_d;
    end
  end

  // --------------------------------------------------------------------------
  // Output decodes for TAP states
  // --------------------------------------------------------------------------
  always_comb begin
    shift_dr   = (state_q == SHIFT_DR);
    capture_dr = (state_q == CAPTURE_DR);
    update_dr  = (state_q == UPDATE_DR);

    shift_ir   = (state_q == SHIFT_IR);
    capture_ir = (state_q == CAPTURE_IR);
    update_ir  = (state_q == UPDATE_IR);

    tdo_en     = shift_dr | shift_ir;
  end

  // --------------------------------------------------------------------------
  // IR holding output and UTDR select
  // --------------------------------------------------------------------------
  always_comb begin
    ir_reg_out = ir_hold_q;
    tdr_select = (ir_hold_q == IR_UTDR);
  end

  // --------------------------------------------------------------------------
  // IR shifting + holding update
  // --------------------------------------------------------------------------
  always_comb begin
    ir_shift_d = ir_shift_q;
    ir_hold_d  = ir_hold_q;

    if (state_q == CAPTURE_IR) begin
      // Standard TAP capture pattern often includes "01" in LSBs; keep simple.
      ir_shift_d = 4'b0001;
    end

    if (state_q == SHIFT_IR) begin
      ir_shift_d = {tdi, ir_shift_q[3:1]};
    end

    if (state_q == UPDATE_IR) begin
      ir_hold_d = ir_shift_q;
    end
  end

  // --------------------------------------------------------------------------
  // DR shifting (IDCODE and BYPASS)
  // --------------------------------------------------------------------------
  always_comb begin
    idcode_shift_d = idcode_shift_q;
    bypass_d       = bypass_q;

    if (state_q == CAPTURE_DR) begin
      if (ir_hold_q == IR_IDCODE) begin
        idcode_shift_d = 32'hDEADBEEF;
      end else begin
        // BYPASS is used for BYPASS and also CLAMP and all other non-specified DRs
        bypass_d = 1'b0;
      end
    end

    if (state_q == SHIFT_DR) begin
      if (ir_hold_q == IR_IDCODE) begin
        idcode_shift_d = {tdi, idcode_shift_q[31:1]};
      end else begin
        bypass_d = tdi;
      end
    end
  end

  // --------------------------------------------------------------------------
  // Sequential registers with async reset (IR defaults to IDCODE)
  // --------------------------------------------------------------------------
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      ir_shift_q     <= IR_IDCODE;
      ir_hold_q      <= IR_IDCODE;
      idcode_shift_q <= 32'hDEADBEEF;
      bypass_q       <= 1'b0;
    end else begin
      ir_shift_q     <= ir_shift_d;
      ir_hold_q      <= ir_hold_d;
      idcode_shift_q <= idcode_shift_d;
      bypass_q       <= bypass_d;
    end
  end

  // --------------------------------------------------------------------------
  // TDO launch on negedge TCK
  // --------------------------------------------------------------------------
  always_ff @(negedge tck or negedge trst_n) begin
    if (!trst_n) begin
      tdo <= 1'b0;
    end else begin
      if (state_q == SHIFT_IR) begin
        tdo <= ir_shift_q[0];
      end else if (state_q == SHIFT_DR) begin
        unique case (ir_hold_q)
          IR_EXTEST,
          IR_SAMPLE: tdo <= bsr_tdo;
          IR_IDCODE: tdo <= idcode_shift_q[0];
          IR_UTDR:   tdo <= tdr_tdo;
          default:   tdo <= bypass_q; // includes BYPASS, CLAMP, and others
        endcase
      end else begin
        tdo <= 1'b0;
      end
    end
  end

endmodule
```
