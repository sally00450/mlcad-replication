```systemverilog
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

    //========================================================================
    // Internal Signals
    //========================================================================
    logic capture_reg;
    logic update_reg;

    //========================================================================
    // Capture / Shift Stage
    // Triggered on the rising edge of TCK.
    // Captures data_in if capture_dr is asserted.
    // Shifts serial_in if shift_dr is asserted and capture_dr is not.
    //========================================================================
    always_ff @(posedge tck) begin
        if (capture_dr) begin
            capture_reg <= data_in;
        end else if (shift_dr) begin
            capture_reg <= serial_in;
        end
    end

    //========================================================================
    // Update Stage
    // Triggered on the falling edge of TCK.
    // Latches the value from the capture register if update_dr is asserted.
    //========================================================================
    always_ff @(negedge tck) begin
        if (update_dr) begin
            update_reg <= capture_reg;
        end
    end

    //========================================================================
    // Output Assignments
    //========================================================================
    
    // The serial output is driven directly from the capture register.
    assign serial_out = capture_reg;

    // The data output mux selects between the latched update register
    // (if mode is 1) or the incoming data_in bypass (if mode is 0).
    assign data_out = mode ? update_reg : data_in;

endmodule
```
