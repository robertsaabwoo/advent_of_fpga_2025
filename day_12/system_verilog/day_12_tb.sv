`timescale 1ns/1ps

module day_12_tb;

    // ------------------------------------------------------------
    // 1. Clock / Reset
    // ------------------------------------------------------------
    logic clk = 0;
    always #5 clk = ~clk;

    logic rst_n;

    // ------------------------------------------------------------
    // 2. DUT I/O
    // ------------------------------------------------------------
    logic        s_tvalid;
    logic        s_tready;
    logic [31:0] s_tdata;

    logic        m_tvalid;
    logic        m_tready;
    logic        m_tlast;
    logic [31:0] m_tdata;

    // ------------------------------------------------------------
    // 3. Instantiate DUT
    // ------------------------------------------------------------
    day_12 dut (
        .clk(clk),
        .rst_n(rst_n),
        .s_tvalid(s_tvalid),
        .s_tready(s_tready),
        .s_tdata(s_tdata),
        .m_tvalid(m_tvalid),
        .m_tready(m_tready),
        .m_tlast(m_tlast),
        .m_tdata(m_tdata)
    );

    // ------------------------------------------------------------
    // 4. SHAPES Definition (Must match DUT)
    // ------------------------------------------------------------
    // 4x4 bitmaps: SHAPES[id][orient][row]
    // 16'hXXXX represents one row
    localparam logic [15:0] SHAPES [0:5][0:3][0:3] = '{
        '{ '{16'h0667,0,0,0}, '{16'h0766,0,0,0}, '{16'h0766,0,0,0}, '{16'h0667,0,0,0} },
        '{ '{16'h0367,0,0,0}, '{16'h0763,0,0,0}, '{16'h0763,0,0,0}, '{16'h0367,0,0,0} },
        '{ '{16'h0673,0,0,0}, '{16'h0376,0,0,0}, '{16'h0376,0,0,0}, '{16'h0673,0,0,0} },
        '{ '{16'h0676,0,0,0}, '{16'h0676,0,0,0}, '{16'h0676,0,0,0}, '{16'h0676,0,0,0} },
        '{ '{16'h0717,0,0,0}, '{16'h0787,0,0,0}, '{16'h0717,0,0,0}, '{16'h0787,0,0,0} },
        '{ '{16'h0727,0,0,0}, '{16'h0747,0,0,0}, '{16'h0727,0,0,0}, '{16'h0747,0,0,0} }
    };

    // Approximate area (number of 1s) for "Impossible" heuristic
    localparam int GIFT_AREA [0:5] = '{5,5,5,5,5,5}; 

    // ------------------------------------------------------------
    // 5. Reference Solver (Software Model)
    // ------------------------------------------------------------
    logic [15:0] ref_board [0:15];
    int gift_list [0:15];   // Fixed size array, big enough for test
    int total_gifts;
    int grid_w, grid_h;     // Dynamic dimensions for verification

    // Helper: Check if piece fits
    function automatic bit fits(int id, int o, int x, int y);
        int r;
        begin
            for (r = 0; r < 4; r = r + 1) begin
                // Check Y bounds
                if (y + r >= grid_h) begin
                    // If the shape actually has pixels in this row, it's out of bounds
                    if (SHAPES[id][o][r] != 0) return 0; 
                end

                if (y + r < 16) begin // Memory safety check
                    // Check X starting position
                    if (x >= grid_w) return 0;
                    
                    // Check collision with existing pieces
                    if ((ref_board[y+r] & (SHAPES[id][o][r] << x)) != 0) return 0;
                    
                    // Check if shifted shape exceeds grid width
                    // Find the highest bit set in the shape row
                    if (SHAPES[id][o][r] != 0) begin
                        int max_bit = 0;
                        for (int b = 0; b < 4; b = b + 1) begin
                            if (SHAPES[id][o][r][b]) max_bit = b;
                        end
                        // If x + max_bit >= grid_w, piece extends beyond grid
                        if ((x + max_bit) >= grid_w) return 0;
                    end
                end
            end
            return 1;
        end
    endfunction

    task automatic place(int id, int o, int x, int y);
        int r;
        begin
            for (r = 0; r < 4; r = r + 1)
                if (y + r < 16)
                    ref_board[y+r] |= (SHAPES[id][o][r] << x);
        end
    endtask

    task automatic remove(int id, int o, int x, int y);
        int r;
        begin
            for (r = 0; r < 4; r = r + 1)
                if (y + r < 16)
                    ref_board[y+r] ^= (SHAPES[id][o][r] << x);
        end
    endtask

    // Recursive Search
    int dfs_call_count;
    int MAX_DFS_CALLS = 5000;  // Aggressively limit to prevent hangs on unsolvable puzzles
    
    function automatic bit dfs(int depth);
        int id, o, x, y;
        begin
            dfs_call_count++;
            if (dfs_call_count > MAX_DFS_CALLS) return 0;  // Give up, assume unsolvable
            
            if (depth == total_gifts) return 1;
            id = gift_list[depth];
            
            // Try all Orientations
            for (o = 0; o < 4; o = o + 1) begin
                if (dfs_call_count > MAX_DFS_CALLS) return 0;  // Check frequently
                
                // Try all Y
                for (y = 0; y < grid_h; y = y + 1) begin
                    if (dfs_call_count > MAX_DFS_CALLS) return 0;  // Check frequently
                    
                    // Try all X
                    for (x = 0; x < grid_w; x = x + 1) begin
                        if (fits(id, o, x, y)) begin
                            place(id, o, x, y);
                            if (dfs(depth + 1)) return 1;
                            remove(id, o, x, y);
                        end
                    end
                end
            end
            return 0;
        end
    endfunction

    function automatic bit reference_solve(int w, int h);
        int i;
        begin
            grid_w = w;
            grid_h = h;
            for (i = 0; i < 16; i = i + 1) ref_board[i] = 0;
            dfs_call_count = 0;
            return dfs(0);
        end
    endfunction

    // ------------------------------------------------------------
    // 6. AXI-Stream Drivers
    // ------------------------------------------------------------
    
    // Send Dimensions FIRST
    task automatic send_dims(input int w, input int h);
        s_tdata  <= {16'b0, 8'(w), 8'(h)};
        s_tvalid <= 1;
        do @(posedge clk); while (!s_tready);
        // Wait 1 cycle after accept (optional, safer for FSMs)
        // @(posedge clk); 
        s_tvalid <= 0;
    endtask

    // Send Counts
    task automatic send_counts(input byte counts [0:5]);
        int i;
        begin
            for (i = 0; i < 6; i = i + 1) begin
                s_tdata  <= {24'b0, counts[i]};
                s_tvalid <= 1;
                do @(posedge clk); while (!s_tready);
            end
            s_tvalid <= 0;
        end
    endtask

    // ------------------------------------------------------------
    // 7. Deadlock Detection
    // ------------------------------------------------------------

    logic [4:0] last_state;  // Match the enum width from day_12 module
    int idle_count = 0;
    int IDLE_THRESHOLD = 150;  // Tune based on your grid sizes

    always @(posedge clk) begin
        if (dut.ram_wen || dut.state != last_state) begin
            idle_count <= 0;
        end else if (dut.state != 5'h0 && dut.state != 5'h11 && dut.state != 5'h1) begin  // S_IDLE=0, S_OUTPUT=16
            idle_count <= idle_count + 1;
        end
        
        last_state <= dut.state;
        
        if (idle_count > IDLE_THRESHOLD) begin
            $error("DEADLOCK: No activity for %0d cycles in state 0x%02h", 
                IDLE_THRESHOLD, dut.state);
            $stop;
        end
    end

    // ------------------------------------------------------------
    // 8. Main Test Loop
    // ------------------------------------------------------------
    initial begin : test_loop
        byte counts [0:5];
        bit ref_result, dut_result;
        int timeout, i, k, current_area;
        int rand_w, rand_h;
        int repeat_count;
        automatic int cycle_count;
        automatic int total_cycles = 0;
        int test_cycles [0:19];

        rst_n    = 0;
        s_tvalid = 0;
        m_tready = 1;

        repeat (5) @(posedge clk);
        rst_n = 1;
        wait (dut.state == 4'd1); // S_IDLE == 1 in DUT enum
        @(posedge clk);
        
        $display("---------------------------------------------------");
        $display("STARTING VERIFICATION");
        $display("---------------------------------------------------");


        repeat_count = 0;
        repeat (20) begin
            // -------------------------------------------------
            // 1. Deterministic Test Cases with Variance
            // -------------------------------------------------
            
            case (repeat_count)
                // Tests 0-4: Small grids, single gift (solvable)
                0: begin rand_w = 4;  rand_h = 4;  counts = '{0:1, default:0}; end
                1: begin rand_w = 6;  rand_h = 6;  counts = '{1:1, default:0}; end
                2: begin rand_w = 8;  rand_h = 8;  counts = '{2:1, default:0}; end
                3: begin rand_w = 5;  rand_h = 7;  counts = '{3:1, default:0}; end
                4: begin rand_w = 9;  rand_h = 5;  counts = '{4:1, default:0}; end
                
                // Tests 5-9: Large grids, multiple gifts (solvable)
                5: begin rand_w = 12; rand_h = 12; counts = '{0:2, 1:1, default:0}; end
                6: begin rand_w = 14; rand_h = 14; counts = '{0:1, 1:1, 2:1, default:0}; end
                7: begin rand_w = 16; rand_h = 16; counts = '{0:2, 1:2, default:0}; end
                8: begin rand_w = 10; rand_h = 14; counts = '{3:1, 4:1, 5:1, default:0}; end
                9: begin rand_w = 13; rand_h = 13; counts = '{0:1, 2:1, 4:1, 5:1, default:0}; end
                
                // Tests 10-14: Medium grids, moderate gifts (mixed)
                10: begin rand_w = 8;  rand_h = 8;  counts = '{0:2, 1:2, default:0}; end
                11: begin rand_w = 6;  rand_h = 10; counts = '{0:1, 1:1, 2:1, 3:1, default:0}; end
                12: begin rand_w = 10; rand_h = 6;  counts = '{0:3, default:0}; end
                13: begin rand_w = 7;  rand_h = 7;  counts = '{1:2, 2:2, default:0}; end
                14: begin rand_w = 9;  rand_h = 9;  counts = '{3:2, 4:1, default:0}; end
                
                // Tests 15-19: Small grids, many gifts (unsolvable)
                15: begin rand_w = 4;  rand_h = 4;  counts = '{0:5, default:0}; end
                16: begin rand_w = 5;  rand_h = 5;  counts = '{0:6, default:0}; end
                17: begin rand_w = 4;  rand_h = 6;  counts = '{0:7, default:0}; end
                18: begin rand_w = 6;  rand_h = 4;  counts = '{1:8, default:0}; end
                19: begin rand_w = 5;  rand_h = 5;  counts = '{0:4, 1:3, 2:2, default:0}; end
            endcase

            total_gifts = 0;
            current_area = 0;

            // Populate linear list for reference solver
            for (i = 0; i < 6; i++) begin
                for (k = 0; k < counts[i]; k++) begin
                    gift_list[total_gifts] = i;
                    total_gifts++;
                    current_area += GIFT_AREA[i];
                end
            end

            // -------------------------------------------------
            // 2. Solve in Software
            // -------------------------------------------------
            ref_result = reference_solve(rand_w, rand_h);
            $display("Test: Grid %0dx%0d, Gifts %0d. Expect: %b", rand_w, rand_h, total_gifts, ref_result);

            // -------------------------------------------------
            // 3. Drive DUT
            // -------------------------------------------------
            send_dims(rand_w, rand_h);
            send_counts(counts);

            $display("data sent successfully");

            // -------------------------------------------------
            // 4. Wait for Result (with cycle counting)
            // -------------------------------------------------
            cycle_count = 0;
            while (!(m_tvalid && m_tlast)) begin
                @(posedge clk);
                cycle_count++;
            end
            
            test_cycles[repeat_count] = cycle_count;
            total_cycles += cycle_count;
            dut_result = m_tdata[0];
            @(posedge clk); // Clear handshake

            // -------------------------------------------------
            // 5. Check
            // -------------------------------------------------
            if (dut_result !== ref_result) begin
                $error("MISMATCH! DUT: %b, REF: %b", dut_result, ref_result);
                $stop;
            end else begin
                $display("  -> PASS (cycles: %0d)", cycle_count);
            end

            rst_n = 0;
            repeat(10) @(posedge clk);
            rst_n = 1;
            wait (dut.state == 4'd1);
            @(posedge clk);
            
            repeat_count = repeat_count + 1;
        end

        $display("---------------------------------------------------");
        $display("ALL TESTS PASSED");
        $display("Total cycles (all 20 tests): %0d", total_cycles);
        $display("Average cycles per test: %0d", total_cycles / 20);
        $display("---------------------------------------------------");
        $finish;
    end

endmodule