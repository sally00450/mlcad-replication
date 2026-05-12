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

    // Write state
    logic        aw_captured;
    logic [31:0] aw_addr_q;
    logic        w_captured;
    logic [31:0] w_data_q;
    logic [3:0]  w_strb_q;

    wire do_write = (aw_captured || awvalid) && (w_captured || wvalid) && (!bvalid || bready);

    wire [31:0] eff_awaddr = aw_captured ? aw_addr_q : awaddr;
    wire [31:0] eff_wdata  = w_captured  ? w_data_q  : wdata;
    wire [3:0]  eff_wstrb  = w_captured  ? w_strb_q  : wstrb;
    wire        aw_oor     = |eff_awaddr[31:4];
    wire [1:0]  widx       = eff_awaddr[3:2];

    assign awready = !aw_captured && (!bvalid || bready);
    assign wready  = !w_captured  && (!bvalid || bready);

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            regs[0] <= 32'h0; regs[1] <= 32'h0; regs[2] <= 32'h0; regs[3] <= 32'h0;
            aw_captured <= 1'b0;
            w_captured  <= 1'b0;
            aw_addr_q   <= 32'h0;
            w_data_q    <= 32'h0;
            w_strb_q    <= 4'h0;
            bvalid      <= 1'b0;
            bresp       <= 2'b00;
        end else begin
            if (bvalid && bready) begin
                bvalid <= 1'b0;
            end

            if (do_write) begin
                if (!aw_oor) begin
                    if (eff_wstrb[0]) regs[widx][7:0]   <= eff_wdata[7:0];
                    if (eff_wstrb[1]) regs[widx][15:8]  <= eff_wdata[15:8];
                    if (eff_wstrb[2]) regs[widx][23:16] <= eff_wdata[23:16];
                    if (eff_wstrb[3]) regs[widx][31:24] <= eff_wdata[31:24];
                    bresp <= 2'b00;
                end else begin
                    bresp <= 2'b10;
                end
                bvalid      <= 1'b1;
                aw_captured <= 1'b0;
                w_captured  <= 1'b0;
            end else begin
                if (awvalid && awready) begin
                    aw_addr_q   <= awaddr;
                    aw_captured <= 1'b1;
                end
                if (wvalid && wready) begin
                    w_data_q   <= wdata;
                    w_strb_q   <= wstrb;
                    w_captured <= 1'b1;
                end
            end
        end
    end

    // Read channel
    assign arready = !rvalid;
    wire        ar_oor = |araddr[31:4];
    wire [1:0]  ridx   = araddr[3:2];

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rvalid <= 1'b0;
            rdata  <= 32'h0;
            rresp  <= 2'b00;
        end else begin
            if (rvalid && rready) begin
                rvalid <= 1'b0;
            end else if (arvalid && arready) begin
                rvalid <= 1'b1;
                if (ar_oor) begin
                    rdata <= 32'h0;
                    rresp <= 2'b10;
                end else begin
                    rdata <= regs[ridx];
                    rresp <= 2'b00;
                end
            end
        end
    end

endmodule
```