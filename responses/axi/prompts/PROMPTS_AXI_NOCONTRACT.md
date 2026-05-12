# Third-DUT No-Contract Prompts (AXI4-Lite)

## PS_AXI -- axi_lite_regs (no port contract, AXI4-Lite slave)

Generate a SystemVerilog module called `axi_lite_regs` implementing a
minimal AXI4-Lite slave that hosts four 32-bit registers. The slave has
a single clock input (rising-edge) and a single asynchronous
active-low reset. All four registers reset to zero.

Requirements:
- Standard AXI4-Lite single-beat handshaking on the five channels
  (write address, write data, write response, read address, read
  data). Each valid/ready pair follows the standard AXI handshake: a
  transfer happens on a cycle where valid and ready are both high.
- Address map (byte addresses, using address bits [3:2] to select the
  word):
    * 0x00 -> register 0
    * 0x04 -> register 1
    * 0x08 -> register 2
    * 0x0C -> register 3
  Any address whose upper bits ([31:4]) are non-zero is out-of-range.
- On a write, honor the 4-bit byte-strobe per-byte: byte b of the
  addressed register is updated only when strobe bit b is 1.
  Unselected bytes keep their previous value.
- After a successful in-range write, return an OKAY write response
  (2'b00). After an out-of-range write, return a SLVERR write response
  (2'b10) and do not modify any register.
- After a successful in-range read, drive the read-data output with the
  register contents and an OKAY read response. After an out-of-range
  read, drive read-data zero and a read response that is either OKAY
  or SLVERR; the testbench accepts either.
- Reset clears all four registers, all output valid signals, and all
  internal state.

Target ~80 lines, synthesizable SystemVerilog for VCS. Return ONLY
SystemVerilog code in a single ```systemverilog``` code block. No prose
outside the code block.
