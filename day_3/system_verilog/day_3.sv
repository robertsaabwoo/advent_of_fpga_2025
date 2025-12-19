`timescale 1ns/1ps

module day_3 #(
    parameter int INPUTWIDTH = 64
)(
    input  logic clk,
    input  logic rst_n,

    // AXI4-Stream slave
    axi_stream_if.slave s_axis,

    // AXI4-Stream master
    axi_stream_if.master m_axis
);

    localparam MAXLENGTH = INPUTWIDTH + 4*$ceil(INPUTWIDTH/3);
    localparam integer OUTPUTWIDTH = (MAXLENGTH % 4 ==0)?MAXLENGTH : MAXLENGTH - (MAXLENGTH%4) + 4;
    localparam FINAL_WIDTH = 4*OUTPUTWIDTH;

    logic [OUTPUTWIDTH-1:0] output_r;
    logic [OUTPUTWIDTH-1:0] output_n;
    logic [FINAL_WIDTH-1:0] sum;
    logic [INPUTWIDTH-1:0] input_r, input_n;
    logic [$clog2(INPUTWIDTH)-1:0] count;
    logic [$clog2(OUTPUTWIDTH)-1:0] output_count;

    logic [3:0] max_digit_1_r, max_digit_1_n, max_digit_2_r, max_digit_2_n;

    typedef enum logic [2:0] {S_IDLE, S_MATH, S_FIND_MAX, S_OUTPUT} state_e;
    state_e state_r, state_n;
    
    always_comb begin
        s_axis.tready = (state_r == S_IDLE);
    end

    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            state_r <= S_IDLE;
            m_axis.tvalid <= 0;
            sum <= '0;
        end
        else begin
            case(state_r)
                S_IDLE: begin
                    m_axis.tvalid <= 0;
                    if (s_axis.tready && s_axis.tvalid) begin
                        input_r <= s_axis.tdata;
                        output_r <= '0;
                        count <= '0;
                        state_r <= S_MATH;
                        state_n <= (s_axis.tlast)? S_OUTPUT : S_IDLE;
                    end
                end

                S_MATH: begin
                    output_n = output_r;
                    //$display("step 0: output_n = %0h", output_n);
                    for (int i = 0; i<OUTPUTWIDTH/4; i=i+1) begin
                        if (output_n[4*i+:4] >= 5) begin
                            output_n = output_n + ((OUTPUTWIDTH'(3))<<(4*i));
                        end
                    end
                    //$display("step 1: output_n = %0h", output_n);
                    output_n = (output_n<<1);
                    //$display("step 2: output_n = %0h", output_n);
                    output_n = output_n + input_r[INPUTWIDTH-1];
                    //$display("step 3: output_n = %0h", output_n);
                    output_r <= output_n;
                    input_r <= input_r<<1;
                    count <= count+1;
                    if (count == INPUTWIDTH-1) begin
                        state_r <= S_FIND_MAX;
                        output_count <= OUTPUTWIDTH-4;
                        max_digit_1_r <= 0;
                        max_digit_2_r <= 0;
                    end

                end
                S_FIND_MAX: begin
                    automatic logic [3:0] digit = output_r[OUTPUTWIDTH-1-:4];
                    max_digit_1_n = max_digit_1_r;
                    max_digit_2_n = max_digit_2_r;
                    //$display("digit: %0d, output count %0d", digit, output_count);
                    if (digit > max_digit_1_n && output_count != 0) begin
                        max_digit_1_n = digit;
                    end
                    else if (digit > max_digit_2_n) begin
                        max_digit_2_n = digit;
                    end 
                    else if (output_r == 0 || output_count == 0) begin
                        state_r <= state_n;
                        sum <= sum + max_digit_1_r*10+ max_digit_2_r;
                    end
                    output_r <= output_r <<4;
                    output_count <= output_count-4;
                    max_digit_1_r <= max_digit_1_n;
                    max_digit_2_r <= max_digit_2_n;
                end
                S_OUTPUT: begin
                    m_axis.tvalid <= 1'b1;
                    m_axis.tdata  <= sum;
                    if (m_axis.tvalid && m_axis.tready) begin
                        state_r <= S_IDLE;
                        sum <= '0;
                    end
                end
            endcase
        end
    end
endmodule