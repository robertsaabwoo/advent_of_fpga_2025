`timescale 1ns/1ps

module day_3 #(
    parameter int INPUTWIDTH = 64,
    parameter int OUTPUTWIDTH = 64
)(
    input  logic clk,
    input  logic rst_n,

    // AXI4-Stream slave
    axi_stream_if.slave s_axis,

    // AXI4-Stream master
    axi_stream_if.master m_axis
);

    localparam integer MAXLENGTH = INPUTWIDTH + 4*$ceil(INPUTWIDTH/3);
    localparam integer DIGITS = (MAXLENGTH % 4 ==0)?MAXLENGTH/4 : MAXLENGTH/4 + 1;
    localparam integer DIGIT_BITS = DIGITS*4;

    logic [OUTPUTWIDTH-1:0] sum;
    logic [INPUTWIDTH-1:0] input_r, input_n;
    logic [3:0] largest_digit;

    logic first_digit;

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
                        first_digit <= 1;
                        state_r <= S_FIND_MAX;
                        max_digit_1_r <= '0;
                        max_digit_2_r <= '0;
                        largest_digit <= '0;
                        state_n <= (s_axis.tlast)? S_OUTPUT : S_IDLE;
                    end
                end
                S_FIND_MAX: begin
                    automatic logic [3:0] digit = input_r % 10;
                    max_digit_1_n = max_digit_1_r;
                    max_digit_2_n = max_digit_2_r;
                    if (first_digit)
                        max_digit_2_n = digit;
                    else if (digit >= max_digit_1_n && first_digit != 1) begin
                        max_digit_1_n = digit;
                        max_digit_2_n = largest_digit; // at this point the largest digit is behind the current
                    end
                    
                    if (input_r == 0) begin
                        state_r <= state_n;
                        sum <= sum + max_digit_1_r*10+ max_digit_2_r;
                    end
                    input_r <= input_r/10;
                    first_digit <= 0;
                    max_digit_1_r <= max_digit_1_n;
                    max_digit_2_r <= max_digit_2_n;
                    largest_digit <= (digit>largest_digit)? digit:largest_digit;
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