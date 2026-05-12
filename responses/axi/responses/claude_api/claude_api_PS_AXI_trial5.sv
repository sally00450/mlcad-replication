```systemverilog
module axi_lite_regs (
    input  logic        aclk,
    input  logic        aresetn,
    input  logic [31:0] awaddr,
    input  logic        awvalid,
    output logic        awready,
    input  logic [31:0] wdata,
    input  logic [3:0]  wstrb,
    input  logic        wvalid,
    output logic        wready,
    output logic [1:0]  bresp,
    output logic        bvalid,
    input  logic        bready,
    input  logic [31:0] araddr,
    input  logic        arvalid,
    output logic        arready,
    output logic [31:0] rdata,
    output logic [1:0]  rresp,
    output logic        rvalid,
    input  logic        rready
);

    logic [31:0] regs [0:3];
    logic [31:0] aw_addr_latched;
    logic        aw_done, w_done;

    // Write handshake
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            awready         <= 1'b0;
            wready          <= 1'b0;
            bvalid          <= 1'b0;
            bresp           <= 2'b00;
            aw_done         <= 1'b0;
            w_done          <= 1'b0;
            aw_addr_latched <= 32'b0;
            regs[0]         <= 32'b0;
            regs[1]         <= 32'b0;
            regs[2]         <= 32'b0;
            regs[3]         <= 32'b0;
        end else begin
            // AW channel
            if (!aw_done && !bvalid) awready <= 1'b1;
            if (awready && awvalid) begin
                awready         <= 1'b0;
                aw_addr_latched <= awaddr;
                aw_done         <= 1'b1;
            end
            // W channel
            if (!w_done && !bvalid) wready <= 1'b1;
            if (wready && wvalid) begin
                wready <= 1'b0;
                w_done <= 1'b1;
            end
            // Commit write when both address and data received
            if (aw_done && w_done && !bvalid) begin
                if (wready && wvalid) begin
                    // handled below in same cycle: use current signals
                end
                // Use latched address; data was accepted, need to capture it
                // We capture data at acceptance time in a separate block below.
            end
            // B channel handshake clear
            if (bvalid && bready) begin
                bvalid  <= 1'b0;
                bresp   <= 2'b00;
                aw_done <= 1'b0;
                w_done  <= 1'b0;
            end
        end
    end

    // Latch write data and perform write when both channels done
    logic [31:0] w_data_latched;
    logic [3:0]  w_strb_latched;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            w_data_latched <= 32'b0;
            w_strb_latched <= 4'b0;
        end else if (wready && wvalid) begin
            w_data_latched <= wdata;
            w_strb_latched <= wstrb;
        end
    end

    // Perform write commit
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            // handled above
        end else begin
            if (aw_done && w_done && !bvalid) begin
                if (|aw_addr_latched[31:4]) begin
                    bvalid <= 1'b1;
                    bresp  <= 2'b10;
                end else begin
                    integer idx;
                    idx = aw_addr_latched[3:2];
                    if (w_strb_latched[0]) regs[idx][7:0]   <= w_data_latched[7:0];
                    if (w_strb_latched[1]) regs[idx][15:8]  <= w_data_latched[15:8];
                    if (w_strb_latched[2]) regs[idx][23:16] <= w_data_latched[23:16];
                    if (w_strb_latched[3]) regs[idx][31:24] <= w_data_latched[31:24];
                    bvalid <= 1'b1;
                    bresp  <= 2'b00;
                end
            end
        end
    end

    // Read channel
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            arready <= 1'b0;
            rvalid  <= 1'b0;
            rresp   <= 2'b00;
            rdata   <= 32'b0;
        end else begin
            if (!arready && !rvalid) arready <= 1'b1;
            if (arready && arvalid) begin
                arready <= 1'b0;
                rvalid  <= 1'b1;
                if (|araddr[31:4]) begin
                    rdata <= 32'b0;
                    rresp <= 2'b10;
                end else begin
                    rdata <= regs[araddr[3:2]];
                    rresp <= 2'b00;
                end
            end
            if (rvalid && rready) begin
                rvalid <= 1'b0;
                rresp  <= 2'b00;
                rdata  <= 32'b0;
            end
        end
    end

endmodule
```