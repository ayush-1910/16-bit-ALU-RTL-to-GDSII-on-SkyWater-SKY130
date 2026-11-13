// 16-bit ALU with an explicitly implemented Ripple-Carry Adder (RCA)
// Operations: ADD, SUB, AND, OR, XOR, NOT A, logical left/right shift.
// Pipeline: input registers followed by output/flag registers; no reset.

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
    wire [3:0] shift_amount = B_reg[3:0];
    reg [15:0] A_reg;
    reg [15:0] B_reg;
    reg [2:0]  opcode_reg;

    // Shared ripple-carry add/subtract datapath.
    // SUB computes A + (~B) + 1 = A - B.
    wire        is_sub;
    wire [15:0] B_rca;
    wire [16:0] carry;
    wire [15:0] rca_result;

    assign is_sub   = (opcode_reg == 3'b001);
    assign B_rca    = B_reg ^ {16{is_sub}};
    assign carry[0] = is_sub;

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : RCA_STAGE
            wire propagate;
            wire generate_carry;

            assign propagate      = A_reg[i] ^ B_rca[i];
            assign generate_carry = A_reg[i] & B_rca[i];
            assign rca_result[i]  = propagate ^ carry[i];
            assign carry[i+1]     = generate_carry |
                                    (propagate & carry[i]);
        end
    endgenerate

    reg [15:0] result_comb;
    reg        carry_comb;
    reg        overflow_comb;

    always @* begin
        result_comb   = 16'h0000;
        carry_comb    = 1'b0;
        overflow_comb = 1'b0;

        case (opcode_reg)
            3'b000: begin // ADD
                result_comb   = rca_result;
                carry_comb    = carry[16];
                overflow_comb = (~(A_reg[15] ^ B_reg[15])) &
                                (rca_result[15] ^ A_reg[15]);
            end

            3'b001: begin // SUB; carry=1 means no borrow
                result_comb   = rca_result;
                carry_comb    = carry[16];
                overflow_comb = (A_reg[15] ^ B_reg[15]) &
                                (rca_result[15] ^ A_reg[15]);
            end

            3'b010: result_comb = A_reg & B_reg; // AND
            3'b011: result_comb = A_reg | B_reg; // OR
            3'b100: result_comb = A_reg ^ B_reg; // XOR
            3'b101: result_comb = ~A_reg;        // NOT A
            3'b110: begin // Logical left shift
    result_comb = A_reg << shift_amount;

    if (shift_amount != 0)
        carry_comb = A_reg[16 - shift_amount];
end

3'b111: begin // Logical right shift
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

    // Preserve the existing two-edge input-to-output pipeline.
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
