```systemverilog
//------------------------------------------------------------------------------
// Simple behavioral pad models (synthesizable), IEEE 1800-2017
//------------------------------------------------------------------------------

module pad_input (
    input  logic pad_pin,
    output logic core_data
);
    // Transparent input buffer from pad to core
    assign core_data = pad_pin;
endmodule

module pad_output (
    input  logic core_data,
    input  logic oe,
    output logic pad_pin
);
    // Tristate output: drive when oe=1, otherwise high-Z
    assign pad_pin = oe ? core_data : 1'bz;
endmodule
```
