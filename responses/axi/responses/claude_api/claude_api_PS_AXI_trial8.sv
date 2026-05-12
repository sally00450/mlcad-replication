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

    // Write FSM
    typedef enum logic [1:0] {W_IDLE, W_DATA, W_RESP} wstate_t;
    wstate_t wstate;
    logic [31:0] aw_addr_lat;
    logic        aw_oor_lat;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            wstate      <= W_IDLE;
            awready     <= 1'b0;
            wready      <= 1'b0;
            bvalid      <= 1'b0;
            bresp       <= 2'b00;
            aw_addr_lat <= 32'h0;
            aw_oor_lat  <= 1'b0;
            regs[0]     <= 32'h0;
            regs[1]     <= 32'h0;
            regs[2]     <= 32'h0;
            regs[3]     <= 32'h0;
        end else begin
            case (wstate)
                W_IDLE: begin
                    awready <= 1'b1;
                    wready  <= 1'b0;
                    bvalid  <= 1'b0;
                    if (awvalid && awready) begin
                        aw_addr_lat <= awaddr;
                        aw_oor_lat  <= |awaddr[31:4];
                        awready     <= 1'b0;
                        wready      <= 1'b1;
                        wstate      <= W_DATA;
                    end
                end
                W_DATA: begin
                    if (wvalid && wready) begin
                        wready <= 1'b0;
                        if (!aw_oor_lat) begin
                            logic [1:0] idx;
                            idx = aw_addr_lat[3:2];
                            if (wstrb[0]) regs[idx][7:0]   <= wdata[7:0];
                            if (wstrb[1]) regs[idx][15:8]  <= wdata[15:8];
                            if (wstrb[2]) regs[idx][23:16] <= wdata[23:16];
                            if (wstrb[3]) regs[idx][31:24] <= wdata[31:24];
                            bresp <= 2'b00;
                        end else begin
                            bresp <= 2'b10;
                        end
                        bvalid <= 1'b1;
                        wstate <= W_RESP;
                    end
                end
                W_RESP: begin
                    if (bvalid && bready) begin
                        bvalid  <= 1'b0;
                        awready <= 1'b1;
                        wstate  <= W_IDLE;
                    end
                end
                default: wstate <= W_IDLE;
            endcase
        end
    end

    // Read FSM
    typedef enum logic [0:0] {R_IDLE, R_RESP} rstate_t;
    rstate_t rstate;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rstate  <= R_IDLE;
            arready <= 1'b0;
            rvalid  <= 1'b0;
            rdata   <= 32'h0;
            rresp   <= 2'b00;
        end else begin
            case (rstate)
                R_IDLE: begin
                    arready <= 1'b1;
                    rvalid  <= 1'b0;
                    if (arvalid && arready) begin
                        arready <= 1'b0;
                        if (|araddr[31:4]) begin
                            rdata <= 32'h0;
                            rresp <= 2'b10;
                        end else begin
                            rdata <= regs[araddr[3:2]];
                            rresp <= 2'b00;
                        end
                        rvalid <= 1'b1;
                        rstate <= R_RESP;
                    end
                end
                R_RESP: begin
                    if (rvalid && rready) begin
                        rvalid  <= 1'b0;
                        arready <= 1'b1;
                        rstate  <= R_IDLE;
                    end
                end
                default: rstate <= R_IDLE;
            endcase
        end
    end

endmodule
```