```systemverilog
//-----------------------------------------------------------------------------
// Module      : bsc_cell
// Description : IEEE 1149.1 BC_1 boundary scan cell.
//               - Capture FF (posedge TCK):
//                   * capture_dr : sample functional data_in
//                   * shift_dr   : shift in serial_in (capture_dr has
//                                  priority per IEEE 1149.1)
//               - Update FF (negedge TCK):
//                   * update_dr  : latch capture FF into update FF
//               - serial_out drives the scan chain from the capture FF.
//               - Output mux selects between functional data_in and the
//                 update FF based on the mode (EXTEST/SAMPLE) signal.
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

    // Capture (shift) register - clocked on rising edge of TCK
    logic capture_reg;

    // Update (parallel hold) register - clocked on falling edge of TCK
    logic update_reg;

    //-------------------------------------------------------------------------
    // Capture / Shift register
    // Per IEEE 1149.1 BC_1:
    //   - When capture_dr is asserted, the cell samples the system data_in.
    //   - Otherwise, when shift_dr is asserted, the cell shifts serial_in
    //     into the capture register (and out via serial_out).
    //   - When neither is asserted, the register holds its value.
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
    // Update register
    // Latches the capture register on the falling edge of TCK when
    // update_dr is asserted. The negedge timing prevents races with the
    // capture/shift register that updates on the rising edge.
    //-------------------------------------------------------------------------
    always_ff @(negedge tck) begin
        if (update_dr) begin
            update_reg <= capture_reg;
        end
    end

    //-------------------------------------------------------------------------
    // Scan chain output: always reflects the capture/shift register.
    //-------------------------------------------------------------------------
    assign serial_out = capture_reg;

    //-------------------------------------------------------------------------
    // Functional output mux:
    //   mode = 0 : transparent (data_out = data_in) - normal operation/SAMPLE
    //   mode = 1 : driven by update register        - EXTEST / boundary drive
    //-------------------------------------------------------------------------
    assign data_out = mode ? update_reg : data_in;

endmodule : bsc_cell
```
