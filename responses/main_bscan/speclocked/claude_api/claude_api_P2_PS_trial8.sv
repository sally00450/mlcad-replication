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

    logic capture_reg;
    logic update_reg;

    // Capture/Shift register on posedge TCK
    always_ff @(posedge tck) begin
        if (capture_dr)
            capture_reg <= data_in;
        else if (shift_dr)
            capture_reg <= serial_in;
    end

    // Update register on negedge TCK
    always_ff @(negedge tck) begin
        if (update_dr)
            update_reg <= capture_reg;
    end

    // Serial output reflects capture register
    assign serial_out = capture_reg;

    // Output mux selects between functional data and update register
    assign data_out = mode ? update_reg : data_in;

endmodule
```