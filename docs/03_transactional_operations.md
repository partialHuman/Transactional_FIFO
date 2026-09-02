# Transaction Operations

This document explains how the Transactional FIFO handles speculative writes and how data is either made permanently readable using **commit** or discarded using **rollback**.

The FIFO uses a single shared memory array and three pointers:

- **`rd_ptr`** — points to the next committed data item to be read.
- **`wr_ptr_actual`** — marks the boundary of committed data.
- **`wr_ptr_spec`** — marks the end of speculative data.

Speculative data occupies FIFO memory immediately, but it cannot be read until a commit operation moves the committed boundary forward.

---

## 1. Transactional FIFO Data Flow

The overall transactional behavior is shown below.

```mermaid
flowchart LR
    WD["Write Interface<br/>wdata + wen"]

    subgraph FIFO["Transactional FIFO"]
        MEM["Shared FIFO Memory<br/>DEPTH × WIDTH"]

        RP["rd_ptr"]
        WA["wr_ptr_actual<br/>Committed Boundary"]
        WS["wr_ptr_spec<br/>Speculative Boundary"]
    end

    CTRL["Transaction Control<br/>commit / rollback"]

    RD["Read Interface<br/>rdata + ren"]

    WD --> MEM
    WD --> WS

    CTRL --> WA
    CTRL --> WS

    RP --> MEM
    WA --> MEM
    WS --> MEM

    MEM --> RD
```

The write interface stores incoming data in the shared FIFO memory. The data initially belongs to the **speculative region**.

The `wr_ptr_spec` pointer advances whenever a valid write is accepted. The `wr_ptr_actual` pointer advances only when a commit operation occurs.

---

# 2. Write Operation

A write operation places new data into the speculative region of the FIFO.

```mermaid
flowchart LR
    WDATA["wdata"]
    WEN["wen = 1"]

    WDATA --> MEM["Shared FIFO Memory"]

    WEN --> CHECK{"FIFO Full?"}

    CHECK -->|No| WRITE["Store Data"]
    WRITE --> SPEC["Advance wr_ptr_spec"]

    CHECK -->|Yes| BLOCK["Write Suppressed"]

    SPEC --> STAGE["Speculative Data Region"]

    STAGE -. "Not Visible to Reader" .-> INVISIBLE["Reader Cannot Access Data"]
```

### Operation

When:

```v
wen = 1
full = 0
```

the FIFO performs:

```v
mem[wr_ptr_spec] <= wdata
wr_ptr_spec      <= wr_ptr_spec + 1
```

The data is stored physically in the FIFO memory, but it remains speculative.

The read side still uses `wr_ptr_actual` as its visibility boundary.

Therefore:

```mermaid
flowchart TB
    
SPEC_IN["Speculative Write Data"]
    subgraph FIFO["Transactional FIFO"]
        direction TB

        subgraph MEM["Shared FIFO Memory"]
            direction LR

            COMMITTED["Committed Region<br/>Readable Data"]
            SPECULATIVE["Speculative Region<br/>Uncommitted Data"]
            
        end

        ACTUAL["wr_ptr_actual<br/>Committed Boundary"]
        SPEC["wr_ptr_spec<br/>Speculative Boundary"]
    end

    SPEC_IN --> SPECULATIVE
    ACTUAL -. "defines committed boundary" .-> COMMITTED
    SPEC -. "defines speculative boundary" .-> SPECULATIVE
```

Only the committed portion is visible to the reader.

---

# 3. Commit Operation

A commit operation makes all currently staged speculative data available for reading.

```mermaid
flowchart LR
    SPEC["Speculative Data<br/>wr_ptr_actual → wr_ptr_spec"]

    COMMIT["commit = 1"]

    COMMIT --> MOVE["Move Committed Boundary"]

    WS["wr_ptr_spec"] --> MOVE

    MOVE --> WA["wr_ptr_actual <= wr_ptr_spec"]

    WA --> COMMITTED["Data Becomes Committed"]

    COMMITTED --> READ["Reader Can Access Data"]
```

### Operation

When:

```v
commit = 1
rollback = 0
```

the FIFO performs:

```v
wr_ptr_actual <= wr_ptr_spec
```

The speculative pointer itself does not move during a commit unless a write operation is also occurring.

After commit:

