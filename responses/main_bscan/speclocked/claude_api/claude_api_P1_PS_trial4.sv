```systemverilog
module pad_input (
    input  logic pad_pin,
    output logic core_data
);

    assign core_data = pad_pin;

endmodule

module pad_output (
    input  logic core_data,
    input  logic oe,
    output logic pad_pin
);

    assign pad_pin = oe ? core_data : 1'bz;

endmodule
```