//-----------------------------------------------------------------------------
// tb_axi_lite -- Reference testbench for axi_lite_regs.
// Exercises only the PORT CONTRACT. 10+ functional checks. Prints PASS/FAIL
// tags per check and a final RESULT: ALL_PASS / RESULT: FAIL.
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_axi_lite;

    logic        aclk    = 0;
    logic        aresetn = 0;

    logic [31:0] awaddr  = 0;
    logic        awvalid = 0;
    logic        awready;
    logic [31:0] wdata   = 0;
    logic [3:0]  wstrb   = 4'hF;
    logic        wvalid  = 0;
    logic        wready;
    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready  = 0;
    logic [31:0] araddr  = 0;
    logic        arvalid = 0;
    logic        arready;
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rvalid;
    logic        rready  = 0;

    int pass_cnt = 0;
    int fail_cnt = 0;

    axi_lite_regs dut (
        .aclk(aclk), .aresetn(aresetn),
        .awaddr(awaddr), .awvalid(awvalid), .awready(awready),
        .wdata(wdata), .wstrb(wstrb), .wvalid(wvalid), .wready(wready),
        .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .araddr(araddr), .arvalid(arvalid), .arready(arready),
        .rdata(rdata), .rresp(rresp), .rvalid(rvalid), .rready(rready)
    );

    always #5 aclk = ~aclk; // 100 MHz

    // -- Check helpers -------------------------------------------------------
    task automatic check(input string name, input bit cond);
        if (cond) begin
            $display("PASS: %s", name);
            pass_cnt++;
        end else begin
            $display("FAIL: %s", name);
            fail_cnt++;
        end
    endtask

    // -- AXI write primitive -------------------------------------------------
    task automatic axi_write(input logic [31:0] addr,
                             input logic [31:0] data,
                             input logic [3:0]  strb,
                             output logic [1:0] resp);
        // Launch AW+W in parallel
        fork
            begin
                @(posedge aclk); awaddr <= addr; awvalid <= 1'b1;
                do @(posedge aclk); while (!awready);
                awvalid <= 1'b0;
            end
            begin
                @(posedge aclk); wdata <= data; wstrb <= strb; wvalid <= 1'b1;
                do @(posedge aclk); while (!wready);
                wvalid <= 1'b0;
            end
        join
        // Wait for BVALID
        bready <= 1'b1;
        do @(posedge aclk); while (!bvalid);
        resp = bresp;
        @(posedge aclk); bready <= 1'b0;
    endtask

    // -- AXI read primitive --------------------------------------------------
    task automatic axi_read(input  logic [31:0] addr,
                            output logic [31:0] data,
                            output logic [1:0]  resp);
        @(posedge aclk); araddr <= addr; arvalid <= 1'b1;
        do @(posedge aclk); while (!arready);
        arvalid <= 1'b0;
        rready <= 1'b1;
        do @(posedge aclk); while (!rvalid);
        data = rdata;
        resp = rresp;
        @(posedge aclk); rready <= 1'b0;
    endtask

    logic [31:0] rd_data;
    logic [1:0]  rd_resp, wr_resp;

    initial begin
        // Reset
        aresetn = 0;
        repeat (5) @(posedge aclk);
        aresetn = 1;
        @(posedge aclk);

        // Check 1: reg0 initial value is 0
        axi_read(32'h00, rd_data, rd_resp);
        check("reg0 init=0", rd_data == 32'h0 && rd_resp == 2'b00);

        // Check 2: reg1 initial value is 0
        axi_read(32'h04, rd_data, rd_resp);
        check("reg1 init=0", rd_data == 32'h0 && rd_resp == 2'b00);

        // Check 3: write reg0 and read back
        axi_write(32'h00, 32'hDEADBEEF, 4'hF, wr_resp);
        check("reg0 write resp OKAY", wr_resp == 2'b00);
        axi_read(32'h00, rd_data, rd_resp);
        check("reg0 readback DEADBEEF", rd_data == 32'hDEADBEEF);

        // Check 4: write reg1 and read back
        axi_write(32'h04, 32'hCAFEBABE, 4'hF, wr_resp);
        axi_read(32'h04, rd_data, rd_resp);
        check("reg1 readback CAFEBABE", rd_data == 32'hCAFEBABE);

        // Check 5: write reg2 and read back
        axi_write(32'h08, 32'h12345678, 4'hF, wr_resp);
        axi_read(32'h08, rd_data, rd_resp);
        check("reg2 readback 12345678", rd_data == 32'h12345678);

        // Check 6: write reg3 and read back
        axi_write(32'h0C, 32'hA5A5A5A5, 4'hF, wr_resp);
        axi_read(32'h0C, rd_data, rd_resp);
        check("reg3 readback A5A5A5A5", rd_data == 32'hA5A5A5A5);

        // Check 7: reg0 is still DEADBEEF (no aliasing between regs)
        axi_read(32'h00, rd_data, rd_resp);
        check("reg0 unchanged after other writes", rd_data == 32'hDEADBEEF);

        // Check 8: wstrb masking, write only byte 0 of reg0
        // Current reg0=DEADBEEF; write data=0x00000011 with strb=4'b0001
        // Expected: reg0 = DEADBE11
        axi_write(32'h00, 32'h00000011, 4'b0001, wr_resp);
        axi_read(32'h00, rd_data, rd_resp);
        check("reg0 wstrb byte0 only -> DEADBE11", rd_data == 32'hDEADBE11);

        // Check 9: wstrb masking, write only byte 3 of reg0
        // Expected: reg0 = 77ADBE11
        axi_write(32'h00, 32'h77000000, 4'b1000, wr_resp);
        axi_read(32'h00, rd_data, rd_resp);
        check("reg0 wstrb byte3 only -> 77ADBE11", rd_data == 32'h77ADBE11);

        // Check 10: out-of-range read returns 0 (with either OKAY or SLVERR acceptable)
        axi_read(32'h100, rd_data, rd_resp);
        check("OOR read rdata==0", rd_data == 32'h0);

        // Check 11: OOR read response is SLVERR or OKAY (implementation choice documented SLVERR)
        check("OOR read rresp OKAY|SLVERR", rd_resp == 2'b00 || rd_resp == 2'b10);

        // Check 12: reset clears registers
        aresetn = 0;
        repeat (3) @(posedge aclk);
        aresetn = 1;
        @(posedge aclk);
        axi_read(32'h00, rd_data, rd_resp);
        check("reg0 cleared by reset", rd_data == 32'h0);
        axi_read(32'h0C, rd_data, rd_resp);
        check("reg3 cleared by reset", rd_data == 32'h0);

        // Summary
        $display("");
        $display("pass=%0d fail=%0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("RESULT: ALL_PASS");
        else
            $display("RESULT: FAIL");
        $finish;
    end

    // Watchdog
    initial begin
        #200000;
        $display("FAIL: watchdog timeout");
        $display("RESULT: FAIL");
        $finish;
    end

endmodule
