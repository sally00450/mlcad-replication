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

  // ----------------------------
  // IEEE 1149.1 TAP 16-state FSM
  // ----------------------------
  typedef enum logic [3:0] {
    TEST_LOGIC_RESET = 4'd0,
    RUN_TEST_IDLE    = 4'd1,
    SELECT_DR_SCAN   = 4'd2,
    CAPTURE_DR       = 4'd3,
    SHIFT_DR         = 4'd4,
    EXIT1_DR         = 4'd5,
    PAUSE_DR         = 4'd6,
    EXIT2_DR         = 4'd7,
    UPDATE_DR        = 4'd8,
    SELECT_IR_SCAN   = 4'd9,
    CAPTURE_IR       = 4'd10,
    SHIFT_IR         = 4'd11,
    EXIT1_IR         = 4'd12,
    PAUSE_IR         = 4'd13,
    EXIT2_IR         = 4'd14,
    UPDATE_IR        = 4'd15
  } tap_state_e;

  tap_state_e state, next_state;

  // ----------------------------
  // Instruction definitions
  // ----------------------------
  localparam logic [3:0] IR_EXTEST = 4'b0010;
  localparam logic [3:0] IR_SAMPLE = 4'b0011;
  localparam logic [3:0] IR_CLAMP  = 4'b0110;
  localparam logic [3:0] IR_UTDR   = 4'b0111;
  localparam logic [3:0] IR_IDCODE = 4'b1110;
  localparam logic [3:0] IR_BYPASS = 4'b1111;

  // Holding IR and shift IR
  logic [3:0] ir_hold;
  logic [3:0] ir_shift;

  // Internal DRs
  logic [31:0] idcode_shift;
  logic        bypass_reg;

  // TDO mux preselect (combinational) and launch register (negedge)
  logic tdo_next;

  // ----------------------------
  // Next-state logic
  // ----------------------------
  always_comb begin
    next_state = state;
    unique case (state)
      TEST_LOGIC_RESET: next_state = (tms) ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
      RUN_TEST_IDLE:    next_state = (tms) ? SELECT_DR_SCAN   : RUN_TEST_IDLE;

      SELECT_DR_SCAN:   next_state = (tms) ? SELECT_IR_SCAN   : CAPTURE_DR;
      CAPTURE_DR:       next_state = (tms) ? EXIT1_DR         : SHIFT_DR;
      SHIFT_DR:         next_state = (tms) ? EXIT1_DR         : SHIFT_DR;
      EXIT1_DR:         next_state = (tms) ? UPDATE_DR        : PAUSE_DR;
      PAUSE_DR:         next_state = (tms) ? EXIT2_DR         : PAUSE_DR;
      EXIT2_DR:         next_state = (tms) ? UPDATE_DR        : SHIFT_DR;
      UPDATE_DR:        next_state = (tms) ? SELECT_DR_SCAN   : RUN_TEST_IDLE;

      SELECT_IR_SCAN:   next_state = (tms) ? TEST_LOGIC_RESET : CAPTURE_IR;
      CAPTURE_IR:       next_state = (tms) ? EXIT1_IR         : SHIFT_IR;
      SHIFT_IR:         next_state = (tms) ? EXIT1_IR         : SHIFT_IR;
      EXIT1_IR:         next_state = (tms) ? UPDATE_IR        : PAUSE_IR;
      PAUSE_IR:         next_state = (tms) ? EXIT2_IR         : PAUSE_IR;
      EXIT2_IR:         next_state = (tms) ? UPDATE_IR        : SHIFT_IR;
      UPDATE_IR:        next_state = (tms) ? SELECT_DR_SCAN   : RUN_TEST_IDLE;

      default:          next_state = TEST_LOGIC_RESET;
    endcase
  end

  // ----------------------------
  // State register with async TRST_N
  // ----------------------------
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      state <= TEST_LOGIC_RESET;
    end else begin
      state <= next_state;
    end
  end

  // ----------------------------
  // Output decode signals
  // ----------------------------
  always_comb begin
    shift_dr   = (state == SHIFT_DR);
    capture_dr = (state == CAPTURE_DR);
    update_dr  = (state == UPDATE_DR);

    shift_ir   = (state == SHIFT_IR);
    capture_ir = (state == CAPTURE_IR);
    update_ir  = (state == UPDATE_IR);

    tdo_en     = shift_dr | shift_ir;
  end

  // ----------------------------
  // IR and DR registers
  // ----------------------------
  // Capture/Shift happen on posedge TCK per JTAG convention
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      ir_hold      <= IR_IDCODE;
      ir_shift     <= IR_IDCODE;
      idcode_shift <= 32'hDEADBEEF;
      bypass_reg   <= 1'b0;
    end else begin
      // IR path
      if (state == CAPTURE_IR) begin
        // IEEE 1149.1 requires "01" in LSBs; for 4-bit IR, use 4'b0001
        ir_shift <= 4'b0001;
      end else if (state == SHIFT_IR) begin
        ir_shift <= {tdi, ir_shift[3:1]};
      end

      if (state == UPDATE_IR) begin
        ir_hold <= ir_shift;
      end

      // DR path
      if (state == CAPTURE_DR) begin
        unique case (ir_hold)
          IR_IDCODE: begin
            idcode_shift <= 32'hDEADBEEF;
          end
          default: begin
            // BYPASS and also CLAMP use bypass_reg
            bypass_reg <= 1'b0;
          end
        endcase
      end else if (state == SHIFT_DR) begin
        unique case (ir_hold)
          IR_IDCODE: begin
            idcode_shift <= {tdi, idcode_shift[31:1]};
          end
          default: begin
            bypass_reg <= tdi;
          end
        endcase
      end
      // UPDATE_DR: no internal DR update required for this controller stub
    end
  end

  // ----------------------------
  // Outputs derived from IR
  // ----------------------------
  always_comb begin
    ir_reg_out  = ir_hold;
    tdr_select  = (ir_hold == IR_UTDR);
  end

  // ----------------------------
  // TDO selection (combinational) and launch on negedge TCK
  // ----------------------------
  always_comb begin
    tdo_next = 1'b0;

    if (state == SHIFT_IR) begin
      tdo_next = ir_shift[0];
    end else if (state == SHIFT_DR) begin
      if ((ir_hold == IR_EXTEST) || (ir_hold == IR_SAMPLE)) begin
        tdo_next = bsr_tdo;
      end else if (ir_hold == IR_IDCODE) begin
        tdo_next = idcode_shift[0];
      end else if (ir_hold == IR_UTDR) begin
        tdo_next = tdr_tdo;
      end else begin
        // BYPASS, CLAMP, or any other undefined instruction
        tdo_next = bypass_reg;
      end
    end else begin
      tdo_next = 1'b0;
    end
  end

  always_ff @(negedge tck or negedge trst_n) begin
    if (!trst_n) begin
      tdo <= 1'b0;
    end else begin
      tdo <= tdo_next;
    end
  end

endmodule
```
