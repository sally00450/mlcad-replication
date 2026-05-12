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

    logic        aw_captured;
    logic [31:0] aw_addr_q;
    logic        w_captured;
    logic [31:0] w_data_q;
    logic [3:0]  w_strb_q;

    assign awready = !aw_captured;
    assign wready  = !w_captured;

    logic do_write;
    assign do_write = aw_captured && w_captured && (!bvalid || bready);

    wire aw_in_range = (aw_addr_q[31:4] == 28'h0);
    wire [1:0] aw_idx = aw_addr_q[3:2];

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            regs[0] <= 32'h0;
            regs[1] <= 32'h0;
            regs[2] <= 32'h0;
            regs[3] <= 32'h0;
            aw_captured <= 1'b0;
            w_captured  <= 1'b0;
            aw_addr_q   <= 32'h0;
            w_data_q    <= 32'h0;
            w_strb_q    <= 4'h0;
            bvalid      <= 1'b0;
            bresp       <= 2'b00;
            arready     <= 1'b0;
            rvalid      <= 1'b0;
            rdata       <= 32'h0;
            rresp       <= 2'b00;
        end else begin
            // AW capture
            if (awvalid && awready) begin
                aw_addr_q   <= awaddr;
                aw_captured <= 1'b1;
            end
            // W capture
            if (wvalid && wready) begin
                w_data_q   <= wdata;
                w_strb_q   <= wstrb;
                w_captured <= 1'b1;
            end
            // B handshake clear
            if (bvalid && bready) begin
                bvalid <= 1'b0;
            end
            // Perform write
            if (do_write) begin
                if (aw_in_range) begin
                    if (w_strb_q[0]) regs[aw_idx][7:0]   <= w_data_q[7:0];
                    if (w_strb_q[1]) regs[aw_idx][15:8]  <= w_data_q[15:8];
                    if (w_strb_q[2]) regs[aw_idx][23:16] <= w_data_q[23:16];
                    if (w_strb_q[3]) regs[aw_idx][31:24] <= w_data_q[31:24];
                    bresp <= 2'b00;
                end else begin
                    bresp <= 2'b10;
                end
                bvalid      <= 1'b1;
                aw_captured <= 1'b0;
                w_captured  <= 1'b0;
            end

            // Read channel
            if (!rvalid && !arready) begin
                arready <= 1'b1;
            end
            if (arvalid && arready) begin
                arready <= 1'b0;
                if (araddr[31:4] == 28'h0) begin
                    rdata <= regs[araddr[3:2]];
                    rresp <= 2'b00;
                end else begin
                    rdata <= 32'h0;
                    rresp <= 2'b10;
                end
                rvalid <= 1'b1;
            end
            if (rvalid && rready) begin
                rvalid  <= 1'b0;
                arready <= 1'b1;
            end
        end
    end

endmodule
```