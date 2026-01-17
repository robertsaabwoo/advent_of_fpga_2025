`timescale 1ns/1ps

module day_12 #(
    parameter int MAX_X     = 16,
    parameter int MAX_Y     = 16,
    parameter int MAX_GIFTS = 12
)(
    input  logic clk,
    input  logic rst_n,

    // AXI4-Stream
    input  logic        s_tvalid,
    output logic        s_tready,
    input  logic [31:0] s_tdata,

    output logic        m_tvalid,
    input  logic        m_tready,
    output logic        m_tlast,
    output logic [31:0] m_tdata
);

    // ---------------------------------------------------------------------
    // 1. Types & State
    // ---------------------------------------------------------------------
    
    typedef logic [2:0] orient_t; // [2]=Flip, [1:0]=Rot

    typedef enum logic [3:0] {
        S_INIT_SHAPES,
        S_IDLE,
        S_READ_COUNTS,
        S_INIT_CLEAR_RAM,
        S_INIT_EXPAND,
        S_START_SOLVER,
        S_CHECK_PLACE_ADDR,
        S_CHECK_PLACE_WAIT,
        S_CHECK_PLACE_VERIFY,
        S_CHECK_PLACE_WRITE,
        S_NEXT_STEP,
        S_UNDO_ADDR,
        S_UNDO_WAIT,
        S_UNDO_WRITE,
        S_OUTPUT
    } state_e;

    state_e state;
    
    // Pipelining: track next gift to check
    logic [3:0] next_gift_ptr;
    logic       next_gift_valid;

    // ---------------------------------------------------------------------
    // 2. Shape ROM (Pre-Computed)
    // ---------------------------------------------------------------------
    
    // 6 Gifts, 8 Orientations, 4 Rows - stored in runtime ROM loaded at reset
    localparam logic [3:0] SHAPE_INIT [0:5][0:7][0:3] = '{
        // Gift 0: base {0110, 0110, 0111, 0000}
        '{
            '{4'b0110, 4'b0110, 4'b0111, 4'b0000},  // Orient 0 (0 rot, no flip)
            '{4'b0110, 4'b0111, 4'b0011, 4'b0000},  // Orient 1 (90° CW)
            '{4'b0000, 4'b1110, 4'b0110, 4'b0110},  // Orient 2 (180°)
            '{4'b1100, 4'b1110, 4'b0110, 4'b0000},  // Orient 3 (270°)
            '{4'b0110, 4'b1100, 4'b0110, 4'b0000},  // Orient 4 (horiz flip)
            '{4'b0000, 4'b0011, 4'b0110, 4'b1100},  // Orient 5 (flip + 90°)
            '{4'b0000, 4'b0111, 4'b0110, 4'b0100},  // Orient 6 (flip + 180°)
            '{4'b1000, 4'b1110, 4'b0110, 4'b0000}   // Orient 7 (flip + 270°)
        },
        // Gift 1: base {0011, 0110, 0111, 0000}
        '{
            '{4'b0011, 4'b0110, 4'b0111, 4'b0000},  // Orient 0
            '{4'b0110, 4'b0111, 4'b0001, 4'b0000},  // Orient 1
            '{4'b0000, 4'b1110, 4'b0110, 4'b1100},  // Orient 2
            '{4'b1000, 4'b1110, 4'b0110, 4'b0000},  // Orient 3
            '{4'b1100, 4'b1110, 4'b0110, 4'b0000},  // Orient 4
            '{4'b0000, 4'b1110, 4'b0110, 4'b0011},  // Orient 5
            '{4'b0000, 4'b1100, 4'b0110, 4'b1000},  // Orient 6
            '{4'b0010, 4'b1110, 4'b0110, 4'b0000}   // Orient 7
        },
        // Gift 2: base {0110, 0111, 0011, 0000}
        '{
            '{4'b0110, 4'b0111, 4'b0011, 4'b0000},  // Orient 0
            '{4'b1100, 4'b0110, 4'b0110, 4'b0000},  // Orient 1
            '{4'b0000, 4'b1100, 4'b1110, 4'b0110},  // Orient 2
            '{4'b0110, 4'b0110, 4'b0011, 4'b0000},  // Orient 3
            '{4'b1100, 4'b1110, 4'b0110, 4'b0000},  // Orient 4
            '{4'b0000, 4'b0110, 4'b1110, 4'b0011},  // Orient 5
            '{4'b0110, 4'b0111, 4'b0011, 4'b0000},  // Orient 6
            '{4'b1100, 4'b0110, 4'b0110, 4'b0000}   // Orient 7
        },
        // Gift 3: base {0110, 0111, 0110, 0000}
        '{
            '{4'b0110, 4'b0111, 4'b0110, 4'b0000},  // Orient 0
            '{4'b0110, 4'b0111, 4'b0110, 4'b0000},  // Orient 1
            '{4'b0110, 4'b0111, 4'b0110, 4'b0000},  // Orient 2
            '{4'b0110, 4'b0111, 4'b0110, 4'b0000},  // Orient 3
            '{4'b0110, 4'b1100, 4'b0110, 4'b0000},  // Orient 4
            '{4'b0110, 4'b0011, 4'b0110, 4'b0000},  // Orient 5
            '{4'b0110, 4'b0011, 4'b0110, 4'b0000},  // Orient 6
            '{4'b0110, 4'b1100, 4'b0110, 4'b0000}   // Orient 7
        },
        // Gift 4: base {0111, 0001, 0111, 0000}
        '{
            '{4'b0111, 4'b0001, 4'b0111, 4'b0000},  // Orient 0
            '{4'b0110, 4'b0111, 4'b0010, 4'b0000},  // Orient 1
            '{4'b0000, 4'b1110, 4'b0100, 4'b1110},  // Orient 2
            '{4'b0100, 4'b1110, 4'b0110, 4'b0000},  // Orient 3
            '{4'b1110, 4'b0100, 4'b1110, 4'b0000},  // Orient 4
            '{4'b0000, 4'b1110, 4'b0100, 4'b1110},  // Orient 5
            '{4'b0110, 4'b0111, 4'b0010, 4'b0000},  // Orient 6
            '{4'b0100, 4'b1110, 4'b0110, 4'b0000}   // Orient 7
        },
        // Gift 5: base {0111, 0010, 0111, 0000}
        '{
            '{4'b0111, 4'b0010, 4'b0111, 4'b0000},  // Orient 0
            '{4'b0100, 4'b0111, 4'b0110, 4'b0000},  // Orient 1
            '{4'b0000, 4'b1110, 4'b0100, 4'b1110},  // Orient 2
            '{4'b0110, 4'b1110, 4'b0010, 4'b0000},  // Orient 3
            '{4'b1110, 4'b0100, 4'b1110, 4'b0000},  // Orient 4
            '{4'b0000, 4'b1110, 4'b0100, 4'b1110},  // Orient 5
            '{4'b0100, 4'b0111, 4'b0110, 4'b0000},  // Orient 6
            '{4'b0110, 4'b1110, 4'b0010, 4'b0000}   // Orient 7
        }
    };

    logic [3:0] SHAPE_ROM [0:5][0:7][0:3];

    // Loader indices for reset-time initialization
    logic [2:0] load_i; // 0..5
    logic [2:0] load_j; // 0..7
    logic [1:0] load_k; // 0..3

    // ---------------------------------------------------------------------
    // 3. Solver Data
    // ---------------------------------------------------------------------

    logic [7:0] region_w, region_h;
    
    // Stack
    logic [7:0] stack_x [MAX_GIFTS];
    logic [7:0] stack_y [MAX_GIFTS];
    orient_t    stack_orient [MAX_GIFTS];

    logic [2:0] gift_id_list [MAX_GIFTS];
    logic [3:0] gift_ptr;
    logic [3:0] total_gifts; 

    // Grid Memory
    logic [15:0] board_mem [0:15];
    logic [15:0] ram_rdata, ram_wdata;
    logic [3:0]  ram_addr;
    logic        ram_wen;

    // Helpers
    logic [7:0] temp_counts [0:5];
    logic [2:0] input_cnt;
    logic [2:0] row_iter; 
    logic       collision_flag;
    logic [3:0] clear_iter;
    logic       solution_found;
    logic       solution_valid;

    // Undo helpers (recompute mask from stored frame on pop)
    logic [3:0] undo_idx;
    logic [2:0] undo_row_iter;

    // Helper: Generate mask and check bounds
    function automatic logic [15:0] get_shifted_row_mask(
        logic [2:0] id, orient_t orient, logic [7:0] px, logic [7:0] current_row_idx, logic [7:0] py
    );
        logic [7:0] relative_y;
        relative_y = current_row_idx - py;
        
        // Vertical Bounds Check
        if (relative_y > 3 || current_row_idx >= region_h) return 16'd0;
        
        // Shift shape to position X
        return {12'h000, SHAPE_ROM[id][orient][relative_y[1:0]]} << px;
    endfunction
    
    // RAM Inference
    always_ff @(posedge clk) begin
        if (ram_wen) board_mem[ram_addr] <= ram_wdata;
        ram_rdata <= board_mem[ram_addr];
    end

    // ---------------------------------------------------------------------
    // 4. FSM
    // ---------------------------------------------------------------------

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_INIT_SHAPES;
            s_tready <= 0;
            m_tvalid <= 0;
            ram_wen <= 0;
            solution_found <= 0;
            solution_valid <= 0;
            // initialize loader indices
            load_i <= 0;
            load_j <= 0;
            load_k <= 0;
        end else begin
            ram_wen <= 0;
            m_tvalid <= 0;
            m_tlast <= 0;

            case (state)
                // --- SHAPE INIT (reset loader) ---
                S_INIT_SHAPES: begin
                    // Copy one element per cycle from SHAPE_INIT into SHAPE_ROM
                    SHAPE_ROM[load_i][load_j][load_k] <= SHAPE_INIT[load_i][load_j][load_k];

                    // increment indices
                    if (load_k == 2'd3) begin
                        load_k <= 0;
                        if (load_j == 3'd7) begin
                            load_j <= 0;
                            if (load_i == 3'd5) begin
                                // finished loading all shapes
                                state <= S_IDLE;
                            end else begin
                                load_i <= load_i + 1;
                            end
                        end else begin
                            load_j <= load_j + 1;
                        end
                    end else begin
                        load_k <= load_k + 1;
                    end
                end

                // --- INPUT HANDLING ---
                S_IDLE: begin
                    s_tready <= 1;
                    if (s_tvalid) begin
                        region_w <= s_tdata[15:8];
                        region_h <= s_tdata[7:0];
                        input_cnt <= 0;
                        state <= S_READ_COUNTS;
                    end
                end
                S_READ_COUNTS: begin
                    s_tready <= 1;
                    if (s_tvalid) begin
                        temp_counts[input_cnt] <= s_tdata[7:0];
                        if (input_cnt == 5) begin
                            s_tready <= 0;
                            clear_iter <= 0;
                            state <= S_INIT_CLEAR_RAM;
                        end else input_cnt <= input_cnt + 1;
                    end
                end

                S_INIT_CLEAR_RAM: begin
                    ram_addr <= clear_iter;
                    ram_wdata <= 0;
                    ram_wen <= 1;
                    if (clear_iter == 15) begin
                        input_cnt <= 0;
                        total_gifts <= 0;
                        state <= S_INIT_EXPAND;
                    end else clear_iter <= clear_iter + 1;
                end

                S_INIT_EXPAND: begin
                    if (temp_counts[input_cnt] != 0 && total_gifts < MAX_GIFTS) begin
                        gift_id_list[total_gifts] <= input_cnt;
                        temp_counts[input_cnt] <= temp_counts[input_cnt] - 1;
                        total_gifts <= total_gifts + 1;
                    end else if (input_cnt == 5) begin
                        state <= S_START_SOLVER;
                    end else input_cnt <= input_cnt + 1;
                end

                S_START_SOLVER: begin
                    gift_ptr <= 0;
                    next_gift_ptr <= 1;
                    next_gift_valid <= (total_gifts > 1) ? 1 : 0;
                    stack_x[0] <= 0;
                    stack_y[0] <= 0;
                    stack_orient[0] <= 0; 
                    row_iter <= 0;
                    collision_flag <= 0;
                    solution_found <= 0;
                    solution_valid <= 0;
                    state <= S_CHECK_PLACE_ADDR;
                end

                // --- CHECK and PLACE (Single-Pass) ---
                S_CHECK_PLACE_ADDR: begin
                    ram_addr <= (stack_y[gift_ptr] + row_iter) & 4'hF; 
                    state <= S_CHECK_PLACE_WAIT;
                end
                
                S_CHECK_PLACE_WAIT: state <= S_CHECK_PLACE_VERIFY;
                
                S_CHECK_PLACE_VERIFY: begin
                    logic [15:0] mask;
                    logic [15:0] bounds_mask;
                    
                    mask = get_shifted_row_mask(gift_id_list[gift_ptr], stack_orient[gift_ptr], 
                                                stack_x[gift_ptr], ram_addr, stack_y[gift_ptr]);

                    bounds_mask = ~((1 << region_w) - 1);

                    // Check bounds and collision
                    if (ram_addr >= region_h) begin
                        // Row is outside grid bounds - treat as collision
                        state <= S_NEXT_STEP;
                    end else if ( ((ram_rdata & mask) != 0) || ((mask & bounds_mask) != 0) ) begin
                         // Collision detected - move to next position
                         state <= S_NEXT_STEP; 
                    end else begin
                        // No collision - proceed to write this row
                        state <= S_CHECK_PLACE_WRITE;
                    end
                end

                S_CHECK_PLACE_WRITE: begin
                    logic [15:0] mask;
                    mask = get_shifted_row_mask(gift_id_list[gift_ptr], stack_orient[gift_ptr], 
                                                stack_x[gift_ptr], ram_addr, stack_y[gift_ptr]);
                    
                    if (ram_addr < region_h) begin
                        ram_wdata <= ram_rdata | mask;
                        ram_wen <= 1;
                    end

                    if (row_iter < 3) begin
                        // Continue checking and placing remaining rows
                        row_iter <= row_iter + 1;
                        state <= S_CHECK_PLACE_ADDR;
                    end else begin
                        // All rows placed successfully
                        if (gift_ptr == total_gifts - 1) begin
                            // All gifts placed - found solution
                            solution_found <= 1;
                            solution_valid <= 1;
                            state <= S_OUTPUT;
                        end else begin
                            // Move to next gift
                            gift_ptr <= gift_ptr + 1;
                            next_gift_ptr <= gift_ptr + 2;
                            next_gift_valid <= (gift_ptr + 2 < total_gifts) ? 1 : 0;
                            // Initialize next frame's placement
                            stack_x[gift_ptr+1] <= 0;
                            stack_y[gift_ptr+1] <= 0;
                            stack_orient[gift_ptr+1] <= 0;
                            row_iter <= 0;
                            state <= S_CHECK_PLACE_ADDR;
                        end
                    end
                end

                // --- NEXT STEP (Iterate States) ---
                S_NEXT_STEP: begin
                    // Priority: Orient -> X -> Y
                    if (stack_orient[gift_ptr] < 7) begin
                        stack_orient[gift_ptr] <= stack_orient[gift_ptr] + 1;
                        row_iter <= 0;
                        state <= S_CHECK_PLACE_ADDR;
                    end else if (stack_x[gift_ptr] < region_w - 1) begin
                        stack_orient[gift_ptr] <= 0;
                        stack_x[gift_ptr] <= stack_x[gift_ptr] + 1;
                        row_iter <= 0;
                        state <= S_CHECK_PLACE_ADDR;
                    end else if (stack_y[gift_ptr] < region_h - 1) begin
                        stack_orient[gift_ptr] <= 0;
                        stack_x[gift_ptr] <= 0;
                        stack_y[gift_ptr] <= stack_y[gift_ptr] + 1;
                        row_iter <= 0;
                        state <= S_CHECK_PLACE_ADDR;
                    end else begin
                        // Exhausted all positions - backtrack
                        if (gift_ptr == 0) begin
                            // No Solution
                            solution_found <= 0;
                            solution_valid <= 1;
                            state <= S_OUTPUT;
                        end else begin
                            // Backtrack: undo last placed gift (gift_ptr-1) using stored masks
                            undo_idx <= gift_ptr - 1;
                            undo_row_iter <= 0;
                            state <= S_UNDO_ADDR;
                        end
                    end
                end

                // Undo single popped gift by clearing its stored masks from board_mem
                S_UNDO_ADDR: begin
                    ram_addr <= (stack_y[undo_idx] + undo_row_iter) & 4'hF;
                    state <= S_UNDO_WAIT;
                end

                S_UNDO_WAIT: state <= S_UNDO_WRITE;

                S_UNDO_WRITE: begin
                    logic [15:0] mask;
                    mask = get_shifted_row_mask(gift_id_list[undo_idx], stack_orient[undo_idx],
                                                stack_x[undo_idx], ram_addr, stack_y[undo_idx]);

                    if (ram_addr < region_h) begin
                        ram_wdata <= ram_rdata & ~mask;
                        ram_wen <= 1;
                    end

                    if (undo_row_iter < 3) begin
                        undo_row_iter <= undo_row_iter + 1;
                        state <= S_UNDO_ADDR;
                    end else begin
                        // Cleared last placed gift; pop stack and try next position
                        gift_ptr <= undo_idx;
                        row_iter <= 0;
                        next_gift_ptr <= gift_ptr + 1;
                        next_gift_valid <= 1;
                        state <= S_NEXT_STEP;
                    end
                end

                S_OUTPUT: begin
                    m_tvalid <= 1;
                    m_tlast <= 1;
                    m_tdata <= (solution_found & solution_valid); 
                    if (m_tready) state <= S_IDLE;
                end
            endcase
        end
    end

endmodule