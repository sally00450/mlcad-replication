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

  // TAP Controller States
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
  } tap_state_t;

  tap_state_t state_q, state_d;

  // Instructions
  localparam logic [3:0] EXTEST = 4'b0010;
  localparam logic [3:0] SAMPLE = 4'b0011;
  localparam logic [3:0] CLAMP  = 4'b0110;
  localparam logic [3:0] UTDR   = 4'b0111;
  localparam logic [3:0] IDCODE = 4'b1110;
  localparam logic [3:0] BYPASS = 4'b1111;

  // Internal Registers
  logic [3:0]  ir_reg_q;
  logic [3:0]  ir_sr_q;
  logic [31:0] idcode_sr_q;
  logic        bypass_reg_q;

  // Next State Logic
  always_comb begin
    state_d = state_q;
    case (state_q)
      TEST_LOGIC_RESET: state_d = tms ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
      RUN_TEST_IDLE:    state_d = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
      SELECT_DR_SCAN:   state_d = tms ? SELECT_IR_SCAN   : CAPTURE_DR;
      CAPTURE_DR:       state_d = tms ? EXIT1_DR         : SHIFT_DR;
      SHIFT_DR:         state_d = tms ? EXIT1_DR         : SHIFT_DR;
      EXIT1_DR:         state_d = tms ? UPDATE_DR        : PAUSE_DR;
      PAUSE_DR:         state_d = tms ? EXIT2_DR         : PAUSE_DR;
      EXIT2_DR:         state_d = tms ? UPDATE_DR        : SHIFT_DR;
      UPDATE_DR:        state_d = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
      SELECT_IR_SCAN:   state_d = tms ? TEST_LOGIC_RESET : CAPTURE_IR;
      CAPTURE_IR:       state_d = tms ? EXIT1_IR         : SHIFT_IR;
      SHIFT_IR:         state_d = tms ? EXIT1_IR         : SHIFT_IR;
      EXIT1_IR:         state_d = tms ? UPDATE_IR        : PAUSE_IR;
      PAUSE_IR:         state_d = tms ? EXIT2_IR         : PAUSE_IR;
      EXIT2_IR:         state_d = tms ? UPDATE_IR        : SHIFT_IR;
      UPDATE_IR:        state_d = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
      default:          state_d = TEST_LOGIC_RESET;
    endcase
  end

  // State Register (posedge TCK)
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      state_q <= TEST_LOGIC_RESET;
    end else begin
      state_q <= state_d;
    end
  end

  // Output Decodes
  assign shift_dr   = (state_q == SHIFT_DR);
  assign capture_dr = (state_q == CAPTURE_DR);
  assign update_dr  = (state_q == UPDATE_DR);
  assign shift_ir   = (state_q == SHIFT_IR);
  assign capture_ir = (state_q == CAPTURE_IR);
  assign update_ir  = (state_q == UPDATE_IR);

  assign ir_reg_out = ir_reg_q;
  assign tdr_select = (ir_reg_q == UTDR);

  // Instruction Register
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      ir_reg_q <= IDCODE;
      ir_sr_q  <= 4'b0001; // Capture-IR typically loads 01
    end else begin
      if (state_q == TEST_LOGIC_RESET) begin
        ir_reg_q <= IDCODE;
      end else if (state_q == CAPTURE_IR) begin
        ir_sr_q <= 4'b0001;
      end else if (state_q == SHIFT_IR) begin
        ir_sr_q <= {tdi, ir_sr_q[3:1]};
      end else if (state_q == UPDATE_IR) begin
        ir_reg_q <= ir_sr_q;
      end
    end
  end

  // Data Registers
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      idcode_sr_q  <= 32'hDEADBEEF;
      bypass_reg_q <= 1'b0;
    end else begin
      if (state_q == CAPTURE_DR) begin
        if (ir_reg_q == IDCODE) begin
          idcode_sr_q <= 32'hDEADBEEF;
        end
        bypass_reg_q <= 1'b0;
      end else if (state_q == SHIFT_DR) begin
        if (ir_reg_q == IDCODE) begin
          idcode_sr_q <= {tdi, idcode_sr_q[31:1]};
        end else begin
          bypass_reg_q <= tdi;
        end
      end
    end
  end

  // TDO Logic (negedge TCK)
  logic tdo_d;
  logic tdo_en_d;

  always_comb begin
    tdo_d    = 1'b0;
    tdo_en_d = 1'b0;

    if (state_q == SHIFT_IR) begin
      tdo_d    = ir_sr_q[0];
      tdo_en_d = 1'b1;
    end else if (state_q == SHIFT_DR) begin
      tdo_en_d = 1'b1;
      case (ir_reg_q)
        EXTEST, SAMPLE: tdo_d = bsr_tdo;
        IDCODE:         tdo_d = idcode_sr_q[0];
        UTDR:           tdo_d = tdr_tdo;
        default:        tdo_d = bypass_reg_q;
      endcase
    end
  end

  always_ff @(negedge tck or negedge trst_n) begin
    if (!trst_n) begin
      tdo    <= 1'b0;
      tdo_en <= 1'b0;
    end else begin
      tdo    <= tdo_d;
      tdo_en <= tdo_en_d;
    end
  end

endmodule
```
