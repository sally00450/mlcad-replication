```systemverilog
module axi_lite_regs (
    input  logic        aclk,
    input  logic        aresetn,
    // Write address channel
    input  logic [31:0] awaddr,
    input  logic        awvalid,
    output logic        awready,
    // Write data channel
    input  logic [31:0] wdata,
    input  logic [3:0]  wstrb,
    input  logic        wvalid,
    output logic        wready,
    // Write response channel
    output logic [1:0]  bresp,
    output logic        bvalid,
    input  logic        bready,
    // Read address channel
    input  logic [31:0] araddr,
    input  logic        arvalid,
    output logic        arready,
    // Read data channel
    output logic [31:0] rdata,
    output logic [1:0]  rresp,
    output logic        rvalid,
    input  logic        rready
    );

    logic [31:0] regs [0:3];

    logic        aw_done, w_done;
    logic [31:0] aw_addr_q;
    logic [31:0] w_data_q;
    logic [3:0]  w_strb_q;

    // Write address
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            awready   <= 1'b0;
            aw_done   <= 1'b0;
            aw_addr_q <= 32'h0;
        end else begin
            if (!aw_done && !awready && awvalid) begin
                awready   <= 1'b1;
            end else if (awready && awvalid) begin
                awready   <= 1'b0;
                aw_addr_q <= awaddr;
                aw_done   <= 1'b1;
            end else if (bvalid && bready) begin
                aw_done   <= 1'b0;
            end
        end
    end

    // Write data
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            wready   <= 1'b0;
            w_done   <= 1'b0;
            w_data_q <= 32'h0;
            w_strb_q <= 4'h0;
        end else begin
            if (!w_done && !wready && wvalid) begin
                wready   <= 1'b1;
            end else if (wready && wvalid) begin
                wready   <= 1'b0;
                w_data_q <= wdata;
                w_strb_q <= wstrb;
                w_done   <= 1'b1;
            end else if (bvalid && bready) begin
                w_done   <= 1'b0;
            end
        end
    end

    // Write response + register update
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            bvalid   <= 1'b0;
            bresp    <= 2'b00;
            regs[0]  <= 32'h0;
            regs[1]  <= 32'h0;
            regs[2]  <= 32'h0;
            regs[3]  <= 32'h0;
        end else begin
            if (!bvalid && aw_done && w_done) begin
                bvalid <= 1'b1;
                if (|aw_addr_q[31:4]) begin
                    bresp <= 2'b10;
                end else begin
                    bresp <= 2'b00;
                    for (int b = 0; b < 4; b++) begin
                        if (w_strb_q[b])
                            regs[aw_addr_q[3:2]][8*b +: 8] <= w_data_q[8*b +: 8];
                    end
                end
            end else if (bvalid && bready) begin
                bvalid <= 1'b0;
            end
        end
    end

    // Read channel
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            arready <= 1'b0;
            rvalid  <= 1'b0;
            rdata   <= 32'h0;
            rresp   <= 2'b00;
        end else begin
            if (!arready && !rvalid && arvalid) begin
                arready <= 1'b1;
            end else if (arready && arvalid) begin
                arready <= 1'b0;
                rvalid  <= 1'b1;
                if (|araddr[31:4]) begin
                    rdata <= 32'h0;
                    rresp <= 2'b10;
                end else begin
                    rdata <= regs[araddr[3:2]];
                    rresp <= 2'b00;
                end
            end else if (rvalid && rready) begin
                rvalid <= 1'b0;
            end
        end
    end

endmodule
```