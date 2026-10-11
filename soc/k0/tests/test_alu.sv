`timescale 1ns/1ps
import isa_shared::*;

module test_alu;

  localparam int DATA_WIDTH = 32;
  reg test_failed;

  task finish;
    begin
      if (test_failed) begin
        $display("Test failed!");
      end else begin
        $display("Test passed!");
      end
      $finish; // End simulation
    end
  endtask

  // dut io
  reg [DATA_WIDTH-1:0] a;
  reg [DATA_WIDTH-1:0] b;
  alu_ops_e alu_op; // ALU operation code

  wire [DATA_WIDTH-1:0] result;
  wire zero; // zero flag
  wire carry; // carry flag
  wire overflow; // overflow flag

  reg expected_carry;
  reg expected_overflow;
  reg [DATA_WIDTH-1:0] expected_result; // one bit wider to capture carry out

  // dut instantiation
  alu #(
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .a(a),
    .b(b),
    .alu_op(alu_op),
    .result(result),
    .zero(zero),
    .carry(carry),
    .overflow(overflow)
  );


  // result must equal expected for the given operation and operands
  task check_op(input alu_ops_e op, input [DATA_WIDTH-1:0] sa, input [DATA_WIDTH-1:0] sb, input [DATA_WIDTH-1:0] expected);
    begin
      alu_op = op;
      a = sa;
      b = sb;
      #(1);
      if (result !== expected) begin
        test_failed = 1;
        $display("[%0t] error: operation=%s a=0x%08x b=0x%08x expected 0x%08x, got 0x%08x", $time, op.name(), sa, sb, expected, result);
      end
    end
  endtask

  // test case
  initial begin
    $dumpfile("./tests/results/test_alu.vcd");
    $dumpvars(0, test_alu);
    test_failed = 0;
    expected_carry = 0;
    expected_overflow = 0;

    alu_op = ALU_ADD;
    a = 32'h0000_1234;
    b = 32'h0000_5678;
    expected_result = a + b;
    expected_carry = 0;
    expected_overflow = 0;
    #(1);
    if (result !== expected_result || carry !== expected_carry || overflow !== expected_overflow) begin
      test_failed = 1;
      $display("[%0t] error: a=0x%h, b=0x%h, operation=ADD, result=0x%h (got 0x%h), carry=%b (got %b), overflow=%b (got %b)", $time, a, b, expected_result, result, expected_carry, carry, expected_overflow, overflow);
    end
    a = 32'hFFFF_FFFF; // 4294967294
    b = 32'h0000_0001; // 1
    expected_result = a + b;
    expected_carry = 1;
    expected_overflow = 0;
    #(1);
    if (result !== expected_result || carry !== expected_carry || overflow !== expected_overflow) begin
      test_failed = 1;
      $display("[%0t] error: a=0x%h, b=0x%h, operation=ADD, result=0x%h (got 0x%h), carry=%b (got %b), overflow=%b (got %b)", $time, a, b, expected_result, result, expected_carry, carry, expected_overflow, overflow);
    end
    a = 32'h7fff_ffff; // +2147483647
    b = 32'h0000_0001; // +1
    expected_result = a + b;
    expected_carry = 0;
    expected_overflow = 1;
    #(1);
    if (result !== expected_result || carry !== expected_carry || overflow !== expected_overflow) begin
      test_failed = 1;
      $display("[%0t] error: a=0x%h, b=0x%h, operation=ADD, result=0x%h (got 0x%h), carry=%b (got %b), overflow=%b (got %b)", $time, a, b, expected_result, result, expected_carry, carry, expected_overflow, overflow);
    end
    a = 32'h8000_0000; // -2147483648
    b = 32'h8000_0000; // -2147483648
    expected_result = a + b;
    expected_carry = 1;
    expected_overflow = 1;
    #(1);
    if (result !== expected_result || carry !== expected_carry || overflow !== expected_overflow) begin
      test_failed = 1;
      $display("[%0t] error: a=0x%h, b=0x%h, operation=ADD, result=0x%h (got 0x%h), carry=%b (got %b), overflow=%b (got %b)", $time, a, b, expected_result, result, expected_carry, carry, expected_overflow, overflow);
    end

    alu_op = ALU_SUB;
    a = 32'h0000_5678; // 22136
    b = 32'h0000_1234; // 4660
    expected_result = a - b; // 17476
    expected_carry = 0;
    expected_overflow = 0;
    #(1);
    if (result !== expected_result || carry !== expected_carry || overflow !== expected_overflow) begin
      test_failed = 1;
      $display("[%0t] error: a=0x%h, b=0x%h, operation=SUB, result=0x%h (got 0x%h), carry=%b (got %b), overflow=%b (got %b)", $time, a, b, expected_result, result, expected_carry, carry, expected_overflow, overflow);
    end
    a = 32'h0000_0005; // 5
    b = 32'h0000_000a; // 10
    expected_result = a - b; // -5 -> 0xFFFF_FFFB
    expected_carry = 1;
    expected_overflow = 0;
    #(1);
    if (result !== expected_result || carry !== expected_carry || overflow !== expected_overflow) begin
      test_failed = 1;
      $display("[%0t] error: a=0x%h, b=0x%h, operation=SUB, result=0x%h (got 0x%h), carry=%b (got %b), overflow=%b (got %b)", $time, a, b, expected_result, result, expected_carry, carry, expected_overflow, overflow);
    end
    a = 32'h8000_0000; // -2147483648
    b = 32'h0000_0001; // +1
    expected_result = a - b; // +2147483647
    expected_carry = 0;
    expected_overflow = 1;
    #(1);
    if (result !== expected_result || carry !== expected_carry || overflow !== expected_overflow) begin
      test_failed = 1;
      $display("[%0t] error: a=0x%h, b=0x%h, operation=SUB, result=0x%h (got 0x%h), carry=%b (got %b), overflow=%b (got %b)", $time, a, b, expected_result, result, expected_carry, carry, expected_overflow, overflow);
    end
    a = 32'h7fff_ffff; // +2147483647
    b = 32'h8000_0000; // -2147483648
    expected_result = a - b; // -1 -> 0xFFFF_FFFF
    expected_carry = 1;
    expected_overflow = 1;
    #(1);
    if (result !== expected_result || carry !== expected_carry || overflow !== expected_overflow) begin
      test_failed = 1;
      $display("[%0t] error: a=0x%h, b=0x%h, operation=SUB, result=0x%h (got 0x%h), carry=%b (got %b), overflow=%b (got %b)", $time, a, b, expected_result, result, expected_carry, carry, expected_overflow, overflow);
    end

    // reset
    expected_carry = 0;
    expected_overflow = 0;

    alu_op = ALU_EQUALS;
    a = 32'h0000_1234;
    b = 32'h0000_1234;
    #(1); // wait one time unit
    if (result !== 1) begin
      test_failed = 1;
      $display("[%0t] error: operation=EQUALS, expected result 0x1, got 0x%h", $time, result);
    end
    a = 32'h0000_1234;
    b = 32'h0000_5678;
    #(1); // wait one time unit
    if (result !== 0) begin
      test_failed = 1;
      $display("[%0t] error: operation=EQUALS, expected result 0x0, got 0x%h", $time, result);
    end

    alu_op = ALU_NOT_EQUALS;
    a = 32'h0000_1234;
    b = 32'h0000_5678;
    #(1); // wait one time unit
    if (result !== 1) begin
      test_failed = 1;
      $display("[%0t] error: operation=NOT_EQUALS, expected result 0x1, got 0x%h", $time, result);
    end
    a = 32'h0000_1234;
    b = 32'h0000_1234;
    #(1); // wait one time unit
    if (result !== 0) begin
      test_failed = 1;
      $display("[%0t] error: operation=NOT_EQUALS, expected result 0x0, got 0x%h", $time, result);
    end

    alu_op = ALU_NOP;
    #(1); // wait one time unit
    if (result !== 0) begin
      test_failed = 1;
      $display("[%0t] error: operation=NOP, expected result 0x0, got 0x%h", $time, result);
    end

    // a<b signed (ALU_LT), a>=b signed (ALU_GE), a<b unsigned (ALU_LTU), a >=b unsigned (ALU_GEU)
    alu_op = ALU_LT;
    a = 32'h0000_1234; // 4660
    b = 32'h0000_5678; // 22136
    #(1);
    if (result !== 1) begin
      test_failed = 1;
      $display("[%0t] error: operation=LT, expected result 0x1, got 0x%h", $time, result);
    end
    a = 32'hFFFF_FFFF; // -1
    b = 32'h0000_0001; // +1
    #(1);
    if (result !== 1) begin
      test_failed = 1;
      $display("[%0t] error: operation=LT, expected result 0x1, got 0x%h", $time, result);
    end
    a = 32'h7FFF_FFFF; // +2147483647
    b = 32'h8000_0000; // -2147483648
    #(1);
    if (result !== 0) begin
      test_failed = 1;
      $display("[%0t] error: operation=LT, expected result 0x0, got 0x%h", $time, result);
    end
    a = 32'h8000_0000; // -2147483648
    b = 32'h7FFF_FFFF; // +2147483647
    #(1);
    if (result !== 1) begin
      test_failed = 1;
      $display("[%0t] error: operation=LT, expected result 0x1, got 0x%h", $time, result);
    end
    a = 32'h0000_5678; // 22136
    b = 32'h0000_1234; // 4660
    #(1);
    if (result !== 0) begin
      test_failed = 1;
      $display("[%0t] error: operation=LT, expected result 0x0, got 0x%h", $time, result);
    end

    alu_op = ALU_GE;
    a = 32'h0000_5678; // 22136
    b = 32'h0000_1234; // 4660
    #(1);
    if (result !== 1) begin
      test_failed = 1;
      $display("[%0t] error: operation=GE, expected result 0x1, got 0x%h", $time, result);
    end
    a = 32'hFFFF_FFFF; // -1
    b = 32'h0000_0001; // +1
    #(1);
    if (result !== 0) begin
      test_failed = 1;
      $display("[%0t] error: operation=GE, expected result 0x0, got 0x%h", $time, result);
    end
    a = 32'h7FFF_FFFF; // +2147483647
    b = 32'h8000_0000; // -2147483648
    #(1);
    if (result !== 1) begin
      test_failed = 1;
      $display("[%0t] error: operation=GE, expected result 0x1, got 0x%h", $time, result);
    end
    a = 32'h8000_0000; // -2147483648
    b = 32'h7FFF_FFFF; // +2147483647
    #(1);
    if (result !== 0) begin
      test_failed = 1;
      $display("[%0t] error: operation=GE, expected result 0x0, got 0x%h", $time, result);
    end
    a = 32'h0000_1234; // 4660
    b = 32'h0000_5678; // 22136
    #(1);
    if (result !== 0) begin
      test_failed = 1;
      $display("[%0t] error: operation=GE, expected result 0x0, got 0x%h", $time, result);
    end
    a = 32'h0000_1234; // 4660
    b = 32'h0000_1234; // 4660
    #(1);
    if (result !== 1) begin
      test_failed = 1;
      $display("[%0t] error: operation=GE, expected result 0x1, got 0x%h", $time, result);
    end

    alu_op = ALU_LTU;
    a = 32'h0000_1234; // 4660
    b = 32'h0000_5678; // 22136
    #(1);
    if (result !== 1) begin
      test_failed = 1;
      $display("[%0t] error: operation=LTU, expected result 0x1, got 0x%h", $time, result);
    end
    a = 32'hFFFF_FFFF; // 4294967295
    b = 32'h0000_0001; // 1
    #(1);
    if (result !== 0) begin
      test_failed = 1;
      $display("[%0t] error: operation=LTU, expected result 0x0, got 0x%h", $time, result);
    end
    a = 32'h8000_0000; // 2147483648
    b = 32'h7FFF_FFFF; // 2147483647
    #(1);
    if (result !== 0) begin
      test_failed = 1;
      $display("[%0t] error: operation=LTU, expected result 0x0, got 0x%h", $time, result);
    end
    a = 32'h7FFF_FFFF; // 2147483647
    b = 32'h8000_0000; // 2147483648
    #(1);
    if (result !== 1) begin
      test_failed = 1;
      $display("[%0t] error: operation=LTU, expected result 0x1, got 0x%h", $time, result);
    end
    a = 32'h0000_5678; // 22136
    b = 32'h0000_1234; // 4660
    #(1);
    if (result !== 0) begin
      test_failed = 1;
      $display("[%0t] error: operation=LTU, expected result 0x0, got 0x%h", $time, result);
    end
    a = 32'h0000_1234; // 4660
    b = 32'h0000_1234; // 4660
    #(1);
    if (result !== 0) begin
      test_failed = 1;
      $display("[%0t] error: operation=LTU, expected result 0x0, got 0x%h", $time, result);
    end

    alu_op = ALU_GEU;
    a = 32'h0000_5678; // 22136
    b = 32'h0000_1234; // 4660
    #(1);
    if (result !== 1) begin
      test_failed = 1;
      $display("[%0t] error: operation=GEU, expected result 0x1, got 0x%h", $time, result);
    end
    a = 32'hFFFF_FFFF; // 4294967295
    b = 32'h0000_0001; // 1
    #(1);
    if (result !== 1) begin
      test_failed = 1;
      $display("[%0t] error: operation=GEU, expected result 0x1, got 0x%h", $time, result);
    end
    a = 32'h8000_0000; // 2147483648
    b = 32'h7FFF_FFFF; // 2147483647
    #(1);
    if (result !== 1) begin
      test_failed = 1;
      $display("[%0t] error: operation=GEU, expected result 0x1, got 0x%h", $time, result);
    end
    a = 32'h7FFF_FFFF; // 2147483647
    b = 32'h8000_0000; // 2147483648
    #(1);
    if (result !== 0) begin
      test_failed = 1;
      $display("[%0t] error: operation=GEU, expected result 0x0, got 0x%h", $time, result);
    end
    a = 32'h0000_1234; // 4660
    b = 32'h0000_5678; // 22136
    #(1);
    if (result !== 0) begin
      test_failed = 1;
      $display("[%0t] error: operation=GEU, expected result 0x0, got 0x%h", $time, result);
    end
    a = 32'h0000_1234; // 4660
    b = 32'h0000_1234; // 4660
    #(1);
    if (result !== 1) begin
      test_failed = 1;
      $display("[%0t] error: operation=GEU, expected result 0x1, got 0x%h", $time, result);
    end

    // shifts use only the low 5 bits of b as the shift amount
    check_op(ALU_SLL, 32'h0000_0001, 32'd0, 32'h0000_0001);
    check_op(ALU_SLL, 32'h0000_0001, 32'd31, 32'h8000_0000);
    check_op(ALU_SLL, 32'h0000_0001, 32'd32, 32'h0000_0001); // 32 -> 0
    check_op(ALU_SLL, 32'h0000_0001, 32'hFFFF_FFC1, 32'h0000_0002); // upper bits ignored, amount = 1
    check_op(ALU_SLL, 32'hFFFF_FFFF, 32'd4, 32'hFFFF_FFF0);

    check_op(ALU_SRL, 32'h8000_0000, 32'd0, 32'h8000_0000);
    check_op(ALU_SRL, 32'h8000_0000, 32'd31, 32'h0000_0001);
    check_op(ALU_SRL, 32'h8000_0000, 32'd32, 32'h8000_0000);
    check_op(ALU_SRL, 32'hFFFF_FFFF, 32'hFFFF_FFC4, 32'h0FFF_FFFF); // amount = 4, zero fill
    check_op(ALU_SRL, 32'h0000_00F0, 32'd4, 32'h0000_000F);

    check_op(ALU_SRA, 32'h8000_0000, 32'd31, 32'hFFFF_FFFF); // sign fill
    check_op(ALU_SRA, 32'h8000_0000, 32'd4, 32'hF800_0000);
    check_op(ALU_SRA, 32'h7FFF_FFFF, 32'd4, 32'h07FF_FFFF); // positive stays positive
    check_op(ALU_SRA, 32'hF000_0000, 32'hFFFF_FFC4, 32'hFF00_0000); // amount = 4
    check_op(ALU_SRA, 32'h8000_0000, 32'd32, 32'h8000_0000);

    // m extension. mulh* return the upper 32 bits of the 64 bit product.
    check_op(ALU_MUL, 32'd3, 32'd4, 32'd12);
    check_op(ALU_MUL, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'h0000_0001); // (-1)*(-1), lower half
    check_op(ALU_MUL, 32'h8000_0000, 32'd2, 32'h0000_0000); // overflow wraps
    check_op(ALU_MUL, 32'h1234_5678, 32'h0000_1000, 32'h4567_8000);

    check_op(ALU_MULH, 32'd3, 32'd4, 32'h0000_0000);
    check_op(ALU_MULH, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'h0000_0000); // (-1)*(-1) = 1
    check_op(ALU_MULH, 32'h8000_0000, 32'h8000_0000, 32'h4000_0000); // (-2^31)^2 = 2^62
    check_op(ALU_MULH, 32'h8000_0000, 32'd2, 32'hFFFF_FFFF); // -2^32, sign extended

    check_op(ALU_MULHSU, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFF); // (-1) * (2^32-1)
    check_op(ALU_MULHSU, 32'h8000_0000, 32'h8000_0000, 32'hC000_0000); // -2^31 * 2^31
    check_op(ALU_MULHSU, 32'd2, 32'hFFFF_FFFF, 32'h0000_0001); // b is unsigned

    check_op(ALU_MULHU, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFE);
    check_op(ALU_MULHU, 32'h8000_0000, 32'd2, 32'h0000_0001);
    check_op(ALU_MULHU, 32'd3, 32'd4, 32'h0000_0000);

    check_op(ALU_DIV, 32'd20, 32'd3, 32'd6);
    check_op(ALU_DIV, -32'sd20, 32'd3, -32'sd6); // rounds toward zero
    check_op(ALU_DIV, 32'd20, -32'sd3, -32'sd6);
    check_op(ALU_DIV, -32'sd20, -32'sd3, 32'd6);
    check_op(ALU_DIV, 32'd20, 32'd0, 32'hFFFF_FFFF); // divide by zero
    check_op(ALU_DIV, 32'h8000_0000, 32'hFFFF_FFFF, 32'h8000_0000); // overflow

    check_op(ALU_DIVU, 32'd20, 32'd3, 32'd6);
    check_op(ALU_DIVU, 32'hFFFF_FFFF, 32'd2, 32'h7FFF_FFFF);
    check_op(ALU_DIVU, 32'd20, 32'd0, 32'hFFFF_FFFF); // divide by zero

    check_op(ALU_REM, 32'd20, 32'd3, 32'd2);
    check_op(ALU_REM, -32'sd20, 32'd3, -32'sd2); // sign follows the dividend
    check_op(ALU_REM, 32'd20, -32'sd3, 32'd2);
    check_op(ALU_REM, -32'sd20, -32'sd3, -32'sd2);
    check_op(ALU_REM, 32'd20, 32'd0, 32'd20); // divide by zero returns the dividend
    check_op(ALU_REM, 32'h8000_0000, 32'hFFFF_FFFF, 32'd0); // overflow

    check_op(ALU_REMU, 32'd20, 32'd3, 32'd2);
    check_op(ALU_REMU, 32'hFFFF_FFFF, 32'd16, 32'd15);
    check_op(ALU_REMU, 32'd7, 32'd0, 32'd7); // divide by zero returns the dividend

    finish; // End simulation
  end

endmodule
