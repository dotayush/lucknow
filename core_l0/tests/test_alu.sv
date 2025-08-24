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

  // test case
  initial begin
    $dumpfile("./tests/results/test_alu.vcd");
    $dumpvars(0, test_alu);
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



    finish; // End simulation
  end

endmodule
