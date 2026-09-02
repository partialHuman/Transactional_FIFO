`timescale 1ns/1ps

// ============================================================
// Transactional FIFO - Demonstration Testbench
//
// Demonstrates:
//   1. Reset
//   2. Speculative Write A
//   3. Commit A
//   4. Read A
//   5. Speculative Write B
//   6. Rollback B
// ============================================================

module tb_transactional_fifo_demo;

    localparam WIDTH = 32;
    localparam DEPTH = 16;
    localparam ADDR_W = $clog2(DEPTH);

    // --------------------------------------------------------
    // DUT signals
    // --------------------------------------------------------
    reg clk;
    reg resetn;

    reg [WIDTH-1:0] wdata;
    reg wen;
    reg commit;
    reg rollback;

    reg ren;
    wire [WIDTH-1:0] rdata;

    wire empty;
    wire full;
    wire txn_pending;

    wire [ADDR_W:0] committed_count;
    wire [ADDR_W:0] speculative_count;
    wire [ADDR_W:0] total_count;

    // --------------------------------------------------------
    // DUT
    // --------------------------------------------------------
    transactional_fifo #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk),
        .resetn(resetn),

        .wdata(wdata),
        .wen(wen),
        .commit(commit),
        .rollback(rollback),

        .ren(ren),
        .rdata(rdata),

        .empty(empty),
        .full(full),
        .txn_pending(txn_pending),

        .committed_count(committed_count),
        .speculative_count(speculative_count),
        .total_count(total_count)
    );

    // --------------------------------------------------------
    // Clock: 10 ns period
    // --------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // --------------------------------------------------------
    // Main demonstration sequence
    // --------------------------------------------------------
    initial begin

        // Initial values
        resetn   = 0;
        wdata    = 0;
        wen      = 0;
        commit   = 0;
        rollback = 0;
        ren      = 0;

        // ====================================================
        // 1. RESET
        // ====================================================
        #20;

        @(negedge clk);
        resetn = 1;

        #20;

        // ====================================================
        // 2. SPECULATIVE WRITE A
        //
        // Data enters FIFO but remains invisible to reader.
        // ====================================================
        @(negedge clk);

        wdata = 32'hAAAA_0001;
        wen   = 1;

        @(negedge clk);

        wen   = 0;
        wdata = 0;

        #20;

        // ====================================================
        // 3. COMMIT A
        //
        // Speculative data becomes committed/readable.
        // ====================================================
        @(negedge clk);

        commit = 1;

        @(negedge clk);

        commit = 0;

        #20;

        // ====================================================
        // 4. READ A
        //
        // Expected rdata = AAAA0001
        // ====================================================
        @(negedge clk);

        ren = 1;

        @(negedge clk);

        ren = 0;

        #20;

        // ====================================================
        // 5. SPECULATIVE WRITE B
        //
        // Data remains pending.
        // ====================================================
        @(negedge clk);

        wdata = 32'hBBBB_0002;
        wen   = 1;

        @(negedge clk);

        wen   = 0;
        wdata = 0;

        #20;

        // ====================================================
        // 6. ROLLBACK B
        //
        // Speculative data is discarded.
        // ====================================================
        @(negedge clk);

        rollback = 1;

        @(negedge clk);

        rollback = 0;

        #30;

        $display("==============================================");
        $display(" Transactional FIFO Demo Completed");
        $display("==============================================");

        $finish;

    end

endmodule