```mermaid
flowchart TB

    subgraph BEFORE["Before Commit"]
        direction LR
        RD1["rd_ptr"]
        COM1["wr_ptr_actual<br/>Committed Boundary"]
        SPEC1["wr_ptr_spec<br/>Speculative Boundary"]

        RD1 --> COM1
        COM1 -. "Speculative Data" .-> SPEC1
    end

    COMMIT["COMMIT"]

    subgraph AFTER["After Commit"]
        direction LR
        RD2["rd_ptr"]
        COM2["wr_ptr_actual<br/>Moves to previous wr_ptr_spec"]
        SPEC2["wr_ptr_spec"]

        RD2 --> COM2
        COM2 --- SPEC2
    end

    BEFORE --> COMMIT --> AFTER

    RESULT["All previously speculative data<br/>is now committed and readable"]

    AFTER --> RESULT
```

All data between the old `wr_ptr_actual` and `wr_ptr_spec` becomes readable.

---

# 4. Rollback Operation

A rollback operation discards all speculative data while preserving previously committed data.

```mermaid
flowchart LR
    RB["rollback = 1"]

    RB --> DISCARD["Discard Speculative Region"]

    WA["wr_ptr_actual"] --> UPDATE["wr_ptr_spec <= wr_ptr_actual"]

    UPDATE --> DISCARD

    COMMITTED["Previously Committed Data"] --> KEEP["Preserved"]

    SPEC["Speculative Data"] --> X["Discarded"]
```

### Operation

When:

```v
rollback = 1
```

the FIFO performs:

```v
wr_ptr_spec <= wr_ptr_actual
```

The committed pointer does not move.

Therefore, the speculative region is logically discarded without requiring the memory contents to be physically erased.

```mermaid
flowchart TB

    subgraph BEFORE["Before Rollback"]
        direction LR

        RD1["rd_ptr"]
        ACT1["wr_ptr_actual<br/>Committed Boundary"]
        SPEC1["wr_ptr_spec<br/>Speculative Boundary"]

        RD1 -->|"Committed Data"| ACT1
        ACT1 -. "Speculative Data" .-> SPEC1
    end

    ROLLBACK["ROLLBACK"]

    subgraph AFTER["After Rollback"]
        direction LR

        RD2["rd_ptr"]
        ACT2["wr_ptr_actual<br/>Committed Boundary"]
        SPEC2["wr_ptr_spec<br/>Returns to wr_ptr_actual"]

        RD2 -->|"Committed Data"| ACT2
        ACT2 --- SPEC2
    end

    BEFORE --> ROLLBACK --> AFTER

    RESULT["Speculative data is discarded<br/>Committed data remains unchanged"]

    AFTER --> RESULT
```

The old memory values may still physically exist in the array, but they are no longer part of the FIFO because the speculative pointer has been moved back.

---

# 5. Complete Transaction Lifecycle

The complete lifecycle of a transaction is shown below.

```mermaid
flowchart TD
    IDLE(["FIFO Idle / No Transaction"])

    IDLE -->|"wen"| WRITE["Write Data"]

    WRITE --> STAGED["Data Stored in<br/>Speculative Region"]

    STAGED -->|"wen"| WRITE

    STAGED -->|"commit"| COMMIT["Commit Transaction"]

    STAGED -->|"rollback"| ROLLBACK["Rollback Transaction"]

    COMMIT --> VISIBLE["Data Becomes Readable"]

    VISIBLE -->|"ren"| READ["Read Committed Data"]

    READ --> IDLE

    ROLLBACK --> IDLE

    VISIBLE -->|"More Writes"| WRITE
```

The two possible transaction outcomes are:

| Operation | Result |
|---|---|
| `wen` | Data enters the speculative region |
| `commit` | All currently speculative data becomes committed |
| `rollback` | All speculative data is discarded |
| `ren` | Reads only committed data |

---

# 6. Pointer Movement

The following table summarizes how each operation affects the FIFO pointers.

| Operation | `rd_ptr` | `wr_ptr_actual` | `wr_ptr_spec` |
|---|---|---|---|
| Reset | Reset to 0 | Reset to 0 | Reset to 0 |
| Write | No change | No change | Increment |
| Commit | No change | Move to `wr_ptr_spec` | No change |
| Rollback | No change | No change | Move to `wr_ptr_actual` |
| Read | Increment | No change | No change |

---

# 7. Simultaneous Operation Priority

