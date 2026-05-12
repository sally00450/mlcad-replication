

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

  // ---------------------------------------------------------------
  // Instruction codes
  // ---------------------------------------------------------------
  localparam logic [3:0] EXTEST = 4'b0010;
  localparam logic [3:0] SAMPLE = 4'b0011;
  localparam logic [3:0] CLAMP  = 4'b0110;
  localparam logic [3:0] UTDR   = 4'b0111;
  localparam logic [3:0] IDCODE = 4'b1110;
  localparam logic [3:0] BYPASS = 4'b1111;

  // ---------------------------------------------------------------
  // FSM state encoding
  // ---------------------------------------------------------------
  typedef enum logic [3:0] {
    TEST_LOGIC_RESET = 4'h0,
    RUN_TEST_IDLE    = 4'h1,
    SELECT_DR        = 4'h2,
    CAPTURE_DR       = 4'h3,
    SHIFT_DR         = 4'h4,
    EXIT1_DR         = 4'h5,
    PAUSE_DR         = 4'h6,
    EXIT2_DR         = 4'h7,
    UPDATE_DR        = 4'h8,
    SELECT_IR        = 4'h9,
    CAPTURE_IR       = 4'hA,
    SHIFT_IR         = 4'hB,
    EXIT1_IR         = 4'hC,
    PAUSE_IR         = 4'hD,
    EXIT2_IR         = 4'hE,
    UPDATE_IR        = 4'hF
  } tap_state_t;

  tap_state_t state, next_state;

  // ---------------------------------------------------------------
  // Next-state logic (purely combinational)
  // ---------------------------------------------------------------
  always_comb begin
    case (state)
      TEST_LOGIC_RESET: next_state = tms ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
      RUN_TEST_IDLE:    next_state = tms ? SELECT_DR        : RUN_TEST_IDLE;
      SELECT_DR:        next_state = tms ? SELECT_IR        : CAPTURE_DR;
      CAPTURE_DR:       next_state = tms ? EXIT1_DR         : SHIFT_DR;
      SHIFT_DR:         next_state = tms ? EXIT1_DR         : SHIFT_DR;
      EXIT1_DR:         next_state = tms ? UPDATE_DR        : PAUSE_DR;
      PAUSE_DR:         next_state = tms ? EXIT2_DR         : PAUSE_DR;
      EXIT2_DR:         next_state = tms ? UPDATE_DR        : SHIFT_DR;
      UPDATE_DR:        next_state = tms ? SELECT_DR        : RUN_TEST_IDLE;
      SELECT_IR:        next_state = tms ? TEST_LOGIC_RESET : CAPTURE_IR;
      CAPTURE_IR:       next_state = tms ? EXIT1_IR         : SHIFT_IR;
      SHIFT_IR:         next_state = tms ? EXIT1_IR         : SHIFT_IR;
      EXIT1_IR:         next_state = tms ? UPDATE_IR        : PAUSE_IR;
      PAUSE_IR:         next_state = tms ? EXIT2_IR         : PAUSE_IR;
      EXIT2_IR:         next_state = tms ? UPDATE_IR        : SHIFT_IR;
      UPDATE_IR:        next_state = tms ? SELECT_DR        : RUN_TEST_IDLE;
      default:          next_state = TEST_LOGIC_RESET;
    endcase
  end

  // ---------------------------------------------------------------
  // State register (posedge TCK, async reset)
  // ---------------------------------------------------------------
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n)
      state <= TEST_LOGIC_RESET;
    else
      state <= next_state;
  end

  // ---------------------------------------------------------------
  // Decode state outputs (active in their respective states)
  // ---------------------------------------------------------------
  assign shift_dr   = (state == SHIFT_DR);
  assign capture_dr = (state == CAPTURE_DR);
  assign update_dr  = (state == UPDATE_DR);
  assign shift_ir   = (state == SHIFT_IR);
  assign capture_ir = (state == CAPTURE_IR);
  assign update_ir  = (state == UPDATE_IR);

  // ---------------------------------------------------------------
  // Instruction Register (4-bit shift + holding register)
  // ---------------------------------------------------------------
  logic [3:0] ir_shift;
  logic [3:0] ir_hold;

  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      ir_shift <= IDCODE;
    end else begin
      case (state)
        CAPTURE_IR: ir_shift <= ir_hold;  // capture current IR
        SHIFT_IR:   ir_shift <= {tdi, ir_shift[3:1]};
        default:    ir_shift <= ir_shift;
      endcase
    end
  end

  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      ir_hold <= IDCODE;
    end else if (state == TEST_LOGIC_RESET) begin
      ir_hold <= IDCODE;
    end else if (state == UPDATE_IR) begin
      ir_hold <= ir_shift;
    end
  end

  assign ir_reg_out  = ir_hold;
  assign tdr_select  = (ir_hold == UTDR);

  // ---------------------------------------------------------------
  // IDCODE shift register (32-bit, preloaded with 0xDEADBEEF)
  // ---------------------------------------------------------------
  logic [31:0] idcode_reg;

  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      idcode_reg <= 32'hDEADBEEF;
    end else begin
      case (state)
        CAPTURE_DR: begin
          if (ir_hold == IDCODE)
            idcode_reg <= 32'hDEADBEEF;
        end
        SHIFT_DR: begin
          if (ir_hold == IDCODE)
            idcode_reg <= {tdi, idcode_reg[31:1]};
        end
        default: ;
      endcase
    end
  end

  // ---------------------------------------------------------------
  // BYPASS register (1-bit; also used for CLAMP)
  // ---------------------------------------------------------------
  logic bypass_reg;

  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      bypass_reg <= 1'b0;
    end else begin
      case (state)
        CAPTURE_DR: bypass_reg <= 1'b0;
        SHIFT_DR:   begin
          if (ir_hold != IDCODE && ir_hold != EXTEST &&
              ir_hold != SAMPLE && ir_hold != UTDR)
            bypass_reg <= tdi;
        end
        default: ;
      endcase
    end
  end

  // ---------------------------------------------------------------
  // TDO mux data (active in SHIFT_DR or SHIFT_IR)
  // ---------------------------------------------------------------
  logic tdo_mux;

  always_comb begin
    tdo_mux = 1'b0;
    if (state == SHIFT_DR) begin
      case (ir_hold)
        EXTEST, SAMPLE: tdo_mux = bsr_tdo;
        IDCODE:         tdo_mux = idcode_reg[0];
        UTDR:           tdo_mux = tdr_tdo;
        default:        tdo_mux = bypass_reg; // BYPASS, CLAMP, others
      endcase
    end else if (state == SHIFT_IR) begin
      tdo_mux = ir_shift[0];
    end
  end

  // ---------------------------------------------------------------
  // TDO output register (negedge TCK) + enable
  // ---------------------------------------------------------------
  logic tdo_reg;
  logic tdo_en_reg;

  always_ff @(negedge tck or negedge trst_n) begin
    if (!trst_n) begin
      tdo_reg    <= 1'b0;
      tdo_en_reg <= 1'b0;
    end else begin
      tdo_reg    <= tdo_mux;
      tdo_en_reg <= (state == SHIFT_DR) || (state == SHIFT_IR);
    end
  end

  assign tdo    = tdo_reg;
  assign tdo_en = tdo_en_reg;

endmodule
```