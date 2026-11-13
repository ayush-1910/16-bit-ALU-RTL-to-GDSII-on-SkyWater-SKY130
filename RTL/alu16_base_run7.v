
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

    // Input registers
    reg [15:0] A_reg;
    reg [15:0] B_reg;
    reg [2:0]  opcode_reg;

    // Internal combinational ALU signals
    reg [15:0] alu_result;
    reg        alu_Z, alu_N, alu_C, alu_V;

    reg [16:0] arithmetic_tmp;
    reg [3:0]  shift_amt;

    // ---------------------------------------------
    // Input registers
    // ---------------------------------------------
    always @(posedge clk) begin
        A_reg      <= A;
        B_reg      <= B;
        opcode_reg <= opcode;
    end

    // ---------------------------------------------
    // Combinational ALU
    // ---------------------------------------------
    always @(*) begin
        alu_result    = 16'h0000;
        alu_C         = 1'b0;
        alu_V         = 1'b0;
        arithmetic_tmp = 17'h00000;
        shift_amt     = B_reg[3:0];

        case (opcode_reg)

            // ADD
            3'b000: begin
                arithmetic_tmp =
                    {1'b0, A_reg} + {1'b0, B_reg};

                alu_result = arithmetic_tmp[15:0];
                alu_C = arithmetic_tmp[16];
                alu_V = (~(A_reg[15] ^ B_reg[15])) &
                        (alu_result[15] ^ A_reg[15]);
            end

            // SUB: C = 1 means no borrow
            3'b001: begin
                arithmetic_tmp =
                    {1'b0, A_reg} +
                    {1'b0, ~B_reg} + 17'd1;

                alu_result = arithmetic_tmp[15:0];
                alu_C = arithmetic_tmp[16];
                alu_V = (A_reg[15] ^ B_reg[15]) &
                        (alu_result[15] ^ A_reg[15]);
            end

            // AND
            3'b010: alu_result = A_reg & B_reg;

            // OR
            3'b011: alu_result = A_reg | B_reg;

            // XOR
            3'b100: alu_result = A_reg ^ B_reg;

            // NOT A
            3'b101: alu_result = ~A_reg;

            // Logical left shift
            3'b110: begin
                alu_result = A_reg << shift_amt;

                if (shift_amt != 0)
                    alu_C = A_reg[16-shift_amt];
            end

            // Logical right shift
            3'b111: begin
                alu_result = A_reg >> shift_amt;

                if (shift_amt != 0)
                    alu_C = A_reg[shift_amt-1];
            end

            default: begin
                alu_result = 16'h0000;
                alu_C = 1'b0;
                alu_V = 1'b0;
            end

        endcase

        // Result flags
        alu_Z = (alu_result == 16'h0000);
        alu_N = alu_result[15];
    end

    // ---------------------------------------------
    // Output registers
    // ---------------------------------------------
    always @(posedge clk) begin
        Y <= alu_result;
        Z <= alu_Z;
        N <= alu_N;
        C <= alu_C;
        V <= alu_V;
    end

endmodule
