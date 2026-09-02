// =====================================================================
// transactional_fifo.v
//
// Transactional Synchronous FIFO (Commit / Rollback)
// ----------------------------------------------------------------------
// Standard synchronous-FIFO read/write behavior, extended with a
// speculative write stage. Writes land in a "staged" region that is
// invisible to the reader until explicitly committed. A rollback
// discards all staged (uncommitted) data without disturbing anything
// already committed.
//
// Three pointers over one shared memory array:
//   rd_ptr          - read boundary, only ever chases wr_ptr_actual
//   wr_ptr_actual   - committed-data boundary (the only boundary the
//                      reader can see)
//   wr_ptr_spec     - speculative-data boundary (advances on every wen)
//
//   commit   : wr_ptr_actual   <= wr_ptr_spec     (stage becomes real)
//   rollback : wr_ptr_spec     <= wr_ptr_actual   (stage is discarded)
//
// empty is derived from committed data only (rd_ptr vs wr_ptr_actual).
// full accounts for committed + staged occupancy (wr_ptr_spec vs rd_ptr),
// since that memory is already consumed even though it is not yet
// readable.
//
// Documented conflict-priority rules (see design note):
//   1. commit and rollback asserted together   -> rollback wins.
//   2. wen and commit asserted together        -> commit uses the
//      pre-cycle value of wr_ptr_spec; the new write is NOT included
//      in that commit (it becomes visible on a later commit).
//   3. wen and rollback asserted together      -> rollback wins; the
//      write in that same cycle is discarded along with any other
//      staged data.
//   4. wen while the speculative region is full -> write is suppressed
//      (full is asserted one cycle ahead of the collision), no data
//      is corrupted.
//   5. rollback with nothing staged, or back-to-back commits with no
//      intervening writes, are safe no-ops by construction.
// =====================================================================

`timescale 1ns/1ps

module transactional_fifo #(
    parameter WIDTH = 32,
    parameter DEPTH = 16            // must be a power of 2
) (
    input  wire clk,
    input  wire resetn,            // active-low synchronous reset

    // write / transaction control
    input  wire [WIDTH-1:0] wdata,
    input  wire wen,           // stage a speculative write
    input  wire commit,        // staged data -> readable
    input  wire rollback,      // discard staged data

    // read
    input  wire                  ren,
    output reg  [WIDTH-1:0]      rdata,

    // status
    output wire empty,         // no committed data to read
    output wire full,           // committed + staged fills array
    output wire txn_pending,
    output wire [$clog2(DEPTH):0] committed_count,
    output wire [$clog2(DEPTH):0] speculative_count,
    output wire [$clog2(DEPTH):0] total_count
);

    // ------------------------------------------------------------
    // BUGFIX: ADDR_W must be a localparam, not a parameter.
    // As a plain `parameter` it was independently overridable at
    // instantiation (explicitly, or accidentally via a positional
    // override such as #(32, 8, 5)). Any override that disagreed
    // with $clog2(DEPTH) desynced the pointer width from the memory
    // array bound (mem[0:DEPTH-1]), causing out-of-range indexing /
    // silent address truncation with no simulation warning. Making
    // it a localparam ties it permanently to DEPTH so this class of
    // bug can no longer occur.
    // ------------------------------------------------------------
    localparam ADDR_W = $clog2(DEPTH);

    // ------------------------------------------------------------
    // Storage: one extra (wrap) bit on every pointer to disambiguate
    // full vs. empty when address bits are numerically equal.
    // ------------------------------------------------------------
    reg [WIDTH-1:0] mem [0:DEPTH-1];

    reg [ADDR_W:0] rd_ptr;
    reg [ADDR_W:0] wr_ptr_actual;
    reg [ADDR_W:0] wr_ptr_spec;

    wire [ADDR_W-1:0] rd_addr   = rd_ptr[ADDR_W-1:0];
    wire [ADDR_W-1:0] wr_addr_s = wr_ptr_spec[ADDR_W-1:0];

    // ------------------------------------------------------------
    // Status flags
    // ------------------------------------------------------------
    // empty: committed data only -> derived from wr_ptr_actual, never
    // from wr_ptr_spec, so uncommitted data is structurally unreadable.
    assign empty = (rd_ptr == wr_ptr_actual);

    // full: committed + staged occupancy -> derived from wr_ptr_spec,
    // since that memory is already consumed even though invisible.
    assign full  = (wr_ptr_spec[ADDR_W-1:0] == rd_ptr[ADDR_W-1:0]) &&
                   (wr_ptr_spec[ADDR_W]     != rd_ptr[ADDR_W]);
                   
    // Indicates that speculative data is waiting for
    // either a commit or rollback operation.
    assign txn_pending = (wr_ptr_spec != wr_ptr_actual);
    
    // Number of committed entries available for reading
    assign committed_count = wr_ptr_actual - rd_ptr;
    
    // Number of speculative entries waiting for commit/rollback
    assign speculative_count = wr_ptr_spec - wr_ptr_actual;
    
    assign total_count = wr_ptr_spec - rd_ptr;

    // write is legal only if it will not run into the read pointer
    wire write_allowed = wen && !full;

    // ------------------------------------------------------------
    // Pointer & memory update (single clock domain, synchronous reset)
    // ------------------------------------------------------------
    always @(posedge clk) begin
        if (!resetn) begin
            rd_ptr        <= {(ADDR_W+1){1'b0}};
            wr_ptr_actual <= {(ADDR_W+1){1'b0}};
            wr_ptr_spec   <= {(ADDR_W+1){1'b0}};
            rdata         <= {WIDTH{1'b0}};
        end else begin

            // ---- speculative write: stage data, advance wr_ptr_spec ----
            if (write_allowed) begin
                mem[wr_addr_s] <= wdata;
            end

            // ---- commit / rollback / write-pointer resolution ----
            // Rule 1 & 3: rollback has priority over both commit and
            // a same-cycle write on wr_ptr_spec.
            if (rollback) begin
                wr_ptr_spec <= wr_ptr_actual;
            end else if (write_allowed) begin
                wr_ptr_spec <= wr_ptr_spec + 1'b1;
            end

            // Rule 2: commit uses the pre-cycle (current-register) value
            // of wr_ptr_spec, so a same-cycle write is not included.
            // Rollback beats commit if both are asserted (Rule 1).
            if (!rollback && commit) begin
                wr_ptr_actual <= wr_ptr_spec;
            end

            // ---- read: registered data, standard sync-FIFO timing ----
            if (ren && !empty) begin
                rdata  <= mem[rd_addr];
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

endmodule