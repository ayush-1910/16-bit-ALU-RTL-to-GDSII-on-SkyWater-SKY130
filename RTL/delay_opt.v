// =============================================================================
// alu16 - CLA design, DELAY-OPTIMIZED version 2
//
// Same ports, same latency (input regs -> logic -> output regs) and the same
// results for every opcode as the supplied CLA design (and as alu16_cla_opt.v).
//
// What the previous run showed (optimized CLA, 20 ns clock, slowest corner):
//   the ten worst paths ALL started at the shift-amount flop and went through
//   the shifter (mux2, mux2, mux4) and then either a 16-input zero check or
//   the final result mux. The CLA adder was about 1.5 ns behind them.
//
// Changes in this version (all target the shifter paths):
//  1. Shift amount is decoded BEFORE the input registers into two one-hot
//     groups (low 2 bits, high 2 bits), registered in their own flops.
//     No decode and no shared high-fanout bit remain after the register.
//  2. The shifters are two levels of one-hot AND-OR (shift by 0..3, then by
//     0/4/8/12) instead of four mux levels. Two levels instead of four.
//  3. The shift zero flag no longer waits for the shifter. SHR result is zero
//     when A & T == 0 with T[k] = (k >= shamt); SHL result is zero when
//     A & reverse(T) == 0. T comes straight from the one-hot flops.
//  4. The shift carry-out (last bit shifted out) uses the same one-hot
//     selects in two AND-OR levels instead of a 16:1 mux.
//  5. AND, OR, XOR and NOT are merged into one logic unit selected early, so
//     the final result/flag select has 4 inputs (add/sub, logic, SHL, SHR)
//     instead of 7.
//  Kept from alu16_cla_opt.v: opcode pre-decode before the input registers,
//  B stored pre-XOR-ed with the subtract bit, per-unit zero flags, carry-free
//  ADD/SUB zero flag, and the unchanged two-level carry-lookahead adder.
//
// Opcodes: 000 ADD  001 SUB  010 AND  011 OR  100 XOR  101 NOT A
//          110 logical shift left   111 logical shift right (amount = B[3:0])
// =============================================================================
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

    // ---------------- 1. input stage: pre-decode, then register ----------------
    reg [15:0] A_reg;
    reg [15:0] Beff_reg;                  // B ^ {16{is_sub}}  (== B except for SUB)
    reg        sub_reg;
    reg        sel_addsub, sel_logic, sel_shl, sel_shr;
    reg        sel_and, sel_or, sel_xor, sel_not;
    reg [3:0]  sh_lo;                     // one-hot of shift amount bits [1:0]
    reg [3:0]  sh_hi;                     // one-hot of shift amount bits [3:2]

    wire in_sub = (opcode == 3'b001);

    always @(posedge clk) begin
        A_reg      <= A;
        Beff_reg   <= B ^ {16{in_sub}};
        sub_reg    <= in_sub;
        sel_addsub <= (opcode[2:1] == 2'b00);          // ADD or SUB
        sel_logic  <= (opcode[2:1] == 2'b01) | (opcode == 3'b100) | (opcode == 3'b101);
        sel_and    <= (opcode == 3'b010);
        sel_or     <= (opcode == 3'b011);
        sel_xor    <= (opcode == 3'b100);
        sel_not    <= (opcode == 3'b101);
        sel_shl    <= (opcode == 3'b110);
        sel_shr    <= (opcode == 3'b111);
        sh_lo      <= 4'b0001 << B[1:0];
        sh_hi      <= 4'b0001 << B[3:2];
    end

    // ---------------- 2. carry-lookahead adder / subtractor ----------------
    wire [15:0] p = A_reg ^ Beff_reg;
    wire [15:0] g = A_reg & Beff_reg;
    wire [16:0] carry;
    wire [15:0] sum;
    wire [3:0]  P_group, G_group;

    assign carry[0] = sub_reg;

    assign G_group[0] = g[3]  | (p[3]  & g[2])  | (p[3]  & p[2]  & g[1])  | (p[3]  & p[2]  & p[1]  & g[0]);
    assign P_group[0] = p[3]  & p[2]  & p[1]  & p[0];
    assign G_group[1] = g[7]  | (p[7]  & g[6])  | (p[7]  & p[6]  & g[5])  | (p[7]  & p[6]  & p[5]  & g[4]);
    assign P_group[1] = p[7]  & p[6]  & p[5]  & p[4];
    assign G_group[2] = g[11] | (p[11] & g[10]) | (p[11] & p[10] & g[9])  | (p[11] & p[10] & p[9]  & g[8]);
    assign P_group[2] = p[11] & p[10] & p[9]  & p[8];
    assign G_group[3] = g[15] | (p[15] & g[14]) | (p[15] & p[14] & g[13]) | (p[15] & p[14] & p[13] & g[12]);
    assign P_group[3] = p[15] & p[14] & p[13] & p[12];

    assign carry[4]  = G_group[0] | (P_group[0] & carry[0]);
    assign carry[8]  = G_group[1] | (P_group[1] & G_group[0]) | (P_group[1] & P_group[0] & carry[0]);
    assign carry[12] = G_group[2] | (P_group[2] & G_group[1]) | (P_group[2] & P_group[1] & G_group[0])
                     | (P_group[2] & P_group[1] & P_group[0] & carry[0]);
    assign carry[16] = G_group[3] | (P_group[3] & G_group[2]) | (P_group[3] & P_group[2] & G_group[1])
                     | (P_group[3] & P_group[2] & P_group[1] & G_group[0])
                     | (P_group[3] & P_group[2] & P_group[1] & P_group[0] & carry[0]);

    assign carry[1]  = g[0]  | (p[0]  & carry[0]);
    assign carry[2]  = g[1]  | (p[1]  & g[0])  | (p[1]  & p[0]  & carry[0]);
    assign carry[3]  = g[2]  | (p[2]  & g[1])  | (p[2]  & p[1]  & g[0])  | (p[2]  & p[1]  & p[0]  & carry[0]);
    assign carry[5]  = g[4]  | (p[4]  & carry[4]);
    assign carry[6]  = g[5]  | (p[5]  & g[4])  | (p[5]  & p[4]  & carry[4]);
    assign carry[7]  = g[6]  | (p[6]  & g[5])  | (p[6]  & p[5]  & g[4])  | (p[6]  & p[5]  & p[4]  & carry[4]);
    assign carry[9]  = g[8]  | (p[8]  & carry[8]);
    assign carry[10] = g[9]  | (p[9]  & g[8])  | (p[9]  & p[8]  & carry[8]);
    assign carry[11] = g[10] | (p[10] & g[9])  | (p[10] & p[9]  & g[8])  | (p[10] & p[9]  & p[8]  & carry[8]);
    assign carry[13] = g[12] | (p[12] & carry[12]);
    assign carry[14] = g[13] | (p[13] & g[12]) | (p[13] & p[12] & carry[12]);
    assign carry[15] = g[14] | (p[14] & g[13]) | (p[14] & p[13] & g[12]) | (p[14] & p[13] & p[12] & carry[12]);

    assign sum = p ^ carry[15:0];

    // zero flag of the adder result without waiting for the carry chain
    wire [15:0] add_zero_vec = p ^ {(A_reg[14:0] | Beff_reg[14:0]), 1'b0};
    wire add_zero    = (add_zero_vec == 16'h0000);        // ADD: a + b == 0 (mod 2^16)
    wire sub_zero    = (p == 16'hFFFF);                   // SUB: a == b
    wire addsub_zero = sub_reg ? sub_zero : add_zero;

    // ---------------- 3. logic unit (AND / OR / XOR / NOT merged) ----------------
    wire [15:0] and_res = A_reg & Beff_reg;
    wire [15:0] or_res  = A_reg | Beff_reg;
    wire [15:0] xor_res = p;                              // A ^ B whenever XOR is selected
    wire [15:0] not_res = ~A_reg;

    wire [15:0] logic_res = ({16{sel_and}} & and_res) | ({16{sel_or}} & or_res)
                          | ({16{sel_xor}} & xor_res) | ({16{sel_not}} & not_res);

    wire and_zero = (and_res == 16'h0000);
    wire or_zero  = (A_reg == 16'h0000) && (Beff_reg == 16'h0000);
    wire xor_zero = (p == 16'h0000);
    wire not_zero = (A_reg == 16'hFFFF);
    wire logic_zero = (sel_and & and_zero) | (sel_or & or_zero) | (sel_xor & xor_zero) | (sel_not & not_zero);

    // ---------------- 4. shifters: two levels of one-hot AND-OR ----------------
    // shift left
    wire [15:0] shl_s1 = ({16{sh_lo[0]}} & A_reg)
                       | ({16{sh_lo[1]}} & {A_reg[14:0], 1'b0})
                       | ({16{sh_lo[2]}} & {A_reg[13:0], 2'b00})
                       | ({16{sh_lo[3]}} & {A_reg[12:0], 3'b000});
    wire [15:0] shl_res = ({16{sh_hi[0]}} & shl_s1)
                        | ({16{sh_hi[1]}} & {shl_s1[11:0], 4'b0000})
                        | ({16{sh_hi[2]}} & {shl_s1[7:0],  8'h00})
                        | ({16{sh_hi[3]}} & {shl_s1[3:0],  12'h000});
    // shift right (logical)
    wire [15:0] shr_s1 = ({16{sh_lo[0]}} & A_reg)
                       | ({16{sh_lo[1]}} & {1'b0,   A_reg[15:1]})
                       | ({16{sh_lo[2]}} & {2'b00,  A_reg[15:2]})
                       | ({16{sh_lo[3]}} & {3'b000, A_reg[15:3]});
    wire [15:0] shr_res = ({16{sh_hi[0]}} & shr_s1)
                        | ({16{sh_hi[1]}} & {4'b0000,  shr_s1[15:4]})
                        | ({16{sh_hi[2]}} & {8'h00,    shr_s1[15:8]})
                        | ({16{sh_hi[3]}} & {12'h000,  shr_s1[15:12]});

    // thermometer T[k] = (k >= shamt), straight from the one-hot flops
    //   T[4a+b] = (a > hi) | (a == hi & b >= lo)
    wire [3:0] hi_lt = {sh_hi[2] | sh_hi[1] | sh_hi[0], sh_hi[1] | sh_hi[0], sh_hi[0], 1'b0}; // hi < a
    wire [3:0] lo_le = {1'b1, ~sh_lo[3], ~(sh_lo[3] | sh_lo[2]), sh_lo[0]};                    // lo <= b
    wire [15:0] T;
    genvar a, b;
    generate
        for (a = 0; a < 4; a = a + 1) begin : TA
            for (b = 0; b < 4; b = b + 1) begin : TB
                assign T[4*a + b] = hi_lt[a] | (sh_hi[a] & lo_le[b]);
            end
        end
    endgenerate

    // SHR result is zero when no bit of A at positions >= shamt is set
    wire shr_zero = ((A_reg & T) == 16'h0000);
    // SHL result is zero when no bit of A at positions <= 15 - shamt is set
    wire [15:0] T_rev;
    generate
        for (a = 0; a < 16; a = a + 1) begin : TR
            assign T_rev[a] = T[15 - a];
        end
    endgenerate
    wire shl_zero = ((A_reg & T_rev) == 16'h0000);

    // shift carry-out: last bit shifted out (0 when the amount is 0)
    //   SHL: A[16 - shamt]      SHR: A[shamt - 1]
    wire shr_c_g0 = (sh_lo[1] & A_reg[0])  | (sh_lo[2] & A_reg[1])  | (sh_lo[3] & A_reg[2]);
    wire shr_c_g1 = (sh_lo[0] & A_reg[3])  | (sh_lo[1] & A_reg[4])  | (sh_lo[2] & A_reg[5])  | (sh_lo[3] & A_reg[6]);
    wire shr_c_g2 = (sh_lo[0] & A_reg[7])  | (sh_lo[1] & A_reg[8])  | (sh_lo[2] & A_reg[9])  | (sh_lo[3] & A_reg[10]);
    wire shr_c_g3 = (sh_lo[0] & A_reg[11]) | (sh_lo[1] & A_reg[12]) | (sh_lo[2] & A_reg[13]) | (sh_lo[3] & A_reg[14]);
    wire shr_c = (sh_hi[0] & shr_c_g0) | (sh_hi[1] & shr_c_g1) | (sh_hi[2] & shr_c_g2) | (sh_hi[3] & shr_c_g3);

    wire shl_c_g0 = (sh_lo[1] & A_reg[15]) | (sh_lo[2] & A_reg[14]) | (sh_lo[3] & A_reg[13]);
    wire shl_c_g1 = (sh_lo[0] & A_reg[12]) | (sh_lo[1] & A_reg[11]) | (sh_lo[2] & A_reg[10]) | (sh_lo[3] & A_reg[9]);
    wire shl_c_g2 = (sh_lo[0] & A_reg[8])  | (sh_lo[1] & A_reg[7])  | (sh_lo[2] & A_reg[6])  | (sh_lo[3] & A_reg[5]);
    wire shl_c_g3 = (sh_lo[0] & A_reg[4])  | (sh_lo[1] & A_reg[3])  | (sh_lo[2] & A_reg[2])  | (sh_lo[3] & A_reg[1]);
    wire shl_c = (sh_hi[0] & shl_c_g0) | (sh_hi[1] & shl_c_g1) | (sh_hi[2] & shl_c_g2) | (sh_hi[3] & shl_c_g3);

    // ---------------- 5. final select (4 inputs) of result and flags together ----------------
    wire [15:0] result_comb =
          ({16{sel_addsub}} & sum)
        | ({16{sel_logic}}  & logic_res)
        | ({16{sel_shl}}    & shl_res)
        | ({16{sel_shr}}    & shr_res);

    wire zero_comb =
          (sel_addsub & addsub_zero)
        | (sel_logic  & logic_zero)
        | (sel_shl    & shl_zero)
        | (sel_shr    & shr_zero);

    wire carry_comb    = (sel_addsub & carry[16]) | (sel_shl & shl_c) | (sel_shr & shr_c);
    wire overflow_comb = sel_addsub & ~(A_reg[15] ^ Beff_reg[15]) & (sum[15] ^ A_reg[15]);

    // ---------------- 6. output registers ----------------
    always @(posedge clk) begin
        Y <= result_comb;
        Z <= zero_comb;
        N <= result_comb[15];
        C <= carry_comb;
        V <= overflow_comb;
    end

endmodule
