```systemverilog
// IEEE 1149.1 boundary scan subsystem pad models
// SystemVerilog IEEE 1800-2017, synthesizable behavioral models

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
    // Tristate output: drive core_data when enabled, otherwise high-Z
    assign pad_pin = oe ? core_data : 1'bz;
endmodule
```
