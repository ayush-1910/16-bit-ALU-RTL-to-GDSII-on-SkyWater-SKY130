// =============================================================================
// alu16 - HYBRID (balanced area / delay / power)
//
// Merges the two final designs:
//   * RCA design (area/power):  lean register set, shared datapath pieces,
//                               one shifter instead of two, no wide select flops
//   * CLA design (delay):       pre-decode ahead of the input flops, B pre-XORed
//                               with the subtract bit, carry-free zero flag for
//                               ADD/SUB, shallow (2-level) shifter
//
// Same ports, same 2-cycle latency (input regs -> logic -> output regs), same
// results and flags for all 8 opcodes as both parent designs.
//
// Opcodes: 000 ADD  001 SUB  010 AND  011 OR  100 XOR  101 NOT A
//          110 logical shift left   111 logical shift right (amount = B[3:0])
//
// What was measured in the two parent runs (sky130, slowest corner)
//   RCA : worst path = opcode decode -> operand gating -> 4-level mux shifter
//         -> result -> chained 16-input zero detect (Z flag, ~11-12 ns).
//         The ripple adder itself was NOT the limiter (~7-8 ns).
//   CLA : worst path = lookahead adder / zero flag (~6.5 ns), but it spends
//         68 flops, two duplicated one-hot shifters and eight per-unit zero
//         detectors (+~47% area, ~1.7x energy per cycle vs RCA).
//
// What this version takes from each
//   1. ADDER  - 8-bit ripple low half + 8-bit "carry-increment" high half
//               (ripple with cin=0, AND-chain for group propagate, one a21o
//               per bit to merge the real carry).  Far smaller than a 4x4 CLA,
//               roughly half the carry depth of a 16-bit ripple.
//   2. B ^ SUB is done BEFORE the input register (from CLA): the 16 XORs leave
//               the adder path for free (they move across the flop).
//   3. NO operand-isolation AND gates in front of the adder (RCA run 20 had 32
//               of them plus a decode chain: ~2 ns on the critical path for a
//               small power gain).  Results are gated at the final merge only.
//   4. SHIFTER - ONE shared left-rotator (2 levels of one-hot 4:1 AND-OR) plus a
//               thermometer mask.  SRL = rotate-left by (16-n), so there is no
//               input/output bit reversal (RCA: 32 mux2) and no second shifter
//               (CLA: duplicated).  The negate (16-n) is done before the flops.
//               The shift carry-out is just rotator bit 0 (SLL) / bit 15 (SRL).
//   5. LOGIC UNIT shares the adder's p = A^B and g = A&B:
//               AND = g, XOR = p, OR = p|g  -> one 3-term AND-OR per bit.
//   6. FLAGS  - V = carry[15]^carry[16] (no sum bit needed).
//               Z for ADD/SUB uses the carry-free test  (a+b==0) with a single
//               unified XOR row for both ADD and SUB (CLA used two trees);
//               Z for logic ops / shifts is detected from the operands and the
//               shift mask (not from the finished result).  Neither the carry
//               chain nor the shifter therefore feeds a zero-detect tree.
//   7. Registers: 16 A + 16 B^sub + 3 opcode + 3 rotate-amount = 38 input flops
//               (RCA 35, CLA 49) + 20 output flops.
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

    // -------------------------------------------------------------------------
    // 1. Input stage: pre-decode (cheap, has a full clock period) then register
    // -------------------------------------------------------------------------
    reg [15:0] A_reg;
    reg [15:0] Beff_reg;        // B ^ {16{SUB}}  (== B for every opcode but SUB)
    reg [2:0]  op_reg;
    reg [2:0]  rot_hi_reg;      // rotate-left amount bits [3:1] (index 0 -> bit 1); bit 0 == B[0]

    wire in_sub = (opcode == 3'b001);
    wire in_srl = (opcode == 3'b111);

    // rotate-left amount: SLL -> n ; SRL -> (16-n) mod 16 = two's complement of n
    wire [2:0] rot_hi_in;
    assign rot_hi_in[0] = B[1] ^ (in_srl &  B[0]);
    assign rot_hi_in[1] = B[2] ^ (in_srl & (B[1] | B[0]));
    assign rot_hi_in[2] = B[3] ^ (in_srl & (B[2] | B[1] | B[0]));

    always @(posedge clk) begin
        A_reg      <= A;
        Beff_reg   <= B ^ {16{in_sub}};
        op_reg     <= opcode;
        rot_hi_reg <= rot_hi_in;
    end

    // One-hot operation decode (after the flops: arrives long before the data)
    wire op_sub  = (op_reg == 3'b001);
    wire sel_as  = ~op_reg[2] & ~op_reg[1];          // ADD or SUB
    wire sel_and = (op_reg == 3'b010);
    wire sel_or  = (op_reg == 3'b011);
    wire sel_xor = (op_reg == 3'b100);
    wire sel_not = (op_reg == 3'b101);
    wire sel_shl = (op_reg == 3'b110);
    wire sel_shr = (op_reg == 3'b111);

    // -------------------------------------------------------------------------
    // 2. Shared propagate / generate (used by adder AND logic unit)
    // -------------------------------------------------------------------------
    wire [15:0] p = A_reg ^ Beff_reg;
    wire [15:0] g = A_reg & Beff_reg;

    // -------------------------------------------------------------------------
    // 3. Adder / subtractor: ripple low byte + carry-increment high byte
    //    carry-in = op_sub, B already inverted for SUB
    // -------------------------------------------------------------------------
    wire [8:0]  cl;             // low-half carries,  cl[j] = carry into bit j, cl[8] = carry into bit 8
    wire [8:0]  gh;             // high half carry assuming carry-in 0, gh[j] = carry into bit 8+j
    wire [8:0]  ph;             // AND of p[8 .. 8+j-1]  (group propagate)
    wire [16:0] carry;
    wire [15:0] sum;

    assign cl[0] = op_sub;
    assign gh[0] = 1'b0;
    assign ph[0] = 1'b1;

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : LOW
            assign cl[i+1] = g[i] | (p[i] & cl[i]);
        end
        for (i = 0; i < 8; i = i + 1) begin : HIGH
            assign gh[i+1] = g[8+i] | (p[8+i] & gh[i]);
            assign ph[i+1] = p[8+i] & ph[i];
        end
        for (i = 0; i < 8; i = i + 1) begin : LOWC
            assign carry[i] = cl[i];
        end
        for (i = 0; i < 9; i = i + 1) begin : HIGHC
            assign carry[8+i] = gh[i] | (ph[i] & cl[8]);
        end
    endgenerate

    assign sum = p ^ carry[15:0];

    // -------------------------------------------------------------------------
    // 4. Logic unit (AND / OR / XOR / NOT) on the shared p, g
    //    AND = g   OR = p|g   XOR = p   NOT = ~A      (all gated to 0 otherwise)
    // -------------------------------------------------------------------------
    wire use_g = sel_and | sel_or;
    wire use_p = sel_or  | sel_xor;
    wire [15:0] logic_res = (g & {16{use_g}})
                          | (p & {16{use_p}})
                          | (~A_reg & {16{sel_not}});

    // -------------------------------------------------------------------------
    // 5. Shifter: one rotate-left network (2 levels of one-hot 4:1) + mask
    //    SLL n : rotl(A, n)       then keep bits  i >= n
    //    SRL n : rotl(A, 16-n)    then keep bits  i <= 15-n
    // -------------------------------------------------------------------------
    wire [3:0] rot_amt = {rot_hi_reg, Beff_reg[0]};
    wire [3:0] lo_oh = {rot_amt[1:0] == 2'd3, rot_amt[1:0] == 2'd2,
                        rot_amt[1:0] == 2'd1, rot_amt[1:0] == 2'd0};
    wire [3:0] hi_oh = {rot_amt[3:2] == 2'd3, rot_amt[3:2] == 2'd2,
                        rot_amt[3:2] == 2'd1, rot_amt[3:2] == 2'd0};

    // level 1: rotate left by 0..3
    wire [15:0] rot_s1 = ({16{lo_oh[0]}} &  A_reg)
                       | ({16{lo_oh[1]}} & {A_reg[14:0], A_reg[15]})
                       | ({16{lo_oh[2]}} & {A_reg[13:0], A_reg[15:14]})
                       | ({16{lo_oh[3]}} & {A_reg[12:0], A_reg[15:13]});
    // level 2: rotate left by 0 / 4 / 8 / 12
    wire [15:0] rot    = ({16{hi_oh[0]}} &  rot_s1)
                       | ({16{hi_oh[1]}} & {rot_s1[11:0], rot_s1[15:12]})
                       | ({16{hi_oh[2]}} & {rot_s1[7:0],  rot_s1[15:8]})
                       | ({16{hi_oh[3]}} & {rot_s1[3:0],  rot_s1[15:4]});

    // thermometer mask from the shift amount n = B[3:0]  (ready long before rot)
    wire [3:0]  n = Beff_reg[3:0];
    wire [15:0] ge;                                  // ge[i] = (i >= n)
    wire [15:0] smask;
    generate
        for (i = 0; i < 16; i = i + 1) begin : MASK
            assign ge[i] = (n <= i);
        end
        for (i = 0; i < 16; i = i + 1) begin : SMASK
            assign smask[i] = (sel_shl & ge[i]) | (sel_shr & ge[15-i]);
        end
    endgenerate

    wire [15:0] shift_res = rot & smask;

    // bit shifted out last: SLL -> A[16-n] = rot[0] ; SRL -> A[n-1] = rot[15] ; 0 if n == 0
    wire shift_c = (|n) & ((sel_shl & rot[0]) | (sel_shr & rot[15]));

    // -------------------------------------------------------------------------
    // 6. Result merge and flags
    // -------------------------------------------------------------------------
    wire [15:0] other_res   = logic_res | shift_res;
    wire [15:0] result_comb = (sum & {16{sel_as}}) | other_res;

    wire carry_comb    = (sel_as & carry[16]) | shift_c;
    wire overflow_comb = sel_as & (carry[15] ^ carry[16]);

    // zero flag - every class is detected WITHOUT waiting for its own result
    //   ADD/SUB : A + Beff + cin == 0   <=>   p[0] == cin  and  p[i] == (a|b)[i-1]
    //             (one XOR row, no carry chain; holds for ADD and for SUB)
    //   logic   : (logic_res == 0)           - shallow, ready early
    //   shifts  : result is zero  <=>  no source bit survives the mask, i.e.
    //             (A & reverse(smask)) == 0   (reuses the existing mask: SLL by n
    //             keeps source bits j <= 15-n, SRL keeps j >= n)
    wire [15:0] zvec     = p ^ {(A_reg[14:0] | Beff_reg[14:0]), op_sub};
    wire        zero_as  = (zvec == 16'h0000);
    wire        zero_log = (logic_res == 16'h0000);
    wire [15:0] smask_rev;
    generate
        for (i = 0; i < 16; i = i + 1) begin : SREV
            assign smask_rev[i] = smask[15-i];
        end
    endgenerate
    wire        zero_shf = ((A_reg & smask_rev) == 16'h0000);
    wire        zero_comb = (sel_as & zero_as) | (~sel_as & zero_log & zero_shf);

    // -------------------------------------------------------------------------
    // 7. Output registers
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        Y <= result_comb;
        Z <= zero_comb;
        N <= result_comb[15];
        C <= carry_comb;
        V <= overflow_comb;
    end

endmodule