The Transactional FIFO supports multiple control signals during the same clock cycle.

The implemented priority is:

```mermaid
flowchart TD
    START["Clock Edge"]

    START --> RB{"rollback = 1?"}

    RB -->|Yes| ROLLBACK["Rollback Wins<br/>Discard Speculative Data"]

    RB -->|No| COM{"commit = 1?"}

    COM -->|Yes| COMMIT["Commit Pre-Cycle<br/>Speculative Region"]

    COM -->|No| WRITE{"wen = 1 and not full?"}

    WRITE -->|Yes| STAGE["Stage New Write"]

    WRITE -->|No| IDLE["No Write Operation"]
```

The important conflict rules are:

### Commit + Rollback

```v
commit = 1
rollback = 1
```

**Rollback has priority.**

The speculative region is discarded.

---

### Write + Commit

```v
wen    = 1
commit = 1
```

The commit uses the **pre-cycle value** of `wr_ptr_spec`.

Therefore:

- Previously staged data becomes committed.
- The new write remains speculative.
- A later commit is required to make the new write readable.

```mermaid
flowchart LR
    OLD["Previously Staged Data"] --> COMMIT["Commit"]
    COMMIT --> READABLE["Committed / Readable"]

    NEW["New Same-Cycle Write"] --> SPEC["Still Speculative"]

    SPEC --> NEXT["Requires Next Commit"]
```

---

### Write + Rollback

```v
wen      = 1
rollback = 1
```

Rollback has priority.

Any speculative data, including the same-cycle write, is discarded.

```mermaid
flowchart LR
    OLD["Existing Speculative Data"] --> DISCARD["Rollback"]

    NEW["Same-Cycle Write"] --> DISCARD

    DISCARD --> RESULT["wr_ptr_spec = wr_ptr_actual"]
```

---

# 8. Data Visibility

The most important feature of the Transactional FIFO is that **data visibility is controlled by the committed write pointer**.

```mermaid
flowchart LR
    subgraph MEMORY["Shared FIFO Memory"]
        direction LR

        READABLE["Committed Region<br/>Visible to Reader"]

        STAGED["Speculative Region<br/>Hidden from Reader"]
    end

    WA["wr_ptr_actual"] --> READABLE
    WS["wr_ptr_spec"] --> STAGED

    READABLE --> RD["Read Interface"]

    STAGED -. "Blocked" .-> RD
```

The `empty` flag is also based only on committed data:

```verilog
assign empty = (rd_ptr == wr_ptr_actual);
```

Therefore, a FIFO containing only speculative data can still report:

```verilog
empty = 1
txn_pending = 1
```

This ensures that uncommitted data can never be read accidentally.

---

# 9. FIFO Full Condition

The FIFO full condition includes both committed and speculative data.

```mermaid
flowchart LR
    RD["rd_ptr"]

    COM["Committed Data"]
    SPEC["Speculative Data"]

    RD --> COM --> SPEC

    SPEC --> FULL{"Memory Capacity<br/>Reached?"}

    FULL -->|Yes| BLOCK["full = 1<br/>New Writes Blocked"]

    FULL -->|No| ALLOW["New Writes Allowed"]
```

The full flag is derived from `wr_ptr_spec`, because speculative entries already occupy physical memory locations.

```verilog
assign full =
    (wr_ptr_spec[ADDR_W-1:0] == rd_ptr[ADDR_W-1:0]) &&
    (wr_ptr_spec[ADDR_W] != rd_ptr[ADDR_W]);
```

Thus, speculative writes cannot overwrite committed or unread data.

---

# 10. Summary

The Transactional FIFO extends a conventional synchronous FIFO by separating:

- **Physical data storage**
- **Committed data visibility**
- **Speculative transaction state**

The three-pointer architecture enables this behavior:

```mermaid
flowchart LR
    RP["rd_ptr<br/>Read Boundary"]

    WA["wr_ptr_actual<br/>Committed Boundary"]

    WS["wr_ptr_spec<br/>Speculative Boundary"]

    RP -->|"Committed Data"| WA

    WA -->|"Speculative Data"| WS
```

This architecture provides transactional behavior without requiring a separate staging memory.

A write immediately consumes FIFO storage, but the data becomes visible only after `commit`. A `rollback` simply restores the speculative boundary to the committed boundary, discarding all uncommitted entries while preserving committed data.