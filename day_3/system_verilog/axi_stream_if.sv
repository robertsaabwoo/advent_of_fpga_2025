// ============================================================
// AXI4-Stream Interface
// Fully parameterized for any data width
// Author: rob
// ============================================================

`ifndef AXI_STREAM_IF_SV
`define AXI_STREAM_IF_SV

interface axi_stream_if #(
    parameter int DATA_WIDTH = 64,   // default data width
    parameter int USER_WIDTH = 1     // default user signal width
);

    // Derived parameters
    localparam int KEEP_WIDTH = DATA_WIDTH / 8;

    // -----------------------------
    // AXI4-Stream signals
    // -----------------------------
    logic [DATA_WIDTH-1:0] tdata;
    logic [KEEP_WIDTH-1:0] tkeep;
    logic                  tvalid;
    logic                  tready;
    logic                  tlast;
    logic [USER_WIDTH-1:0] tuser;

    // -----------------------------
    // Optional: typedef for struct
    // -----------------------------
    typedef struct packed {
        logic [DATA_WIDTH-1:0] tdata;
        logic [KEEP_WIDTH-1:0] tkeep;
        logic                  tvalid;
        logic                  tready;
        logic                  tlast;
        logic [USER_WIDTH-1:0] tuser;
    } axis_word_t;

    // -----------------------------
    // Modports
    // -----------------------------
    modport master (
        output tdata, tkeep, tvalid, tlast, tuser,
        input  tready
    );

    modport slave (
        input  tdata, tkeep, tvalid, tlast, tuser,
        output tready
    );

endinterface : axi_stream_if

`endif // AXI_STREAM_IF_SV