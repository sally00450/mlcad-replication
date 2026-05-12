```systemverilog
//-----------------------------------------------------------------------------
// Module      : bsc_cell
// Description : IEEE 1149.1 BC_1 boundary scan cell.
//
//   - Capture flop loads system data_in when capture_dr is asserted,
//     otherwise shifts serial_in when shift_dr is asserted (posedge TCK).
//   - Update flop latches the capture flop on negedge TCK when update_dr.
//   - serial_out always reflects the capture flop (scan chain output).
//   - data_out is a mux: mode=0 -> transparent (data_in),
//                        mode=1 -> driven by update_reg (test value).
//-----------------------------------------------------------------------------
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

    // Internal state
    logic capture_reg;
    logic update_reg;

    //-------------------------------------------------------------------------
    // Capture / Shift register (posedge TCK)
    // capture_dr has priority over shift_dr per BC_1 definition.
    //-------------------------------------------------------------------------
    always_ff @(posedge tck) begin
        if (capture_dr) begin
            capture_reg <= data_in;
        end
        else if (shift_dr) begin
            capture_reg <= serial_in;
        end
    end

    //-------------------------------------------------------------------------
    // Update register (negedge TCK)
    // Latches the capture register so the system output is stable while
    // the next pattern is being shifted in on the rising edge of TCK.
    //-------------------------------------------------------------------------
    always_ff @(negedge tck) begin
        if (update_dr) begin
            update_reg <= capture_reg;
        end
    end

    //-------------------------------------------------------------------------
    // Outputs
    //-------------------------------------------------------------------------
    // Scan-chain serial output is the capture flop.
    assign serial_out = capture_reg;

    // System output mux:
    //   mode = 0 : normal operation, pass data_in straight through.
    //   mode = 1 : test mode, drive system output from update_reg.
    assign data_out = mode ? update_reg : data_in;

endmodule
```
