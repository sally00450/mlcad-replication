

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

    // Capture register (shift register) - clocked on posedge TCK
    logic capture_reg;

    // Update register - latched on negedge TCK
    logic update_reg;

    // Capture/Shift register logic (posedge TCK)
    always_ff @(posedge tck) begin
        if (capture_dr) begin
            capture_reg <= data_in;
        end else if (shift_dr) begin
            capture_reg <= serial_in;
        end
    end

    // Update register logic (negedge TCK)
    always_ff @(negedge tck) begin
        if (update_dr) begin
            update_reg <= capture_reg;
        end
    end

    // Serial output is always the capture register
    assign serial_out = capture_reg;

    // Output mux: mode selects between normal data and boundary scan data
    assign data_out = mode ? update_reg : data_in;

endmodule
```