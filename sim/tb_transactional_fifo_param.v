`timescale 1ns/1ps

module tb_transactional_fifo_param;

    localparam WIDTH  = 8;
    localparam DEPTH  = 4;
    localparam ADDR_W = 2;

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

    integer pass_count;
    integer fail_count;

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

    initial clk = 0;
    always #5 clk = ~clk;

    task clear_ctrl;
        begin
            wen = 0;
            commit = 0;
            rollback = 0;
            ren = 0;
            wdata = 0;
        end
    endtask

    task do_reset;
        begin
            resetn = 0;
            clear_ctrl;

            @(posedge clk);
            @(posedge clk);

            resetn = 1;

            @(posedge clk);
        end
    endtask

    task do_write(input [WIDTH-1:0] data);
        begin
            @(negedge clk);

            wen = 1;
            wdata = data;

            @(posedge clk);

            @(negedge clk);

            wen = 0;
        end
    endtask

    task do_commit;
        begin
            @(negedge clk);

            commit = 1;

            @(posedge clk);

            @(negedge clk);

            commit = 0;
        end
    endtask

    task do_read_check(
        input [255:0] tag,
        input [WIDTH-1:0] expected
    );
        begin
            @(negedge clk);

            ren = 1;

            @(posedge clk);

            @(negedge clk);

            ren = 0;

            @(posedge clk);

            #1;

            if (rdata === expected) begin
                pass_count = pass_count + 1;
                $display(
                    "  [PASS] %0s : expected=%0h observed=%0h",
                    tag,
                    expected,
                    rdata
                );
            end
            else begin
                fail_count = fail_count + 1;
                $display(
                    "  [FAIL] %0s : expected=%0h observed=%0h",
                    tag,
                    expected,
                    rdata
                );
            end
        end
    endtask

    task check_count(
        input [255:0] tag,
        input [ADDR_W:0] expected,
        input [ADDR_W:0] observed
    );
        begin
            if (expected === observed) begin
                pass_count = pass_count + 1;

                $display(
                    "  [PASS] %0s : expected=%0d observed=%0d",
                    tag,
                    expected,
                    observed
                );
            end
            else begin
                fail_count = fail_count + 1;

                $display(
                    "  [FAIL] %0s : expected=%0d observed=%0d",
                    tag,
                    expected,
                    observed
                );
            end
        end
    endtask

    initial begin

        pass_count = 0;
        fail_count = 0;

        resetn = 0;
        clear_ctrl;

        $display("=====================================================");
        $display(" Transactional FIFO - Parameterization Test");
        $display(" WIDTH = 8, DEPTH = 4");
        $display("=====================================================");

        do_reset;

        // ---------------------------------------------------------
        // 26.1 Fill FIFO with speculative data
        // ---------------------------------------------------------

        $display("\n-- 26.1 Fill DEPTH=4 FIFO --");

        do_write(8'hA1);
        do_write(8'hA2);
        do_write(8'hA3);
        do_write(8'hA4);

        check_count(
            "26.1.total-count-full",
            4,
            total_count
        );

        check_count(
            "26.1.speculative-count-full",
            4,
            speculative_count
        );

        if (full === 1'b1) begin
            pass_count = pass_count + 1;
            $display("  [PASS] 26.1.full-asserted");
        end
        else begin
            fail_count = fail_count + 1;
            $display("  [FAIL] 26.1.full-asserted");
        end

        // ---------------------------------------------------------
        // 26.2 Commit all data
        // ---------------------------------------------------------

        $display("\n-- 26.2 Commit all entries --");

        do_commit;

        check_count(
            "26.2.committed-count",
            4,
            committed_count
        );

        check_count(
            "26.2.speculative-count",
            0,
            speculative_count
        );

        // ---------------------------------------------------------
        // 26.3 Drain FIFO
        // ---------------------------------------------------------

        $display("\n-- 26.3 Read all entries --");

        do_read_check("26.3.read-1", 8'hA1);
        do_read_check("26.3.read-2", 8'hA2);
        do_read_check("26.3.read-3", 8'hA3);
        do_read_check("26.3.read-4", 8'hA4);

        check_count(
            "26.3.total-count-empty",
            0,
            total_count
        );

        if (empty === 1'b1) begin
            pass_count = pass_count + 1;
            $display("  [PASS] 26.3.empty-asserted");
        end
        else begin
            fail_count = fail_count + 1;
            $display("  [FAIL] 26.3.empty-asserted");
        end

        // ---------------------------------------------------------
        // Summary
        // ---------------------------------------------------------

        $display("\n=====================================================");
        $display(
            " RESULTS: %0d PASS / %0d FAIL / %0d TOTAL",
            pass_count,
            fail_count,
            pass_count + fail_count
        );

        if (fail_count == 0)
            $display(" STATUS : ALL PARAMETER TESTS PASSED");
        else
            $display(" STATUS : FAILURES DETECTED");

        $display("=====================================================");

        $finish;

    end

endmodule