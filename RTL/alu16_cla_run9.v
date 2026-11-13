module alu16 (
    input  wire        clk,
    input  wire [15:0] A,
    input  wire [15:0] B,
    input  wire [2:0]  opcode,
    output reg  [15:0] Y,
    output reg         Z,
    output reg         N,
    output reg         C,
    output reg         V
);

    // Input pipeline registers: preserve the original two-stage behavior.
    reg [15:0] A_reg;
    reg [15:0] B_reg;
    reg [2:0]  opcode_reg;

    wire       is_sub;
    wire [15:0] B_eff;
    wire [15:0] p;
    wire [15:0] g;
    wire [16:0] carry;
    wire [15:0] cla_sum;

    wire [3:0] P_group;
    wire [3:0] G_group;

    wire [3:0] shift_amount;

    assign is_sub       = (opcode_reg == 3'b001);
    assign B_eff        = B_reg ^ {16{is_sub}};
    assign p            = A_reg ^ B_eff;
    assign g            = A_reg & B_eff;
    assign carry[0]     = is_sub;
    assign shift_amount = B_reg[3:0];

    // Four 4-bit carry-lookahead groups.

    assign G_group[0] = (g[3]) | (p[3] & g[2]) | (p[3] & p[2] & g[1]) | (p[3] & p[2] & p[1] & g[0]);
    assign P_group[0] = (p[3] & p[2] & p[1] & p[0]);
    assign G_group[1] = (g[7]) | (p[7] & g[6]) | (p[7] & p[6] & g[5]) | (p[7] & p[6] & p[5] & g[4]);
    assign P_group[1] = (p[7] & p[6] & p[5] & p[4]);
    assign G_group[2] = (g[11]) | (p[11] & g[10]) | (p[11] & p[10] & g[9]) | (p[11] & p[10] & p[9] & g[8]);
    assign P_group[2] = (p[11] & p[10] & p[9] & p[8]);
    assign G_group[3] = (g[15]) | (p[15] & g[14]) | (p[15] & p[14] & g[13]) | (p[15] & p[14] & p[13] & g[12]);
    assign P_group[3] = (p[15] & p[14] & p[13] & p[12]);

    // Lookahead carries between 4-bit groups.
    assign carry[4]  = G_group[0] | (P_group[0] & carry[0]);
    assign carry[8]  = G_group[1] |
                       (P_group[1] & G_group[0]) |
                       (P_group[1] & P_group[0] & carry[0]);
    assign carry[12] = G_group[2] |
                       (P_group[2] & G_group[1]) |
                       (P_group[2] & P_group[1] & G_group[0]) |
                       (P_group[2] & P_group[1] & P_group[0] & carry[0]);
    assign carry[16] = G_group[3] |
                       (P_group[3] & G_group[2]) |
                       (P_group[3] & P_group[2] & G_group[1]) |
                       (P_group[3] & P_group[2] & P_group[1] & G_group[0]) |
                       (P_group[3] & P_group[2] & P_group[1] & P_group[0] & carry[0]);

    // Lookahead carries within each 4-bit group.

    assign carry[1] = (g[0]) | (p[0] & carry[0]);
    assign carry[2] = (g[1]) | (p[1] & g[0]) | (p[1] & p[0] & carry[0]);
    assign carry[3] = (g[2]) | (p[2] & g[1]) | (p[2] & p[1] & g[0]) | (p[2] & p[1] & p[0] & carry[0]);
    assign carry[5] = (g[4]) | (p[4] & carry[4]);
    assign carry[6] = (g[5]) | (p[5] & g[4]) | (p[5] & p[4] & carry[4]);
    assign carry[7] = (g[6]) | (p[6] & g[5]) | (p[6] & p[5] & g[4]) | (p[6] & p[5] & p[4] & carry[4]);
    assign carry[9] = (g[8]) | (p[8] & carry[8]);
    assign carry[10] = (g[9]) | (p[9] & g[8]) | (p[9] & p[8] & carry[8]);
    assign carry[11] = (g[10]) | (p[10] & g[9]) | (p[10] & p[9] & g[8]) | (p[10] & p[9] & p[8] & carry[8]);
    assign carry[13] = (g[12]) | (p[12] & carry[12]);
    assign carry[14] = (g[13]) | (p[13] & g[12]) | (p[13] & p[12] & carry[12]);
    assign carry[15] = (g[14]) | (p[14] & g[13]) | (p[14] & p[13] & g[12]) | (p[14] & p[13] & p[12] & carry[12]);

    assign cla_sum = p ^ carry[15:0];

    reg [15:0] result_comb;
    reg        carry_comb;
    reg        overflow_comb;

    always @* begin
        result_comb   = 16'h0000;
        carry_comb    = 1'b0;
        overflow_comb = 1'b0;

        case (opcode_reg)
            3'b000: begin // ADD
                result_comb   = cla_sum;
                carry_comb    = carry[16];
                overflow_comb = (~(A_reg[15] ^ B_reg[15])) &
                                (cla_sum[15] ^ A_reg[15]);
            end

            3'b001: begin // SUB
                result_comb   = cla_sum;
                carry_comb    = carry[16]; // 1 means no borrow
                overflow_comb = (A_reg[15] ^ B_reg[15]) &
                                (cla_sum[15] ^ A_reg[15]);
            end

            3'b010: result_comb = A_reg & B_reg;
            3'b011: result_comb = A_reg | B_reg;
            3'b100: result_comb = A_reg ^ B_reg;
            3'b101: result_comb = ~A_reg;

            3'b110: begin // Logical left shift; shift amount is B[3:0]
                result_comb = A_reg << shift_amount;
                if (shift_amount != 0)
                    carry_comb = A_reg[16 - shift_amount];
            end

            3'b111: begin // Logical right shift; shift amount is B[3:0]
                result_comb = A_reg >> shift_amount;
                if (shift_amount != 0)
                    carry_comb = A_reg[shift_amount - 1];
            end

            default: begin
                result_comb   = 16'h0000;
                carry_comb    = 1'b0;
                overflow_comb = 1'b0;
            end
        endcase
    end

    // Output registers retain the same pipeline latency as the RCA design.
    always @(posedge clk) begin
        A_reg      <= A;
        B_reg      <= B;
        opcode_reg <= opcode;

        Y <= result_comb;
        Z <= (result_comb == 16'h0000);
        N <= result_comb[15];
        C <= carry_comb;
        V <= overflow_comb;
    end

endmodule
