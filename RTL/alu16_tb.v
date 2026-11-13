
`timescale 1ns / 1ps

module alu16_tb;

    reg clk;
    reg [15:0] A, B;
    reg [2:0] opcode;

    wire [15:0] Y;
    wire Z, N, C, V;

    integer i, j, k;
    integer test_count;
    integer seed;

    reg [15:0] vec [0:31];

    // DUT: synchronous input registers, combinational outputs
    alu16 dut (
        .clk(clk),
        .A(A),
        .B(B),
        .opcode(opcode),
        .Y(Y),
        .Z(Z),
        .N(N),
        .C(C),
        .V(V)
    );

    // 10 ns clock period
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------------------------------------
    // Self-checking task
    // ------------------------------------------------
    task automatic check_case;
        input [15:0] ta;
        input [15:0] tb;
        input [2:0] op;

        reg [15:0] ey;
        reg ec, ev, ez, en;
        reg [16:0] tmp;
        reg [3:0] sh;

        begin
            // Compute expected values independently
            ey  = 16'h0000;
            ec  = 1'b0;
            ev  = 1'b0;
            tmp = 17'h00000;
            sh  = tb[3:0];

            case (op)
                3'b000: begin
                    tmp = {1'b0, ta} + {1'b0, tb};
                    ey = tmp[15:0];
                    ec = tmp[16];
                    ev = (~(ta[15] ^ tb[15])) &
                         (ey[15] ^ ta[15]);
                end

                3'b001: begin
                    tmp = {1'b0, ta} +
                          {1'b0, ~tb} + 17'd1;
                    ey = tmp[15:0];
                    ec = tmp[16];
                    ev = (ta[15] ^ tb[15]) &
                         (ey[15] ^ ta[15]);
                end

                3'b010: ey = ta & tb;
                3'b011: ey = ta | tb;
                3'b100: ey = ta ^ tb;
                3'b101: ey = ~ta;

                3'b110: begin
                    ey = ta << sh;
                    if (sh != 0)
                        ec = ta[16-sh];
                end

                3'b111: begin
                    ey = ta >> sh;
                    if (sh != 0)
                        ec = ta[sh-1];
                end

                default: begin
                    ey = 16'h0000;
                    ec = 1'b0;
                    ev = 1'b0;
                end
            endcase

            ez = (ey == 16'h0000);
            en = ey[15];

            // Drive inputs away from the rising edge
            @(negedge clk);
            A = ta;
            B = tb;
            opcode = op;

            // DUT captures inputs at the next rising edge
            @(posedge clk);
            @(posedge clk);

            // Allow nonblocking assignments and combinational
            // logic to settle before checking
            #1;

            if ((Y !== ey) ||
                (Z !== ez) ||
                (N !== en) ||
                (C !== ec) ||
                (V !== ev)) begin

                $display("\n========== TEST FAILED ==========");
                $display("Test number : %0d", test_count + 1);
                $display("Opcode      : %b", op);
                $display("A           : %h", ta);
                $display("B           : %h", tb);
                $display("Expected Y  : %h", ey);
                $display("Actual Y    : %h", Y);
                $display("Expected ZN : %b%b", ez, en);
                $display("Actual ZN   : %b%b", Z, N);
                $display("Expected CV : %b%b", ec, ev);
                $display("Actual CV   : %b%b", C, V);
                $display("=================================\n");

                $fatal(1, "ALU verification failed");
            end

            test_count = test_count + 1;
        end
    endtask

    // ------------------------------------------------
    // Test sequence
    // ------------------------------------------------
    initial begin
        test_count = 0;
        seed = 32'h1234ABCD;

        A = 0;
        B = 0;
        opcode = 0;

        // Boundary-value vectors
        vec[0]  = 16'h0000;
        vec[1]  = 16'h0001;
        vec[2]  = 16'h0002;
        vec[3]  = 16'h0003;
        vec[4]  = 16'h0007;
        vec[5]  = 16'h000F;
        vec[6]  = 16'h0010;
        vec[7]  = 16'h00FF;
        vec[8]  = 16'h0100;
        vec[9]  = 16'h0FFF;
        vec[10] = 16'h1000;
        vec[11] = 16'h3FFF;
        vec[12] = 16'h4000;
        vec[13] = 16'h5555;
        vec[14] = 16'h6666;
        vec[15] = 16'h7FFE;
        vec[16] = 16'h7FFF;
        vec[17] = 16'h8000;
        vec[18] = 16'h8001;
        vec[19] = 16'hAAAA;
        vec[20] = 16'hBFFF;
        vec[21] = 16'hC000;
        vec[22] = 16'hF000;
        vec[23] = 16'hF00F;
        vec[24] = 16'hFF00;
        vec[25] = 16'hFFFE;
        vec[26] = 16'hFFFF;
        vec[27] = 16'h00F0;
        vec[28] = 16'h0F0F;
        vec[29] = 16'h3333;
        vec[30] = 16'hCCCC;
        vec[31] = 16'h8080;

        $display("Starting boundary-vector tests...");

        for (i = 0; i < 32; i = i + 1)
            for (j = 0; j < 32; j = j + 1)
                for (k = 0; k < 8; k = k + 1)
                    check_case(vec[i], vec[j], k[2:0]);

        $display("Starting arithmetic corner cases...");

        // Addition: carry, wraparound and signed overflow
        check_case(16'hFFFF, 16'h0001, 3'b000);
        check_case(16'hFFFF, 16'hFFFF, 3'b000);
        check_case(16'hFFFE, 16'h0002, 3'b000);
        check_case(16'h7FFF, 16'h0001, 3'b000);
        check_case(16'h7FFF, 16'h7FFF, 3'b000);
        check_case(16'h8000, 16'h8000, 3'b000);
        check_case(16'h8000, 16'hFFFF, 3'b000);
        check_case(16'h7FFF, 16'hFFFF, 3'b000);

        // Subtraction: borrow, no borrow and overflow
        check_case(16'h0000, 16'h0000, 3'b001);
        check_case(16'h0000, 16'h0001, 3'b001);
        check_case(16'h0001, 16'h0000, 3'b001);
        check_case(16'hFFFF, 16'h0001, 3'b001);
        check_case(16'h0000, 16'hFFFF, 3'b001);
        check_case(16'h7FFF, 16'hFFFF, 3'b001);
        check_case(16'h8000, 16'h0001, 3'b001);
        check_case(16'h7FFF, 16'h8000, 3'b001);
        check_case(16'h8000, 16'h7FFF, 3'b001);

        // Logic identities
        check_case(16'h0000, 16'hFFFF, 3'b010);
        check_case(16'hFFFF, 16'hFFFF, 3'b010);
        check_case(16'hAAAA, 16'h5555, 3'b011);
        check_case(16'hAAAA, 16'h5555, 3'b100);
        check_case(16'h0000, 16'h0000, 3'b101);
        check_case(16'hFFFF, 16'h0000, 3'b101);

        $display("Starting shift tests...");

        // Every shift amount: 0 through 15
        for (i = 0; i < 16; i = i + 1) begin
            check_case(16'h8001, i, 3'b110);
            check_case(16'h8001, i, 3'b111);
            check_case(16'hFFFF, i, 3'b110);
            check_case(16'hFFFF, i, 3'b111);
            check_case(16'h0001, i, 3'b110);
            check_case(16'h0001, i, 3'b111);
            check_case(16'h0000, i, 3'b110);
            check_case(16'h0000, i, 3'b111);
            check_case(16'hA55A, i, 3'b110);
            check_case(16'hA55A, i, 3'b111);
        end

        $display("Starting randomized tests...");

        for (i = 0; i < 5000; i = i + 1)
            check_case(
                $random(seed),
                $random(seed),
                $random(seed)
            );

        $display("\n====================================");
        $display("ALL TESTS PASSED!");
        $display("Total test cases: %0d", test_count);
        $display("====================================\n");

        $finish;
    end

endmodule
