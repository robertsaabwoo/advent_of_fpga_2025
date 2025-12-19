`timescale 1ns/1ps

`define NUM_PACKETS 100

module day_3_tb;

    parameter INPUTWIDTH = 64;
    parameter MAXLENGTH = INPUTWIDTH + 4*$ceil(INPUTWIDTH/3);
    parameter integer OUTPUTWIDTH = (MAXLENGTH % 4 ==0)?MAXLENGTH : MAXLENGTH - (MAXLENGTH%4) + 4;

    // Clock & reset
    logic clk;
    logic rst_n;

    // AXI interfaces
    axi_stream_if s_axis_if();
    axi_stream_if m_axis_if();

    // -----------------------------
    // DUT instantiation
    day_3 #(.INPUTWIDTH(INPUTWIDTH)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis(s_axis_if),
        .m_axis(m_axis_if)
    );

    // Clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Reset
    initial begin
        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);
    end

    // -----------------------------
    // Send single AXI word
    task send_word(input logic [INPUTWIDTH-1:0] tdata,input logic [INPUTWIDTH/8-1:0] tkeep, input bit tlast);
        s_axis_if.tdata  = tdata;
        s_axis_if.tkeep  = tkeep;
        s_axis_if.tvalid = 1'b1;
        s_axis_if.tlast  = tlast;
        // Wait until ready
        do @(posedge clk); while (!s_axis_if.tready);
        s_axis_if.tvalid = 1'b0;
        s_axis_if.tlast  = 1'b0;

    endtask

    // Returns 1 if equal, 0 if mismatch
    function automatic longint unsigned get_max(
        input logic [INPUTWIDTH-1:0] decimal_val
    );
        longint unsigned dec_1 = decimal_val;
        longint unsigned dec = 0;
        int unsigned max_digit_1 = 0;
        int unsigned max_digit_2 = 0;
        int unsigned count= 0;
        
        // compare each digit from LSB
        while (dec_1 != 0) begin
            dec += (dec_1%10);
            count += 1;
            dec *= 10;
            dec_1 /= 10;
        end
        for (int i =count; i >=0; i--) begin
            if ((dec % 10 > max_digit_1) && (i != 0)) begin
                max_digit_1 = dec%10;
            end
            else if ((dec % 10 > max_digit_2)) begin
                max_digit_2 = dec%10;
            end
            dec /= 10;
            if (dec == 0) begin
                break;
            end
        end
        return max_digit_1*10+max_digit_2;
    endfunction

    function automatic bit is_valid(
        input int length,
        input logic [INPUTWIDTH-1:0] decimal_val[$],
        input logic [OUTPUTWIDTH-1:0] hw_val  // DUT output
    );

        longint unsigned sum = 0;

        for (int i = 0; i<length; i++) begin
            sum += get_max(decimal_val[i]);
        end

        return sum == hw_val;  // all digits matched
    endfunction

    // -----------------------------
    // Main test
    initial begin
        automatic bit passed = 1;
        @(posedge rst_n);
        $display("Starting packet test...");
        for (int n=0; n<`NUM_PACKETS; n++) begin
            automatic logic [INPUTWIDTH-1:0] val[$] = {};
            automatic int length = $urandom_range(1, 15);
            m_axis_if.tready <= 0;
            for (int i = 0; i< length; i++) begin
                automatic logic [INPUTWIDTH-1:0] temp = $urandom();
                val.push_back(temp);
                send_word(temp, '1, i==(length-1));
            end

            m_axis_if.tready <= 1;
            while (~m_axis_if.tvalid)begin
                 @(posedge clk);
            end
                    
            if (!is_valid(length, val, m_axis_if.tdata)) begin
                $display("Sent:");
                for (int i = 0; i<length; i++) begin
                    $display("%0d", val[i]);
                end
                $display("got %0d", m_axis_if.tdata);
                $warning("Mismatch!");
                passed = 0;
            end

            repeat(1) @(posedge clk);
        end
        if (passed) begin
            $display("All Tests Passed :D");
        end
        $display("Packet test complete.");
        $stop(0);
    end

endmodule