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
    reg [15:0] B_eff_reg;
    // Decode the opcode before the pipeline boundary and register one-hot
    // controls. This moves opcode decoding off the critical output path.
    reg op_add, op_sub, op_and, op_or;
    reg op_xor, op_not, op_sll, op_srl;

    // Shared add/sub datapath: B XOR subtract control, carry-in = subtract.
    wire       is_sub = op_sub;
    wire [15:0] p = A_reg ^ B_eff_reg;
    wire [15:0] g = A_reg & B_eff_reg;
    wire [16:0] carry;
    wire [15:0] cla_sum;
    wire [3:0]  P_group;
    wire [3:0]  G_group;
    wire [3:0]  shift_amount = B_reg[3:0];

    assign carry[0] = is_sub;

    // Four 4-bit carry-lookahead groups.
    assign G_group[0] = g[3] | (p[3] & g[2]) |
                        (p[3] & p[2] & g[1]) |
                        (p[3] & p[2] & p[1] & g[0]);
    assign P_group[0] = p[3] & p[2] & p[1] & p[0];

    assign G_group[1] = g[7] | (p[7] & g[6]) |
                        (p[7] & p[6] & g[5]) |
                        (p[7] & p[6] & p[5] & g[4]);
    assign P_group[1] = p[7] & p[6] & p[5] & p[4];

    assign G_group[2] = g[11] | (p[11] & g[10]) |
                        (p[11] & p[10] & g[9]) |
                        (p[11] & p[10] & p[9] & g[8]);
    assign P_group[2] = p[11] & p[10] & p[9] & p[8];

    assign G_group[3] = g[15] | (p[15] & g[14]) |
                        (p[15] & p[14] & g[13]) |
                        (p[15] & p[14] & p[13] & g[12]);
    assign P_group[3] = p[15] & p[14] & p[13] & p[12];

    // Lookahead carries between 4-bit groups.
    assign carry[4] = G_group[0] | (P_group[0] & carry[0]);

    assign carry[8] = G_group[1] |
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
    assign carry[1] = g[0] | (p[0] & carry[0]);
    assign carry[2] = g[1] | (p[1] & g[0]) |
                      (p[1] & p[0] & carry[0]);
    assign carry[3] = g[2] | (p[2] & g[1]) |
                      (p[2] & p[1] & g[0]) |
                      (p[2] & p[1] & p[0] & carry[0]);

    assign carry[5] = g[4] | (p[4] & carry[4]);
    assign carry[6] = g[5] | (p[5] & g[4]) |
                      (p[5] & p[4] & carry[4]);
    assign carry[7] = g[6] | (p[6] & g[5]) |
                      (p[6] & p[5] & g[4]) |
                      (p[6] & p[5] & p[4] & carry[4]);

    assign carry[9] = g[8] | (p[8] & carry[8]);
    assign carry[10] = g[9] | (p[9] & g[8]) |
                       (p[9] & p[8] & carry[8]);
    assign carry[11] = g[10] | (p[10] & g[9]) |
                       (p[10] & p[9] & g[8]) |
                       (p[10] & p[9] & p[8] & carry[8]);

    assign carry[13] = g[12] | (p[12] & carry[12]);
    assign carry[14] = g[13] | (p[13] & g[12]) |
                       (p[13] & p[12] & carry[12]);
    assign carry[15] = g[14] | (p[14] & g[13]) |
                       (p[14] & p[13] & g[12]) |
                       (p[14] & p[13] & p[12] & carry[12]);

    assign cla_sum = p ^ carry[15:0];

    // Compute operation results in parallel, then combine using one-hot masks.
    wire [15:0] addsub_result = cla_sum & {16{op_add | op_sub}};
    wire [15:0] and_result    = (A_reg & B_reg) & {16{op_and}};
    wire [15:0] or_result     = (A_reg | B_reg) & {16{op_or}};
    wire [15:0] xor_result    = (A_reg ^ B_reg) & {16{op_xor}};
    wire [15:0] not_result   = (~A_reg) & {16{op_not}};
    wire [15:0] sll_result   = (A_reg << shift_amount) & {16{op_sll}};
    wire [15:0] srl_result   = (A_reg >> shift_amount) & {16{op_srl}};

    wire [15:0] result_comb = addsub_result |
                              and_result |
                              or_result |
                              xor_result |
                              not_result |
                              sll_result |
                              srl_result;

    wire add_overflow = (~(A_reg[15] ^ B_reg[15])) &
                        (cla_sum[15] ^ A_reg[15]);
    wire sub_overflow = (A_reg[15] ^ B_reg[15]) &
                        (cla_sum[15] ^ A_reg[15]);

    wire shift_carry = op_sll
                     ? ((shift_amount != 0) ? A_reg[16 - shift_amount] : 1'b0)
                     : ((shift_amount != 0) ? A_reg[shift_amount - 1'b1] : 1'b0);

    wire carry_comb = ((op_add | op_sub) & carry[16]) |
                      ((op_sll | op_srl) & shift_carry);

    wire overflow_comb = (op_add & add_overflow) |
                         (op_sub & sub_overflow);

    // Output registers retain the same pipeline latency as the RCA design.
    // One-hot controls are captured alongside A_reg and B_reg.
    always @(posedge clk) begin
        A_reg      <= A;
        B_reg      <= B;
        // Precompute B XOR subtract in the input-capture stage.
        // This keeps the same pipeline latency while moving the 16 XORs
        // out of the registered-control-to-result critical path.
        B_eff_reg  <= B ^ {16{(opcode == 3'b001)}};
        op_add <= (opcode == 3'b000);
        op_sub <= (opcode == 3'b001);
        op_and <= (opcode == 3'b010);
        op_or  <= (opcode == 3'b011);
        op_xor <= (opcode == 3'b100);
        op_not <= (opcode == 3'b101);
        op_sll <= (opcode == 3'b110);
        op_srl <= (opcode == 3'b111);

        Y <= result_comb;
        Z <= (result_comb == 16'h0000);
        N <= result_comb[15];
        C <= carry_comb;
        V <= overflow_comb;
    end

endmodule
